"""Tests for chaos scenario logic."""

from unittest.mock import MagicMock

from sentinel.chaos.engine import ChaosEngine
from sentinel.chaos.scenarios import (
    BUILTIN_SCENARIOS,
    ConnectionFlood,
    DataCorruption,
    JobFailure,
)
from sentinel.monitor.incident_manager import IncidentManager


class TestBuiltinScenarios:
    def test_all_scenarios_registered(self):
        assert len(BUILTIN_SCENARIOS) == 9
        assert "Long Running Query" in BUILTIN_SCENARIOS
        assert "Deadlock" in BUILTIN_SCENARIOS
        assert "Data Corruption" in BUILTIN_SCENARIOS
        assert "Orphaned Records" in BUILTIN_SCENARIOS
        assert "Job Failure" in BUILTIN_SCENARIOS
        assert "Connection Flood" in BUILTIN_SCENARIOS

    def test_job_failure_scenario(self, mock_db):
        scenario = JobFailure()
        result = scenario.execute(mock_db)
        assert result["triggered"] is True
        assert "failed" in result["detail"].lower() or "job" in result["detail"].lower()

    def test_data_corruption_scenario(self, mock_db):
        # Mock needs to handle multiple execute_nonquery calls
        mock_db.execute_nonquery = MagicMock(return_value=1)
        scenario = DataCorruption()
        result = scenario.execute(mock_db)
        assert result["triggered"] is True
        assert len(result["detail"]) > 0

    def test_connection_flood_scenario(self, mock_db):
        scenario = ConnectionFlood()
        result = scenario.execute(mock_db)
        assert result["triggered"] is True
        assert "connection" in result["detail"].lower() or "opened" in result["detail"].lower()


class TestChaosEngine:
    def test_list_scenarios(self, mock_db):
        incidents = IncidentManager(mock_db)
        engine = ChaosEngine(mock_db, incidents)
        scenarios = engine.list_scenarios()
        assert len(scenarios) == 9
        assert all("name" in s for s in scenarios)
        assert all("severity" in s for s in scenarios)

    def test_trigger_known_scenario(self, mock_db):
        incidents = IncidentManager(mock_db)
        engine = ChaosEngine(mock_db, incidents)
        result = engine.trigger("Job Failure")
        assert result["scenario"] == "Job Failure"
        assert result.get("triggered") is True

    def test_trigger_unknown_scenario(self, mock_db):
        incidents = IncidentManager(mock_db)
        engine = ChaosEngine(mock_db, incidents)
        result = engine.trigger("Nonexistent")
        assert "error" in result

    def test_cooldown_enforcement(self, mock_db):
        incidents = IncidentManager(mock_db)
        engine = ChaosEngine(mock_db, incidents)
        engine.trigger("Job Failure")
        # Second trigger should be blocked by cooldown
        result = engine.trigger("Job Failure")
        assert "cooldown" in result.get("error", "").lower()

    def test_trigger_random(self, mock_db):
        incidents = IncidentManager(mock_db)
        engine = ChaosEngine(mock_db, incidents)
        result = engine.trigger_random()
        assert "scenario" in result
