"""Unit tests for data governance — PHI classification, catalog, lineage."""

from __future__ import annotations

import re

from sentinel.governance.catalog import (
    MASKING_RULES,
    PHI_PATTERNS,
    PII_PATTERNS,
    DataCatalogEngine,
)


class TestPhiClassification:
    """Test PHI/PII auto-classification patterns."""

    def test_phi_detects_first_name(self):
        for pattern in PHI_PATTERNS.values():
            if pattern.search("first_name"):
                return
        raise AssertionError("first_name not detected as PHI")

    def test_phi_detects_last_name(self):
        for pattern in PHI_PATTERNS.values():
            if pattern.search("last_name"):
                return
        raise AssertionError("last_name not detected as PHI")

    def test_phi_detects_date_of_birth(self):
        for pattern in PHI_PATTERNS.values():
            if pattern.search("date_of_birth"):
                return
        raise AssertionError("date_of_birth not detected as PHI")

    def test_phi_detects_ssn(self):
        for pattern in PHI_PATTERNS.values():
            if pattern.search("ssn_last_four"):
                return
        raise AssertionError("ssn_last_four not detected as PHI")

    def test_phi_detects_phone(self):
        for pattern in PHI_PATTERNS.values():
            if pattern.search("phone"):
                return
        raise AssertionError("phone not detected as PHI")

    def test_phi_detects_email(self):
        for pattern in PHI_PATTERNS.values():
            if pattern.search("email"):
                return
        raise AssertionError("email not detected as PHI")

    def test_phi_detects_member_id(self):
        for pattern in PHI_PATTERNS.values():
            if pattern.search("member_id"):
                return
        raise AssertionError("member_id not detected as PHI")

    def test_phi_does_not_flag_claim_number(self):
        engine = DataCatalogEngine(db=None)
        assert engine._classify_phi("claim_number") is None

    def test_phi_does_not_flag_ingredient_cost(self):
        engine = DataCatalogEngine(db=None)
        assert engine._classify_phi("ingredient_cost") is None

    def test_pii_detects_password(self):
        for pattern in PII_PATTERNS.values():
            if pattern.search("password"):
                return
        raise AssertionError("password not detected as PII")

    def test_pii_does_not_flag_drug_name(self):
        engine = DataCatalogEngine(db=None)
        assert engine._classify_pii("drug_name") is False

    def test_masking_rules_exist_for_phi_categories(self):
        for category in PHI_PATTERNS:
            assert category in MASKING_RULES, f"No masking rule for PHI category: {category}"

    def test_phi_patterns_are_valid_regex(self):
        for name, pattern in PHI_PATTERNS.items():
            assert isinstance(pattern, re.Pattern), f"{name} is not a compiled regex"

    def test_pii_patterns_are_valid_regex(self):
        for name, pattern in PII_PATTERNS.items():
            assert isinstance(pattern, re.Pattern), f"{name} is not a compiled regex"


class TestDataCatalogEngine:
    """Test catalog engine operations."""

    def test_scan_schema(self, mock_db):
        engine = DataCatalogEngine(mock_db)
        result = engine.scan_schema("dbo")

        assert result["columns_scanned"] == 8
        assert result["phi_pii_classified"] > 0
        assert "scanned_at" in result

    def test_scan_classifies_phi_columns(self, mock_db):
        engine = DataCatalogEngine(mock_db)
        engine.scan_schema("dbo")

        # Check that PHI columns were stored
        phi_entries = [e for e in mock_db._tables["data_catalog"] if e.get("is_phi")]
        assert len(phi_entries) >= 4  # first_name, last_name, dob, member_id, email, phone

    def test_get_catalog_returns_all(self, mock_db):
        engine = DataCatalogEngine(mock_db)
        engine.scan_schema("dbo")
        entries = engine.get_catalog()
        assert isinstance(entries, list)

    def test_get_catalog_phi_only(self, mock_db):
        engine = DataCatalogEngine(mock_db)
        engine.scan_schema("dbo")
        phi_entries = engine.get_catalog(phi_only=True)
        assert isinstance(phi_entries, list)

    def test_get_lineage_empty(self, mock_db):
        engine = DataCatalogEngine(mock_db)
        lineage = engine.get_lineage()
        assert isinstance(lineage, list)

    def test_classify_phi_returns_category(self):
        engine = DataCatalogEngine(db=None)
        assert engine._classify_phi("first_name") == "name"
        assert engine._classify_phi("date_of_birth") == "dob"
        assert engine._classify_phi("ssn_last_four") == "ssn"
        assert engine._classify_phi("email") == "email"

    def test_classify_phi_returns_none_for_non_phi(self):
        engine = DataCatalogEngine(db=None)
        assert engine._classify_phi("service_date") is None
        assert engine._classify_phi("quantity_dispensed") is None
        assert engine._classify_phi("ndc_code") is None
