"""Built-in chaos scenarios that simulate production problems."""

from __future__ import annotations

import logging
from typing import Any

from sentinel.core.exceptions import DatabaseQueryError
from sentinel.db.connection import ConnectionManager

logger = logging.getLogger(__name__)


class ChaosScenario:
    """Base chaos scenario."""

    name: str = "base"
    description: str = ""
    severity: str = "medium"

    def execute(self, db: ConnectionManager) -> dict[str, Any]:
        raise NotImplementedError


class LongRunningQuery(ChaosScenario):
    """Simulate a query that runs for a long time, consuming resources."""

    name = "Long Running Query"
    description = "Runs a WAITFOR + heavy computation to simulate a stuck query"
    severity = "medium"

    def execute(self, db: ConnectionManager) -> dict[str, Any]:
        try:
            db.execute_nonquery("WAITFOR DELAY '00:00:45'")
            return {"triggered": True, "detail": "45-second blocking query executed"}
        except DatabaseQueryError as e:
            return {"triggered": True, "detail": f"Long query started (may timeout): {e}"}


class DeadlockSimulation(ChaosScenario):
    """Create conditions that can lead to deadlocks."""

    name = "Deadlock"
    description = "Creates competing transactions to trigger a deadlock"
    severity = "high"

    def execute(self, db: ConnectionManager) -> dict[str, Any]:
        # Insert two rows, then update in crossed order from different connections
        try:
            db.execute_nonquery(
                "IF NOT EXISTS (SELECT 1 FROM customers WHERE email = 'deadlock_a@chaos.test') "
                "INSERT INTO customers (name, email, region) "
                "VALUES ('Deadlock A', 'deadlock_a@chaos.test', 'CHAOS')"
            )
            db.execute_nonquery(
                "IF NOT EXISTS (SELECT 1 FROM customers WHERE email = 'deadlock_b@chaos.test') "
                "INSERT INTO customers (name, email, region) "
                "VALUES ('Deadlock B', 'deadlock_b@chaos.test', 'CHAOS')"
            )
            return {
                "triggered": True,
                "detail": "Deadlock-prone rows created. Concurrent updates may deadlock.",
            }
        except DatabaseQueryError as e:
            return {"triggered": False, "detail": str(e)}


class DataCorruption(ChaosScenario):
    """Introduce invalid data to trigger validation failures."""

    name = "Data Corruption"
    description = "Inserts rows with invalid/NULL values to trigger validation alerts"
    severity = "high"

    def execute(self, db: ConnectionManager) -> dict[str, Any]:
        corruptions = []

        # Negative order total
        db.execute_nonquery(
            "INSERT INTO orders (customer_id, total_amount, status) "
            "VALUES (1, -999.99, 'corrupted')"
        )
        corruptions.append("Negative order total (-999.99)")

        # Orphaned order item (non-existent order)
        db.execute_nonquery(
            "SET IDENTITY_INSERT orders ON; "
            "IF NOT EXISTS (SELECT 1 FROM orders WHERE id = 99999) "
            "INSERT INTO orders (id, customer_id, total_amount, status) "
            "VALUES (99999, 1, 0, 'phantom'); "
            "SET IDENTITY_INSERT orders OFF; "
            "INSERT INTO order_items (order_id, product, quantity, unit_price) "
            "VALUES (99999, 'CHAOS_ITEM', 0, -1.00)"
        )
        corruptions.append("Zero-quantity item with negative price")

        # Duplicate email
        db.execute_nonquery(
            "INSERT INTO customers (name, email, region) "
            "VALUES ('Chaos Clone', 'customer1@example.com', 'CHAOS')"
        )
        corruptions.append("Duplicate customer email")

        return {"triggered": True, "detail": f"Corruptions injected: {corruptions}"}


class OrphanedRecords(ChaosScenario):
    """Create orphaned records that break referential integrity."""

    name = "Orphaned Records"
    description = "Creates order items pointing to non-existent orders"
    severity = "medium"

    def execute(self, db: ConnectionManager) -> dict[str, Any]:
        # Temporarily disable FK to insert orphan, then re-enable
        try:
            db.execute_nonquery("ALTER TABLE order_items NOCHECK CONSTRAINT ALL")
            db.execute_nonquery(
                "INSERT INTO order_items (order_id, product, quantity, unit_price) "
                "VALUES (88888, 'ORPHAN_PRODUCT', 1, 10.00)"
            )
            db.execute_nonquery("ALTER TABLE order_items CHECK CONSTRAINT ALL")
            return {
                "triggered": True,
                "detail": "Orphaned order_item created (order_id=88888 doesn't exist)",
            }
        except DatabaseQueryError as e:
            # Re-enable constraints on failure
            try:
                db.execute_nonquery("ALTER TABLE order_items CHECK CONSTRAINT ALL")
            except DatabaseQueryError:
                pass
            return {"triggered": False, "detail": str(e)}


class JobFailure(ChaosScenario):
    """Simulate a scheduled job failure."""

    name = "Job Failure"
    description = "Inserts a fake failed job run record"
    severity = "low"

    def execute(self, db: ConnectionManager) -> dict[str, Any]:
        db.execute_nonquery(
            "INSERT INTO job_runs (job_name, status, error_message, completed_at, duration_ms) "
            "VALUES ('chaos_simulated_job', 'failed', "
            "'CHAOS: Simulated job failure — disk I/O timeout', "
            "SYSUTCDATETIME(), 15000)"
        )
        return {"triggered": True, "detail": "Failed job record inserted for 'chaos_simulated_job'"}


