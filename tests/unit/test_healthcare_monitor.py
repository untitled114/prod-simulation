"""Tests for the healthcare monitoring module."""

from __future__ import annotations

from sentinel.config.models import ThresholdConfig
from sentinel.monitor.healthcare import HealthcareMonitor


class TestCollectMetrics:
    def test_returns_expected_keys(self, mock_db):
        monitor = HealthcareMonitor(mock_db, ThresholdConfig())
        metrics = monitor.collect_metrics()
        assert "claims_today" in metrics
        assert "rejection_rate" in metrics
        assert "generic_rate" in metrics
        assert "avg_pdc" in metrics
        assert "non_adherent_count" in metrics
        assert "total_patients" in metrics

    def test_caches_latest_metrics(self, mock_db):
        monitor = HealthcareMonitor(mock_db, ThresholdConfig())
        assert monitor.get_latest_metrics() is None
        metrics = monitor.collect_metrics()
        assert monitor.get_latest_metrics() == metrics

    def test_returns_numeric_values(self, mock_db):
        monitor = HealthcareMonitor(mock_db, ThresholdConfig())
        metrics = monitor.collect_metrics()
        assert isinstance(metrics["claims_today"], (int, float))
        assert isinstance(metrics["rejection_rate"], (int, float))


class TestEvaluateThresholds:
    def test_no_alerts_for_healthy_values(self, mock_db):
        thresholds = ThresholdConfig(
            claim_rejection_rate_warning=10.0,
            claim_rejection_rate_critical=20.0,
            generic_dispensing_rate_warning=50.0,
            pdc_adherence_warning=0.70,
        )
        monitor = HealthcareMonitor(mock_db, thresholds)
        metrics = {
            "claims_today": 100,
            "rejection_rate": 3.0,
            "generic_rate": 85.0,
            "avg_pdc": 0.85,
            "total_patients": 50,
        }
        alerts = monitor.evaluate_thresholds(metrics)
        assert len(alerts) == 0

    def test_critical_rejection_rate_alert(self, mock_db):
        thresholds = ThresholdConfig(
            claim_rejection_rate_warning=5.0,
            claim_rejection_rate_critical=15.0,
        )
        monitor = HealthcareMonitor(mock_db, thresholds)
        metrics = {
            "claims_today": 100,
            "rejection_rate": 20.0,
            "generic_rate": 85.0,
            "avg_pdc": 0.90,
            "total_patients": 50,
        }
        alerts = monitor.evaluate_thresholds(metrics)
        rejection_alerts = [a for a in alerts if a["metric"] == "claim_rejection_rate"]
        assert len(rejection_alerts) == 1
        assert rejection_alerts[0]["level"] == "critical"
        assert rejection_alerts[0]["value"] == 20.0

    def test_warning_rejection_rate_alert(self, mock_db):
        thresholds = ThresholdConfig(
            claim_rejection_rate_warning=5.0,
            claim_rejection_rate_critical=15.0,
        )
        monitor = HealthcareMonitor(mock_db, thresholds)
        metrics = {
            "claims_today": 100,
            "rejection_rate": 8.0,
            "generic_rate": 85.0,
            "avg_pdc": 0.90,
            "total_patients": 50,
        }
        alerts = monitor.evaluate_thresholds(metrics)
        rejection_alerts = [a for a in alerts if a["metric"] == "claim_rejection_rate"]
        assert len(rejection_alerts) == 1
        assert rejection_alerts[0]["level"] == "warning"

    def test_low_generic_rate_alert(self, mock_db):
        thresholds = ThresholdConfig(generic_dispensing_rate_warning=80.0)
        monitor = HealthcareMonitor(mock_db, thresholds)
        metrics = {
            "claims_today": 100,
            "rejection_rate": 2.0,
            "generic_rate": 60.0,
            "avg_pdc": 0.90,
            "total_patients": 50,
        }
        alerts = monitor.evaluate_thresholds(metrics)
        generic_alerts = [a for a in alerts if a["metric"] == "generic_dispensing_rate"]
        assert len(generic_alerts) == 1
        assert generic_alerts[0]["level"] == "warning"
        assert generic_alerts[0]["value"] == 60.0

    def test_no_generic_alert_when_no_claims(self, mock_db):
        thresholds = ThresholdConfig(generic_dispensing_rate_warning=80.0)
        monitor = HealthcareMonitor(mock_db, thresholds)
        metrics = {
            "claims_today": 0,
            "rejection_rate": 0.0,
            "generic_rate": 0.0,
            "avg_pdc": 0.90,
            "total_patients": 50,
        }
        alerts = monitor.evaluate_thresholds(metrics)
        generic_alerts = [a for a in alerts if a["metric"] == "generic_dispensing_rate"]
        assert len(generic_alerts) == 0

    def test_low_pdc_alert(self, mock_db):
        thresholds = ThresholdConfig(pdc_adherence_warning=0.80)
        monitor = HealthcareMonitor(mock_db, thresholds)
        metrics = {
            "claims_today": 100,
            "rejection_rate": 2.0,
            "generic_rate": 85.0,
            "avg_pdc": 0.65,
            "total_patients": 50,
        }
        alerts = monitor.evaluate_thresholds(metrics)
        pdc_alerts = [a for a in alerts if a["metric"] == "pdc_adherence"]
        assert len(pdc_alerts) == 1
        assert pdc_alerts[0]["value"] == 0.65

    def test_no_pdc_alert_when_no_patients(self, mock_db):
        thresholds = ThresholdConfig(pdc_adherence_warning=0.80)
        monitor = HealthcareMonitor(mock_db, thresholds)
        metrics = {
            "claims_today": 100,
            "rejection_rate": 2.0,
            "generic_rate": 85.0,
            "avg_pdc": 0.0,
            "total_patients": 0,
        }
        alerts = monitor.evaluate_thresholds(metrics)
        pdc_alerts = [a for a in alerts if a["metric"] == "pdc_adherence"]
        assert len(pdc_alerts) == 0

    def test_multiple_alerts_simultaneously(self, mock_db):
        thresholds = ThresholdConfig(
            claim_rejection_rate_warning=5.0,
            claim_rejection_rate_critical=15.0,
            generic_dispensing_rate_warning=80.0,
            pdc_adherence_warning=0.80,
        )
        monitor = HealthcareMonitor(mock_db, thresholds)
        metrics = {
            "claims_today": 100,
            "rejection_rate": 20.0,
            "generic_rate": 50.0,
            "avg_pdc": 0.60,
            "total_patients": 50,
        }
        alerts = monitor.evaluate_thresholds(metrics)
        assert len(alerts) == 3
