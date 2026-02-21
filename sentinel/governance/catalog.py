"""Data catalog engine — schema scanning, PHI/PII classification, lineage."""

from __future__ import annotations

import logging
import re
from datetime import datetime, timezone

logger = logging.getLogger(__name__)

# PHI/PII patterns for auto-classification
PHI_PATTERNS: dict[str, re.Pattern] = {
    "name": re.compile(r"(first_name|last_name|full_name|patient_name)", re.IGNORECASE),
    "dob": re.compile(r"(date_of_birth|dob|birth_date|birthdate)", re.IGNORECASE),
    "ssn": re.compile(r"(ssn|social_security|ssn_last)", re.IGNORECASE),
    "phone": re.compile(r"(phone|fax|mobile|telephone)", re.IGNORECASE),
    "email": re.compile(r"(email|e_mail)", re.IGNORECASE),
    "address": re.compile(r"(address|street|city|zip_code|state_code)", re.IGNORECASE),
    "member_id": re.compile(r"(member_id|patient_id|subscriber_id)", re.IGNORECASE),
}

PII_PATTERNS: dict[str, re.Pattern] = {
    "financial": re.compile(r"(account_number|routing|credit_card|bank)", re.IGNORECASE),
    "credential": re.compile(r"(password|secret|token|api_key)", re.IGNORECASE),
    "identifier": re.compile(r"(ssn|driver_license|passport)", re.IGNORECASE),
}

# Masking rules by PHI category
MASKING_RULES: dict[str, str] = {
    "name": "partial_mask",
    "dob": "full_mask",
    "ssn": "full_mask",
    "phone": "partial_mask",
    "email": "partial_mask",
    "address": "partial_mask",
    "member_id": "hash",
}