class ConnectionFlood(ChaosScenario):
    """Open many connections to stress connection pool limits."""

    name = "Connection Flood"
    description = "Opens 20 concurrent connections to stress the pool"
    severity = "high"

    def execute(self, db: ConnectionManager) -> dict[str, Any]:
        opened = 0
        conns = []
        try:
            for _ in range(20):
                conn = db.get_connection()
                conns.append(conn)
                opened += 1
            return {"triggered": True, "detail": f"Opened {opened} connections (will auto-close)"}
        except DatabaseQueryError as e:
            return {"triggered": True, "detail": f"Opened {opened} connections before error: {e}"}
        finally:
            for c in conns:
                try:
                    c.close()
                except Exception:
                    pass


class ClaimVolumeSpike(ChaosScenario):
    """Simulate a sudden flood of pharmacy claims with mixed statuses."""

    name = "Claim Volume Spike"
    description = (
        "Bulk inserts ~200 pharmacy claims with mixed statuses to simulate processing flood"
    )
    severity = "high"

    def execute(self, db: ConnectionManager) -> dict[str, Any]:
        try:
            db.execute_nonquery("""
                DECLARE @i INT = 0;
                WHILE @i < 200
                BEGIN
                    INSERT INTO pharmacy_claims
                        (claim_number, patient_id, medication_id, pharmacy_id,
                         prescriber_id, service_date, quantity_dispensed,
                         days_supply, ingredient_cost, dispensing_fee,
                         copay_amount, plan_paid_amount, claim_status)
                    VALUES (
                        'CHAOS-' + RIGHT('000000' + CAST(@i AS VARCHAR), 6),
                        (SELECT TOP 1 id FROM patients ORDER BY NEWID()),
                        (SELECT TOP 1 id FROM medications ORDER BY NEWID()),
                        (SELECT TOP 1 id FROM pharmacies ORDER BY NEWID()),
                        (SELECT TOP 1 id FROM providers ORDER BY NEWID()),
                        CAST(GETDATE() AS DATE),
                        CASE WHEN @i % 5 = 0 THEN 999 ELSE 30 END,
                        30,
                        ROUND(RAND() * 500, 2),
                        2.50,
                        ROUND(RAND() * 50, 2),
                        ROUND(RAND() * 400, 2),
                        CASE
                            WHEN @i % 7 = 0 THEN 'rejected'
                            WHEN @i % 11 = 0 THEN 'pending'
                            ELSE 'paid'
                        END
                    );
                    SET @i = @i + 1;
                END
                """)
            return {
                "triggered": True,
                "detail": "Injected ~200 pharmacy claims (mix of paid/rejected/pending)",
            }
        except DatabaseQueryError as e:
            return {"triggered": True, "detail": f"Claim spike started (partial): {e}"}


class PhiExposureEvent(ChaosScenario):
    """Simulate a suspicious PHI access pattern — bulk patient record access."""

    name = "PHI Exposure"
    description = "Inserts 100 suspicious PHI access records from a single user — HIPAA audit event"
    severity = "high"

    def execute(self, db: ConnectionManager) -> dict[str, Any]:
        try:
            db.execute_nonquery("""
                DECLARE @i INT = 0;
                WHILE @i < 100
                BEGIN
                    INSERT INTO phi_access_log
                        (user_name, action, table_name, record_count,
                         justification, access_time)
                    VALUES (
                        'chaos_user_suspect',
                        'BULK_EXPORT',
                        'patients',
                        CAST(50 + @i AS INT),
                        'CHAOS: Simulated suspicious bulk PHI access',
                        DATEADD(SECOND, @i, SYSUTCDATETIME())
                    );
                    SET @i = @i + 1;
                END
                """)
            return {
                "triggered": True,
                "detail": (
                    "100 suspicious PHI access records inserted "
                    "(single user bulk-exporting patient data)"
                ),
            }
        except DatabaseQueryError as e:
            return {"triggered": True, "detail": f"PHI exposure event started: {e}"}


class FormularyChangeCascade(ChaosScenario):
    """Simulate mid-year formulary upheaval — tier changes + prior auth requirements."""

    name = "Formulary Change"
    description = (
        "Moves 10 popular generics from tier 1 to tier 3 "
        "and sets requires_prior_auth — simulates mid-year formulary upheaval"
    )
    severity = "medium"

    def execute(self, db: ConnectionManager) -> dict[str, Any]:
        try:
            result = db.execute_query("""
                UPDATE TOP (10) medications
                SET formulary_tier = 3,
                    requires_prior_auth = 1
                OUTPUT INSERTED.drug_name
                WHERE formulary_tier = 1
                  AND dea_schedule = 0
                """)
            affected = [r["drug_name"] for r in result] if result else []
            return {
                "triggered": True,
                "detail": (
                    f"Moved {len(affected)} medications to tier 3 "
                    f"with prior auth required: {affected[:5]}"
                ),
            }
        except DatabaseQueryError as e:
            return {"triggered": True, "detail": f"Formulary cascade started: {e}"}


BUILTIN_SCENARIOS: dict[str, type[ChaosScenario]] = {
    "Long Running Query": LongRunningQuery,
    "Deadlock": DeadlockSimulation,
    "Data Corruption": DataCorruption,
    "Orphaned Records": OrphanedRecords,
    "Job Failure": JobFailure,
    "Connection Flood": ConnectionFlood,
    "Claim Volume Spike": ClaimVolumeSpike,
    "PHI Exposure": PhiExposureEvent,
    "Formulary Change": FormularyChangeCascade,
}
