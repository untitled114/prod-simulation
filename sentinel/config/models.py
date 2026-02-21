"""Pydantic models for all YAML configuration."""

from __future__ import annotations

from typing import Any

from pydantic import BaseModel, Field


class DatabaseConfig(BaseModel):
    host: str = "sqlserver"
    port: int = 1433
    name: str = "SentinelDB"
    user: str = "sa"
    password: str = ""
    driver: str = "ODBC Driver 18 for SQL Server"
    trust_cert: bool = True
    connect_timeout: int = 10
    query_timeout: int = 30


class ThresholdConfig(BaseModel):
    cpu_percent_warning: float = 70.0
    cpu_percent_critical: float = 90.0
    memory_percent_warning: float = 75.0
    memory_percent_critical: float = 90.0
    blocking_chain_warning: int = 2
    blocking_chain_critical: int = 5
    long_query_seconds_warning: int = 30
    long_query_seconds_critical: int = 120
    connection_count_warning: int = 80
    connection_count_critical: int = 150
    tempdb_usage_mb_warning: float = 500.0
    tempdb_usage_mb_critical: float = 1000.0
    # Healthcare thresholds
    claim_rejection_rate_warning: float = 5.0
    claim_rejection_rate_critical: float = 15.0
    generic_dispensing_rate_warning: float = 80.0  # alert if below
    pdc_adherence_warning: float = 0.80  # CMS Star threshold


class MonitorConfig(BaseModel):
    poll_interval_seconds: int = 10
    snapshot_retention_hours: int = 24
    auto_remediate: bool = True
    escalation_timeout_seconds: int = 300


class JobConfig(BaseModel):
    name: str
    schedule_cron: str
    sql_file: str | None = None
    sql_inline: str | None = None
    enabled: bool = True
    timeout_seconds: int = 60
    retry_count: int = 0
    description: str = ""


class ValidationRuleConfig(BaseModel):
    name: str
    type: str  # null_check, range_check, referential, duplicate, freshness, custom_sql
    table: str = ""
    column: str = ""
    severity: str = "warning"  # warning, critical
    params: dict[str, Any] = Field(default_factory=dict)
    description: str = ""


class ChaosScenarioConfig(BaseModel):
    name: str
    description: str = ""
    sql: str | list[str] = ""
    cooldown_seconds: int = 30
    severity: str = "medium"  # low, medium, high
    enabled: bool = True


class RemediationActionConfig(BaseModel):
    pattern: str  # incident type to match
    action: str  # action function name
    params: dict[str, Any] = Field(default_factory=dict)
    max_retries: int = 1
    escalate_on_failure: bool = True


class SentinelConfig(BaseModel):
    database: DatabaseConfig = Field(default_factory=DatabaseConfig)
    thresholds: ThresholdConfig = Field(default_factory=ThresholdConfig)
    monitor: MonitorConfig = Field(default_factory=MonitorConfig)
    jobs: list[JobConfig] = Field(default_factory=list)
    validation_rules: list[ValidationRuleConfig] = Field(default_factory=list)
    chaos_scenarios: list[ChaosScenarioConfig] = Field(default_factory=list)
    remediation_actions: list[RemediationActionConfig] = Field(default_factory=list)
