"""Shared test fixtures and mock database connection."""

from __future__ import annotations

from unittest.mock import MagicMock

import pytest

from sentinel.config.models import (
    SentinelConfig,
    ThresholdConfig,
    ValidationRuleConfig,
)


class MockConnectionManager:
    """Mock database that stores data in-memory for testing."""

    def __init__(self):
        self._tables: dict[str, list[dict]] = {
            "health_snapshots": [],
            "incidents": [],
            "job_runs": [],
            "validation_results": [],
            "remediation_log": [],
            "postmortems": [],
            "data_catalog": [],
            "data_lineage": [],
            "phi_access_log": [],
        }
        self._id_counters: dict[str, int] = {}
        self._query_log: list[str] = []

    def execute_query(self, sql: str, params: tuple = ()) -> list[dict]:
        self._query_log.append(sql)
        # Healthcare mock handlers
        if "pharmacy_claims" in sql and "COUNT(*)" in sql and "service_date" in sql:
            return [
                {
                    "claims_today": 150,
                    "rejected_count": 8,
                    "rejection_rate": 5.3,
                    "generic_count": 120,
                    "generic_rate": 80.0,
                }
            ]
        if "patient_adherence" in sql and "AVG" in sql:
            return [
                {
                    "avg_pdc": 0.82,
                    "non_adherent_count": 15,
                    "total_patients": 100,
                }
            ]
        # Return mock data based on query patterns
        if "SELECT 1 AS ok" in sql:
            return [{"ok": 1}]
        if "@@VERSION" in sql:
            return [
                {
                    "version": "Mock SQL Server",
                    "server_name": "test",
                    "current_db": "SentinelDB",
                    "server_time": "2026-02-21",
                }
            ]
        if "health_snapshots" in sql and "ORDER BY" in sql:
            return (
                self._tables.get("health_snapshots", [])[-1:]
                if self._tables.get("health_snapshots")
                else []
            )
        if "INSERT INTO incidents" in sql and "OUTPUT INSERTED" in sql:
            new_id = self._next_id("incidents")
            record = {
                "id": new_id,
                "incident_type": params[0] if params else "",
                "severity": params[1] if len(params) > 1 else "warning",
                "status": "detected",
                "title": params[2] if len(params) > 2 else "",
            }
            self._tables["incidents"].append(record)
            return [record]
        if "incidents" in sql and "NOT IN" in sql:
            return [
                i
                for i in self._tables.get("incidents", [])
                if i.get("status") not in ("resolved", "escalated")
            ]
        if "incidents" in sql and "ORDER BY" in sql and "TOP" in sql:
            return self._tables.get("incidents", [])[-1:] if self._tables.get("incidents") else []
        if "incidents" in sql and "WHERE id" in sql:
            target_id = params[-1] if params else None
            return [i for i in self._tables.get("incidents", []) if i.get("id") == target_id][:1]
        if "incidents" in sql:
            return self._tables.get("incidents", [])
        if "job_runs" in sql:
            return self._tables.get("job_runs", [])
        if "validation_results" in sql:
            return self._tables.get("validation_results", [])
        if "postmortems" in sql:
            return self._tables.get("postmortems", [])
        if "INFORMATION_SCHEMA.COLUMNS" in sql:
            return [
                {
                    "schema_name": "dbo",
                    "table_name": "patients",
                    "column_name": "first_name",
                    "data_type": "nvarchar",
                },
                {
                    "schema_name": "dbo",
                    "table_name": "patients",
                    "column_name": "last_name",
                    "data_type": "nvarchar",
                },
                {
                    "schema_name": "dbo",
                    "table_name": "patients",
                    "column_name": "date_of_birth",
                    "data_type": "date",
                },
                {
                    "schema_name": "dbo",
                    "table_name": "patients",
                    "column_name": "member_id",
                    "data_type": "varchar",
                },
                {
                    "schema_name": "dbo",
                    "table_name": "patients",
                    "column_name": "email",
                    "data_type": "varchar",
                },
                {
                    "schema_name": "dbo",
                    "table_name": "patients",
                    "column_name": "phone",
                    "data_type": "varchar",
                },
                {
                    "schema_name": "dbo",
                    "table_name": "pharmacy_claims",
                    "column_name": "claim_number",
                    "data_type": "varchar",
                },
                {
                    "schema_name": "dbo",
                    "table_name": "pharmacy_claims",
                    "column_name": "service_date",
                    "data_type": "date",
                },
            ]
        if "data_catalog" in sql and "is_phi" in sql:
            return [e for e in self._tables.get("data_catalog", []) if e.get("is_phi")]
        if "data_catalog" in sql:
            return self._tables.get("data_catalog", [])
        if "data_lineage" in sql and "ORDER BY" in sql:
            return self._tables.get("data_lineage", [])
        return []

    def execute_nonquery(self, sql: str, params: tuple = ()) -> int:
        self._query_log.append(sql)
        # Handle inserts for key tables
        if "INSERT INTO incidents" in sql:
            new_id = self._next_id("incidents")
            record = {
                "id": new_id,
                "incident_type": params[0] if params else "",
                "severity": params[1] if len(params) > 1 else "warning",
                "status": "detected",
                "title": params[2] if len(params) > 2 else "",
            }
            self._tables["incidents"].append(record)
            return 1
        if "INSERT INTO job_runs" in sql:
            new_id = self._next_id("job_runs")
            self._tables["job_runs"].append(
                {"id": new_id, "job_name": params[0] if params else "", "status": "running"}
            )
            return 1
        if "INSERT INTO validation_results" in sql:
            new_id = self._next_id("validation_results")
            self._tables["validation_results"].append({"id": new_id})
            return 1
        if "INSERT INTO remediation_log" in sql:
            self._tables["remediation_log"].append({"incident_id": params[0] if params else 0})
            return 1
        if "MERGE INTO data_catalog" in sql or "INSERT INTO data_catalog" in sql:
            # Store catalog entry from upsert
            entry = {
                "id": self._next_id("data_catalog"),
                "schema_name": params[0] if params else "dbo",
                "table_name": params[1] if len(params) > 1 else "",
                "column_name": params[2] if len(params) > 2 else None,
                "is_phi": params[4] if len(params) > 4 else False,
                "is_pii": params[5] if len(params) > 5 else False,
                "phi_category": params[6] if len(params) > 6 else None,
            }
            self._tables["data_catalog"].append(entry)
            return 1
        if "INSERT INTO data_lineage" in sql:
            new_id = self._next_id("data_lineage")
            self._tables["data_lineage"].append(
                {
                    "id": new_id,
                    "pipeline_name": params[0] if params else "",
                    "source_table": params[1] if len(params) > 1 else "",
                    "target_table": params[2] if len(params) > 2 else "",
                    "status": params[3] if len(params) > 3 else "success",
                }
            )
            return 1
        if "INSERT INTO postmortems" in sql:
            self._tables["postmortems"].append({"incident_id": params[0] if params else 0})
            return 1
        if "UPDATE incidents" in sql:
            # Simple status update
            for inc in self._tables.get("incidents", []):
                if params and inc.get("id") == params[-1]:
                    inc["status"] = params[0]
            return 1
        return 0

    def execute_proc(self, proc_name: str, params: tuple = ()) -> list[dict]:
        self._query_log.append(f"EXEC {proc_name}")
        if proc_name == "sp_mask_phi_for_export":
            return [
                {
                    "member_id": "A1B2C3D4E5F6",
                    "first_name": "J***",
                    "last_name": "D***",
                    "date_of_birth": "1990-01-01",
                    "ssn_last_four": "****",
                    "phone": "***-***-1234",
                    "email": "j***@***",
                    "address_line1": "[REDACTED]",
                    "city": "Springfield",
                    "state_code": "IL",
                    "zip_code": "62701",
                    "plan_type": "PPO",
                    "group_number": "GRP001",
                    "effective_date": "2025-01-01",
                    "termination_date": None,
                    "is_active": True,
                }
            ]
        if proc_name == "sp_audit_phi_access":
            return []
        if proc_name == "sp_capture_health_snapshot":
            snapshot = {
                "id": self._next_id("health_snapshots"),
                "cpu_percent": 45.0,
                "memory_used_mb": 2048.0,
                "memory_total_mb": 8192.0,
                "connection_count": 25,
                "blocking_count": 0,
                "long_query_count": 0,
                "tempdb_used_mb": 100.0,
                "avg_wait_ms": 5.0,
                "status": "healthy",
            }
            self._tables["health_snapshots"].append(snapshot)
            return [snapshot]
        if proc_name == "sp_cleanup_stale_sessions":
            return [{"sessions_killed": 0}]
        return []

    def get_connection(self):
        return MagicMock()

    def test_connection(self) -> bool:
        return True

    def _next_id(self, table: str) -> int:
        self._id_counters[table] = self._id_counters.get(table, 0) + 1
        return self._id_counters[table]


@pytest.fixture
def mock_db() -> MockConnectionManager:
    return MockConnectionManager()


@pytest.fixture
def config() -> SentinelConfig:
    return SentinelConfig(
        thresholds=ThresholdConfig(
            cpu_percent_warning=70.0,
            cpu_percent_critical=90.0,
            memory_percent_warning=75.0,
            memory_percent_critical=90.0,
        ),
        validation_rules=[
            ValidationRuleConfig(
                name="test_null_check",
                type="null_check",
                table="customers",
                column="email",
                severity="critical",
                description="Email must not be NULL",
            ),
            ValidationRuleConfig(
                name="test_range_check",
                type="range_check",
                table="orders",
                column="total_amount",
                severity="warning",
                params={"min": 0, "max": 100000},
                description="Order total in valid range",
            ),
        ],
    )