class DataCatalogEngine:
    """Manages the data catalog, PHI classification, and lineage tracking."""

    def __init__(self, db):
        self.db = db

    def scan_schema(self, schema_name: str = "dbo") -> dict:
        """Scan database schema and auto-classify PHI/PII columns."""
        sql = """
            SELECT
                TABLE_SCHEMA AS schema_name,
                TABLE_NAME AS table_name,
                COLUMN_NAME AS column_name,
                DATA_TYPE AS data_type
            FROM INFORMATION_SCHEMA.COLUMNS
            WHERE TABLE_SCHEMA = ?
            ORDER BY TABLE_NAME, ORDINAL_POSITION
        """
        rows = self.db.execute_query(sql, (schema_name,))

        classified = 0
        for row in rows:
            column_name = row["column_name"]
            phi_category = self._classify_phi(column_name)
            is_pii = self._classify_pii(column_name)
            masking_rule = MASKING_RULES.get(phi_category) if phi_category else None

            self._upsert_catalog_entry(
                schema_name=row["schema_name"],
                table_name=row["table_name"],
                column_name=column_name,
                data_type=row["data_type"],
                is_phi=phi_category is not None,
                is_pii=is_pii,
                phi_category=phi_category,
                masking_rule=masking_rule,
            )
            if phi_category or is_pii:
                classified += 1

        logger.info(
            "Schema scan complete: %d columns scanned, %d PHI/PII classified",
            len(rows),
            classified,
        )
        return {
            "columns_scanned": len(rows),
            "phi_pii_classified": classified,
            "scanned_at": datetime.now(timezone.utc).isoformat(),
        }

    def get_catalog(self, table_name: str | None = None, phi_only: bool = False) -> list[dict]:
        """Retrieve catalog entries, optionally filtered."""
        conditions = ["1=1"]
        params: list = []

        if table_name:
            conditions.append("table_name = ?")
            params.append(table_name)
        if phi_only:
            conditions.append("is_phi = 1")

        sql = (
            "SELECT id, schema_name, table_name, column_name, data_type, "
            "description, is_phi, is_pii, phi_category, masking_rule, "
            "retention_days, classification, last_scanned_at "
            f"FROM data_catalog WHERE {' AND '.join(conditions)} "
            "ORDER BY table_name, column_name"
        )
        return self.db.execute_query(sql, tuple(params))

    def get_lineage(self, pipeline_name: str | None = None, limit: int = 50) -> list[dict]:
        """Retrieve ETL lineage records."""
        if pipeline_name:
            sql = (
                "SELECT TOP (?) id, pipeline_name, execution_id, source_table, "
                "target_table, started_at, completed_at, status, rows_read, "
                "rows_written, rows_rejected, error_message "
                "FROM data_lineage WHERE pipeline_name = ? "
                "ORDER BY started_at DESC"
            )
            return self.db.execute_query(sql, (limit, pipeline_name))

        sql = (
            "SELECT TOP (?) id, pipeline_name, execution_id, source_table, "
            "target_table, started_at, completed_at, status, rows_read, "
            "rows_written, rows_rejected, error_message "
            "FROM data_lineage ORDER BY started_at DESC"
        )
        return self.db.execute_query(sql, (limit,))

    def record_lineage(
        self,
        pipeline_name: str,
        source_table: str,
        target_table: str,
        rows_read: int = 0,
        rows_written: int = 0,
        rows_rejected: int = 0,
        status: str = "success",
        error_message: str | None = None,
    ) -> int:
        """Record an ETL lineage entry from Python pipelines."""
        sql = """
            INSERT INTO data_lineage
                (pipeline_name, source_table, target_table, status,
                 completed_at, rows_read, rows_written, rows_rejected, error_message)
            OUTPUT INSERTED.id
            VALUES (?, ?, ?, ?, SYSUTCDATETIME(), ?, ?, ?, ?)
        """
        result = self.db.execute_query(
            sql,
            (
                pipeline_name,
                source_table,
                target_table,
                status,
                rows_read,
                rows_written,
                rows_rejected,
                error_message,
            ),
        )
        return result[0]["id"] if result else 0

    def _classify_phi(self, column_name: str) -> str | None:
        """Check if a column name matches PHI patterns."""
        for category, pattern in PHI_PATTERNS.items():
            if pattern.search(column_name):
                return category
        return None

    def _classify_pii(self, column_name: str) -> bool:
        """Check if a column name matches PII patterns."""
        for pattern in PII_PATTERNS.values():
            if pattern.search(column_name):
                return True
        return False

    def mask_patients_for_export(self) -> list[dict]:
        """Return patient data with PHI fields masked for safe export."""
        rows = self.db.execute_proc("sp_mask_phi_for_export")
        count = len(rows) if rows else 0
        self.log_phi_access(
            user="system",
            action="MASKED_EXPORT",
            table="patients",
            count=count,
            justification="PHI masked export via governance API",
        )
        return rows or []

    def log_phi_access(
        self,
        user: str,
        action: str,
        table: str,
        count: int,
        justification: str,
    ) -> None:
        """Record a PHI access event in the audit log."""
        try:
            self.db.execute_nonquery(
                "INSERT INTO phi_access_log "
                "(user_name, action, table_name, record_count, "
                "justification, access_time) "
                "VALUES (?, ?, ?, ?, ?, SYSUTCDATETIME())",
                (user, action, table, count, justification),
            )
        except Exception as e:
            logger.warning("Failed to log PHI access: %s", e)

    def _upsert_catalog_entry(self, **kwargs) -> None:
        """Insert or update a catalog entry."""
        sql = """
            MERGE INTO data_catalog AS tgt
            USING (SELECT ? AS schema_name, ? AS table_name, ? AS column_name) AS src
            ON tgt.schema_name = src.schema_name
               AND tgt.table_name = src.table_name
               AND ISNULL(tgt.column_name, '') = ISNULL(src.column_name, '')
            WHEN MATCHED THEN UPDATE SET
                data_type = ?,
                is_phi = ?,
                is_pii = ?,
                phi_category = ?,
                masking_rule = ?,
                last_scanned_at = SYSUTCDATETIME(),
                updated_at = SYSUTCDATETIME()
            WHEN NOT MATCHED THEN INSERT
                (schema_name, table_name, column_name, data_type,
                 is_phi, is_pii, phi_category, masking_rule,
                 classification, last_scanned_at)
            VALUES (?, ?, ?, ?, ?, ?, ?, ?,
                    CASE WHEN ? = 1 THEN 'restricted' ELSE 'internal' END,
                    SYSUTCDATETIME());
        """
        self.db.execute_nonquery(
            sql,
            (
                kwargs["schema_name"],
                kwargs["table_name"],
                kwargs["column_name"],
                # UPDATE SET params
                kwargs["data_type"],
                kwargs["is_phi"],
                kwargs["is_pii"],
                kwargs["phi_category"],
                kwargs["masking_rule"],
                # INSERT VALUES params
                kwargs["schema_name"],
                kwargs["table_name"],
                kwargs["column_name"],
                kwargs["data_type"],
                kwargs["is_phi"],
                kwargs["is_pii"],
                kwargs["phi_category"],
                kwargs["masking_rule"],
                kwargs["is_phi"],  # for CASE expression
            ),
        )
