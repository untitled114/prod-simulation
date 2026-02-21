"""Tests for health collector and threshold evaluation."""

from sentinel.config.models import SentinelConfig, ThresholdConfig
from sentinel.core.exceptions import DatabaseQueryError
from sentinel.monitor.health import HealthCollector


class TestHealthCollector:
    def test_collect_snapshot_healthy(self, mock_db, config):
        collector = HealthCollector(mock_db, config)
        snapshot = collector.collect_snapshot()
        assert snapshot["status"] == "healthy"
        assert snapshot["cpu_percent"] == 45.0
        assert snapshot["alerts"] == []

    def test_get_sql_health(self, mock_db, config):
        collector = HealthCollector(mock_db, config)
        result = collector.get_sql_health()
        assert result["connected"] is True
        assert "version" in result

    def test_threshold_cpu_warning(self, mock_db):
        config = SentinelConfig(thresholds=ThresholdConfig(cpu_percent_warning=40.0))
        collector = HealthCollector(mock_db, config)
        snapshot = collector.collect_snapshot()
        # CPU is 45% in mock, threshold is 40% = warning
        assert snapshot["status"] == "warning"
        assert any(a["metric"] == "cpu" for a in snapshot["alerts"])

    def test_threshold_cpu_critical(self, mock_db):
        config = SentinelConfig(thresholds=ThresholdConfig(cpu_percent_critical=40.0))
        collector = HealthCollector(mock_db, config)
        snapshot = collector.collect_snapshot()
        assert snapshot["status"] == "critical"

    def test_error_snapshot(self, mock_db, config):
        # Force an error
        mock_db.execute_proc = lambda *a, **k: (_ for _ in ()).throw(DatabaseQueryError("DB down"))
        collector = HealthCollector(mock_db, config)
        snapshot = collector.collect_snapshot()
        assert snapshot["status"] == "error"

    def test_get_latest_empty(self, mock_db, config):
        collector = HealthCollector(mock_db, config)
        assert collector.get_latest() is None

    def test_get_latest_after_collect(self, mock_db, config):
        collector = HealthCollector(mock_db, config)
        collector.collect_snapshot()
        latest = collector.get_latest()
        assert latest is not None
        assert latest["cpu_percent"] == 45.0
