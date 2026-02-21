"""Tests for job runner."""

from sentinel.config.models import JobConfig
from sentinel.jobs.runner import JobRunner, _parse_simple_cron


class TestCronParser:
    def test_every_seconds(self):
        assert _parse_simple_cron("@every 30s") == 30

    def test_every_minutes(self):
        assert _parse_simple_cron("@every 5m") == 300

    def test_every_hours(self):
        assert _parse_simple_cron("@every 2h") == 7200

    def test_cron_style(self):
        assert _parse_simple_cron("*/5 * * * *") == 300

    def test_default_fallback(self):
        assert _parse_simple_cron("some nonsense") == 60


class TestJobRunner:
    def test_get_all_jobs(self, mock_db):
        jobs = [
            JobConfig(name="job1", schedule_cron="@every 30s", sql_inline="SELECT 1"),
            JobConfig(
                name="job2", schedule_cron="*/5 * * * *", sql_inline="SELECT 2", enabled=False
            ),
        ]
        runner = JobRunner(mock_db, jobs)
        all_jobs = runner.get_all_jobs()
        # Only enabled jobs
        assert len(all_jobs) == 1
        assert all_jobs[0]["name"] == "job1"

    def test_run_job_success(self, mock_db):
        jobs = [JobConfig(name="test_job", schedule_cron="@every 60s", sql_inline="SELECT 1")]
        runner = JobRunner(mock_db, jobs)
        result = runner.run_job("test_job")
        assert result["status"] == "success"
        assert result["job_name"] == "test_job"

    def test_run_job_not_found(self, mock_db):
        runner = JobRunner(mock_db, [])
        result = runner.run_job("nonexistent")
        assert "error" in result

    def test_run_job_no_sql(self, mock_db):
        jobs = [JobConfig(name="empty_job", schedule_cron="@every 60s")]
        runner = JobRunner(mock_db, jobs)
        result = runner.run_job("empty_job")
        assert result["status"] == "failed"
