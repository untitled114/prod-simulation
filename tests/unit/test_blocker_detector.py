"""Tests for BlockerDetector — blocking chain detection."""

from __future__ import annotations

from unittest.mock import MagicMock

import pytest

from sentinel.core.exceptions import DatabaseQueryError
from sentinel.monitor.blocker_detector import BlockerDetector


@pytest.fixture
def detector(mock_db):
    return BlockerDetector(mock_db)


def _mock_chains():
    """Sample blocking chain data."""
    return [
        {
            "session_id": 55,
            "blocking_session_id": 0,
            "root_blocker_id": 55,
            "chain_depth": 0,
            "wait_type": "NONE",
            "sql_text": "UPDATE accounts SET balance = 0",
        },
        {
            "session_id": 60,
            "blocking_session_id": 55,
            "root_blocker_id": 55,
            "chain_depth": 1,
            "wait_type": "LCK_M_X",
            "sql_text": "SELECT * FROM accounts",
        },
        {
            "session_id": 61,
            "blocking_session_id": 55,
            "root_blocker_id": 55,
            "chain_depth": 1,
            "wait_type": "LCK_M_S",
            "sql_text": "SELECT * FROM accounts WHERE id = 1",
        },
    ]


class TestDetect:
    def test_no_blocking_returns_empty(self, detector, mock_db):
        mock_db.execute_query = MagicMock(return_value=[])
        result = detector.detect()
        assert result == []

    def test_blocking_chains_returned(self, detector, mock_db):
        chains = _mock_chains()
        mock_db.execute_query = MagicMock(return_value=chains)
        result = detector.detect()
        assert len(result) == 3
        assert result[0]["session_id"] == 55

    def test_db_error_returns_empty(self, detector, mock_db):
        mock_db.execute_query = MagicMock(side_effect=DatabaseQueryError("timeout"))
        result = detector.detect()
        assert result == []


class TestGetRootBlockers:
    def test_filters_to_depth_zero(self, detector, mock_db):
        mock_db.execute_query = MagicMock(return_value=_mock_chains())
        roots = detector.get_root_blockers()
        assert len(roots) == 1
        assert roots[0]["chain_depth"] == 0
        assert roots[0]["session_id"] == 55

    def test_no_chains_returns_empty(self, detector, mock_db):
        mock_db.execute_query = MagicMock(return_value=[])
        assert detector.get_root_blockers() == []


class TestGetChainSummary:
    def test_no_blocking(self, detector, mock_db):
        mock_db.execute_query = MagicMock(return_value=[])
        summary = detector.get_chain_summary()
        assert summary["blocking"] is False
        assert summary["chains"] == 0
        assert summary["total_blocked"] == 0
        assert summary["max_depth"] == 0

    def test_blocking_summary(self, detector, mock_db):
        mock_db.execute_query = MagicMock(return_value=_mock_chains())
        summary = detector.get_chain_summary()
        assert summary["blocking"] is True
        assert summary["chains"] == 1
        assert summary["total_blocked"] == 2
        assert summary["max_depth"] == 1
        assert 55 in summary["root_blockers"]
