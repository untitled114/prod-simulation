"""Tests for healthcare chaos scenarios."""

from __future__ import annotations

from sentinel.chaos.scenarios import (
    BUILTIN_SCENARIOS,
    ClaimVolumeSpike,
    FormularyChangeCascade,
    PhiExposureEvent,
)


class TestClaimVolumeSpike:
    def test_execute_returns_triggered(self, mock_db):
        scenario = ClaimVolumeSpike()
        result = scenario.execute(mock_db)
        assert result["triggered"] is True
        assert "claims" in result["detail"].lower()

    def test_attributes(self):
        s = ClaimVolumeSpike()
        assert s.name == "Claim Volume Spike"
        assert s.severity == "high"


class TestPhiExposureEvent:
    def test_execute_returns_triggered(self, mock_db):
        scenario = PhiExposureEvent()
        result = scenario.execute(mock_db)
        assert result["triggered"] is True
        assert "PHI" in result["detail"] or "phi" in result["detail"].lower()

    def test_attributes(self):
        s = PhiExposureEvent()
        assert s.name == "PHI Exposure"
        assert s.severity == "high"


class TestFormularyChangeCascade:
    def test_execute_returns_triggered(self, mock_db):
        scenario = FormularyChangeCascade()
        result = scenario.execute(mock_db)
        assert result["triggered"] is True
        assert "medication" in result["detail"].lower() or "tier" in result["detail"].lower()

    def test_attributes(self):
        s = FormularyChangeCascade()
        assert s.name == "Formulary Change"
        assert s.severity == "medium"


class TestBuiltinScenariosRegistry:
    def test_nine_scenarios_registered(self):
        assert len(BUILTIN_SCENARIOS) == 9

    def test_healthcare_scenarios_registered(self):
        assert "Claim Volume Spike" in BUILTIN_SCENARIOS
        assert "PHI Exposure" in BUILTIN_SCENARIOS
        assert "Formulary Change" in BUILTIN_SCENARIOS

    def test_original_scenarios_still_present(self):
        assert "Long Running Query" in BUILTIN_SCENARIOS
        assert "Deadlock" in BUILTIN_SCENARIOS
        assert "Data Corruption" in BUILTIN_SCENARIOS
        assert "Orphaned Records" in BUILTIN_SCENARIOS
        assert "Job Failure" in BUILTIN_SCENARIOS
        assert "Connection Flood" in BUILTIN_SCENARIOS
