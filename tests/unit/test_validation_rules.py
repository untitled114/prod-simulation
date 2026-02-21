"""Tests for validation rule types."""

from unittest.mock import MagicMock

import pytest

from sentinel.validation.rules import (
    CustomSqlRule,
    DuplicateRule,
    FreshnessRule,
    NullCheckRule,
    RangeCheckRule,
    ReferentialRule,
    create_rule,
)


def make_db(query_results=None):
    """Create a mock DB that returns given results for execute_query."""
    db = MagicMock()
    db.execute_query.return_value = query_results if query_results is not None else [{"cnt": 0}]
    return db


class TestNullCheckRule:
    def test_no_nulls(self):
        db = make_db([{"cnt": 0}])
        rule = NullCheckRule("test", "null_check", "users", "email", "critical", {}, "")
        result = rule.execute(db)
        assert result["passed"] is True
        assert result["violation_count"] == 0

    def test_nulls_found(self):
        db = MagicMock()
        db.execute_query.side_effect = [[{"cnt": 3}], [{"id": 1}, {"id": 2}, {"id": 3}]]
        rule = NullCheckRule("test", "null_check", "users", "email", "critical", {}, "")
        result = rule.execute(db)
        assert result["passed"] is False
        assert result["violation_count"] == 3


class TestRangeCheckRule:
    def test_all_in_range(self):
        db = make_db([{"cnt": 0}])
        rule = RangeCheckRule(
            "test", "range_check", "orders", "total", "warning", {"min": 0, "max": 1000}, ""
        )
        result = rule.execute(db)
        assert result["passed"] is True

    def test_out_of_range(self):
        db = MagicMock()
        db.execute_query.side_effect = [[{"cnt": 5}], [{"total": -10}, {"total": 99999}]]
        rule = RangeCheckRule(
            "test", "range_check", "orders", "total", "warning", {"min": 0, "max": 1000}, ""
        )
        result = rule.execute(db)
        assert result["passed"] is False
        assert result["violation_count"] == 5

    def test_no_bounds(self):
        db = make_db()
        rule = RangeCheckRule("test", "range_check", "orders", "total", "warning", {}, "")
        result = rule.execute(db)
        assert result["passed"] is True


class TestReferentialRule:
    def test_no_orphans(self):
        db = make_db([{"cnt": 0}])
        rule = ReferentialRule(
            "test",
            "referential",
            "orders",
            "customer_id",
            "critical",
            {"ref_table": "customers", "ref_column": "id"},
            "",
        )
        result = rule.execute(db)
        assert result["passed"] is True

    def test_orphans_found(self):
        db = MagicMock()
        db.execute_query.side_effect = [[{"cnt": 2}], [{"customer_id": 999}, {"customer_id": 998}]]
        rule = ReferentialRule(
            "test",
            "referential",
            "orders",
            "customer_id",
            "critical",
            {"ref_table": "customers", "ref_column": "id"},
            "",
        )
        result = rule.execute(db)
        assert result["passed"] is False


class TestDuplicateRule:
    def test_no_duplicates(self):
        db = make_db([])
        rule = DuplicateRule(
            "test", "duplicate", "users", "email", "warning", {"columns": ["email"]}, ""
        )
        result = rule.execute(db)
        assert result["passed"] is True

    def test_duplicates_found(self):
        db = make_db([{"email": "dup@test.com", "cnt": 3}])
        rule = DuplicateRule(
            "test", "duplicate", "users", "email", "warning", {"columns": ["email"]}, ""
        )
        result = rule.execute(db)
        assert result["passed"] is False
        assert result["violation_count"] == 1


class TestFreshnessRule:
    def test_fresh_data(self):
        db = make_db([{"cnt": 10}])
        rule = FreshnessRule(
            "test", "freshness", "events", "created_at", "warning", {"max_age_hours": 24}, ""
        )
        result = rule.execute(db)
        assert result["passed"] is True

    def test_stale_data(self):
        db = make_db([{"cnt": 0}])
        rule = FreshnessRule(
            "test", "freshness", "events", "created_at", "warning", {"max_age_hours": 24}, ""
        )
        result = rule.execute(db)
        assert result["passed"] is False


class TestCustomSqlRule:
    def test_no_violations(self):
        db = make_db([{"violation_count": 0}])
        rule = CustomSqlRule(
            "test", "custom_sql", "", "", "warning", {"sql": "SELECT 0 AS violation_count"}, ""
        )
        result = rule.execute(db)
        assert result["passed"] is True

    def test_violations_found(self):
        db = make_db([{"violation_count": 5}])
        rule = CustomSqlRule(
            "test", "custom_sql", "", "", "warning", {"sql": "SELECT 5 AS violation_count"}, ""
        )
        result = rule.execute(db)
        assert result["passed"] is False

    def test_empty_sql(self):
        db = make_db()
        rule = CustomSqlRule("test", "custom_sql", "", "", "warning", {}, "")
        result = rule.execute(db)
        assert result["passed"] is True


class TestCreateRule:
    def test_create_null_check(self):
        rule = create_rule({"name": "test", "type": "null_check", "table": "t", "column": "c"})
        assert isinstance(rule, NullCheckRule)

    def test_unknown_type(self):
        with pytest.raises(ValueError, match="Unknown rule type"):
            create_rule({"name": "test", "type": "nonexistent"})
