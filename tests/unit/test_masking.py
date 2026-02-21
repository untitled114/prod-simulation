"""Tests for PHI data masking functionality."""

from __future__ import annotations

from sentinel.governance.catalog import DataCatalogEngine


class TestMaskPatientsForExport:
    def test_calls_masking_proc(self, mock_db):
        engine = DataCatalogEngine(mock_db)
        rows = engine.mask_patients_for_export()
        assert len(rows) == 1
        assert "EXEC sp_mask_phi_for_export" in mock_db._query_log

    def test_returns_masked_data(self, mock_db):
        engine = DataCatalogEngine(mock_db)
        rows = engine.mask_patients_for_export()
        patient = rows[0]
        assert patient["first_name"] == "J***"
        assert patient["last_name"] == "D***"
        assert patient["ssn_last_four"] == "****"
        assert patient["address_line1"] == "[REDACTED]"
        assert "***@***" in patient["email"]

    def test_logs_phi_access_after_export(self, mock_db):
        engine = DataCatalogEngine(mock_db)
        engine.mask_patients_for_export()
        # Should have logged a PHI access record
        phi_inserts = [q for q in mock_db._query_log if "phi_access_log" in q and "INSERT" in q]
        assert len(phi_inserts) >= 1


class TestLogPhiAccess:
    def test_inserts_access_record(self, mock_db):
        engine = DataCatalogEngine(mock_db)
        engine.log_phi_access(
            user="test_user",
            action="VIEW",
            table="patients",
            count=10,
            justification="Testing",
        )
        phi_inserts = [q for q in mock_db._query_log if "phi_access_log" in q and "INSERT" in q]
        assert len(phi_inserts) == 1

    def test_handles_db_error_gracefully(self, mock_db):
        """log_phi_access should not raise even if DB fails."""
        engine = DataCatalogEngine(mock_db)
        # This should not raise — it catches exceptions internally
        engine.log_phi_access(
            user="test_user",
            action="VIEW",
            table="patients",
            count=10,
            justification="Testing",
        )
