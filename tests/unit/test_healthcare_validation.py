"""Unit tests for healthcare validation rules parsing and configuration."""

from __future__ import annotations

import yaml


def _load_rules():
    with open("config/validation_rules.yaml") as f:
        data = yaml.safe_load(f)
    return data["rules"]


class TestHealthcareValidationRules:
    """Verify healthcare validation rules are correctly defined."""

    def test_rules_load_successfully(self):
        rules = _load_rules()
        assert len(rules) > 0

    def test_all_rules_have_required_fields(self):
        rules = _load_rules()
        for rule in rules:
            assert "name" in rule, f"Rule missing name: {rule}"
            assert "type" in rule, f"Rule {rule['name']} missing type"
            assert "severity" in rule, f"Rule {rule['name']} missing severity"
            assert "description" in rule, f"Rule {rule['name']} missing description"

    def test_healthcare_rules_present(self):
        rules = _load_rules()
        rule_names = {r["name"] for r in rules}
        expected = {
            "patients_member_id_not_null",
            "patients_dob_not_null",
            "patients_member_id_unique",
            "medications_ndc_format",
            "providers_npi_format",
            "prescriptions_patient_exists",
            "prescriptions_provider_exists",
            "claims_patient_exists",
            "claims_quantity_valid",
            "claims_days_supply_valid",
            "claims_ingredient_cost_valid",
            "claims_freshness",
            "adherence_pdc_bounds",
            "controlled_substance_dea_required",
        }
        missing = expected - rule_names
        assert not missing, f"Missing healthcare rules: {missing}"

    def test_severity_values_valid(self):
        rules = _load_rules()
        valid_severities = {"critical", "warning", "info"}
        for rule in rules:
            assert (
                rule["severity"] in valid_severities
            ), f"Rule {rule['name']} has invalid severity: {rule['severity']}"

    def test_rule_types_valid(self):
        rules = _load_rules()
        valid_types = {
            "null_check",
            "range_check",
            "referential",
            "duplicate",
            "freshness",
            "custom_sql",
        }
        for rule in rules:
            assert (
                rule["type"] in valid_types
            ), f"Rule {rule['name']} has invalid type: {rule['type']}"

    def test_referential_rules_have_params(self):
        rules = _load_rules()
        for rule in rules:
            if rule["type"] == "referential":
                assert "params" in rule, f"Referential rule {rule['name']} missing params"
                assert "ref_table" in rule["params"], f"Rule {rule['name']} missing ref_table"
                assert "ref_column" in rule["params"], f"Rule {rule['name']} missing ref_column"

    def test_range_rules_have_min_max(self):
        rules = _load_rules()
        for rule in rules:
            if rule["type"] == "range_check":
                assert "params" in rule, f"Range rule {rule['name']} missing params"
                assert "min" in rule["params"], f"Rule {rule['name']} missing min"
                assert "max" in rule["params"], f"Rule {rule['name']} missing max"

    def test_custom_sql_rules_have_sql(self):
        rules = _load_rules()
        for rule in rules:
            if rule["type"] == "custom_sql":
                assert "params" in rule, f"Custom SQL rule {rule['name']} missing params"
                assert "sql" in rule["params"], f"Rule {rule['name']} missing sql"

    def test_total_rule_count(self):
        rules = _load_rules()
        # Original 10 + 14 healthcare = 24
        assert len(rules) >= 24, f"Expected >= 24 rules, got {len(rules)}"

    def test_no_duplicate_rule_names(self):
        rules = _load_rules()
        names = [r["name"] for r in rules]
        assert len(names) == len(set(names)), "Duplicate rule names found"
