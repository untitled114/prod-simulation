-- Sentinel monitoring schema
SET QUOTED_IDENTIFIER ON;
GO

USE master;
GO

IF NOT EXISTS (SELECT 1 FROM sys.databases WHERE name = 'SentinelDB')
    CREATE DATABASE SentinelDB;
GO

USE SentinelDB;
GO

-- Health snapshots captured by the monitor
IF NOT EXISTS (SELECT 1 FROM sys.tables WHERE name = 'health_snapshots')
CREATE TABLE health_snapshots (
    id              INT IDENTITY(1,1) PRIMARY KEY,
    captured_at     DATETIME2 NOT NULL DEFAULT SYSUTCDATETIME(),
    cpu_percent     FLOAT NULL,
    memory_used_mb  FLOAT NULL,
    memory_total_mb FLOAT NULL,
    connection_count INT NULL,
    blocking_count  INT NULL,
    long_query_count INT NULL,
    tempdb_used_mb  FLOAT NULL,
    avg_wait_ms     FLOAT NULL,
    status          VARCHAR(20) NOT NULL DEFAULT 'healthy',
    details         NVARCHAR(MAX) NULL,
    CONSTRAINT CK_health_status CHECK (status IN ('healthy', 'warning', 'critical', 'error'))
);
GO

IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE name = 'IX_health_snapshots_captured')
    CREATE INDEX IX_health_snapshots_captured ON health_snapshots(captured_at DESC);
GO

-- Incident tracking
IF NOT EXISTS (SELECT 1 FROM sys.tables WHERE name = 'incidents')
CREATE TABLE incidents (
    id              INT IDENTITY(1,1) PRIMARY KEY,
    incident_type   VARCHAR(100) NOT NULL,
    severity        VARCHAR(20) NOT NULL DEFAULT 'warning',
    status          VARCHAR(30) NOT NULL DEFAULT 'detected',
    title           NVARCHAR(500) NOT NULL,
    description     NVARCHAR(MAX) NULL,
    detected_at     DATETIME2 NOT NULL DEFAULT SYSUTCDATETIME(),
    acknowledged_at DATETIME2 NULL,
    resolved_at     DATETIME2 NULL,
    resolved_by     VARCHAR(100) NULL,
    dedup_key       VARCHAR(200) NULL,
    metadata        NVARCHAR(MAX) NULL,
    CONSTRAINT CK_incident_severity CHECK (severity IN ('info', 'warning', 'critical')),
    CONSTRAINT CK_incident_status CHECK (status IN ('detected', 'investigating', 'remediating', 'resolved', 'escalated'))
);
GO

IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE name = 'IX_incidents_status')
    CREATE INDEX IX_incidents_status ON incidents(status);
IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE name = 'IX_incidents_detected')
    CREATE INDEX IX_incidents_detected ON incidents(detected_at DESC);
IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE name = 'IX_incidents_dedup')
    CREATE INDEX IX_incidents_dedup ON incidents(dedup_key) WHERE dedup_key IS NOT NULL;
IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE name = 'IX_incidents_type')
    CREATE INDEX IX_incidents_type ON incidents(incident_type);
GO

-- Job run history
IF NOT EXISTS (SELECT 1 FROM sys.tables WHERE name = 'job_runs')
CREATE TABLE job_runs (
    id              INT IDENTITY(1,1) PRIMARY KEY,
    job_name        VARCHAR(200) NOT NULL,
    started_at      DATETIME2 NOT NULL DEFAULT SYSUTCDATETIME(),
    completed_at    DATETIME2 NULL,
    status          VARCHAR(20) NOT NULL DEFAULT 'running',
    duration_ms     INT NULL,
    rows_affected   INT NULL,
    error_message   NVARCHAR(MAX) NULL,
    output          NVARCHAR(MAX) NULL,
    CONSTRAINT CK_job_runs_status CHECK (status IN ('running', 'success', 'failed', 'timeout'))
);
GO

IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE name = 'IX_job_runs_name')
    CREATE INDEX IX_job_runs_name ON job_runs(job_name, started_at DESC);
GO

-- Data validation results
IF NOT EXISTS (SELECT 1 FROM sys.tables WHERE name = 'validation_results')
CREATE TABLE validation_results (
    id              INT IDENTITY(1,1) PRIMARY KEY,
    rule_name       VARCHAR(200) NOT NULL,
    rule_type       VARCHAR(50) NOT NULL,
    table_name      VARCHAR(200) NULL,
    column_name     VARCHAR(200) NULL,
    executed_at     DATETIME2 NOT NULL DEFAULT SYSUTCDATETIME(),
    passed          BIT NOT NULL,
    severity        VARCHAR(20) NOT NULL DEFAULT 'warning',
    violation_count INT NULL DEFAULT 0,
    sample_values   NVARCHAR(MAX) NULL,
    description     NVARCHAR(500) NULL
);
GO

IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE name = 'IX_validation_results_rule')
    CREATE INDEX IX_validation_results_rule ON validation_results(rule_name, executed_at DESC);
GO

-- Remediation action log
IF NOT EXISTS (SELECT 1 FROM sys.tables WHERE name = 'remediation_log')
CREATE TABLE remediation_log (
    id              INT IDENTITY(1,1) PRIMARY KEY,
    incident_id     INT NOT NULL,
    action_name     VARCHAR(200) NOT NULL,
    executed_at     DATETIME2 NOT NULL DEFAULT SYSUTCDATETIME(),
    success         BIT NOT NULL,
    details         NVARCHAR(MAX) NULL,
    FOREIGN KEY (incident_id) REFERENCES incidents(id)
);
GO

-- Postmortems for resolved incidents
IF NOT EXISTS (SELECT 1 FROM sys.tables WHERE name = 'postmortems')
CREATE TABLE postmortems (
    id              INT IDENTITY(1,1) PRIMARY KEY,
    incident_id     INT NOT NULL UNIQUE,
    generated_at    DATETIME2 NOT NULL DEFAULT SYSUTCDATETIME(),
    summary         NVARCHAR(MAX) NOT NULL,
    root_cause      NVARCHAR(MAX) NULL,
    timeline        NVARCHAR(MAX) NULL,  -- JSON array of events
    remediation     NVARCHAR(MAX) NULL,
    lessons_learned NVARCHAR(MAX) NULL,
    FOREIGN KEY (incident_id) REFERENCES incidents(id)
);
GO

PRINT 'Sentinel schema created successfully.';
GO
