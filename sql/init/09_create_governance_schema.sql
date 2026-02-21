SET QUOTED_IDENTIFIER ON;
GO

-- ============================================================================
-- Data Governance Schema
-- Data catalog, lineage tracking, and HIPAA audit trail
-- ============================================================================

-- Data Catalog — metadata registry for all tables/columns
CREATE TABLE data_catalog (
    id              INT IDENTITY(1,1) PRIMARY KEY,
    schema_name     VARCHAR(128)    NOT NULL DEFAULT 'dbo',
    table_name      VARCHAR(128)    NOT NULL,
    column_name     VARCHAR(128)    NULL,               -- NULL = table-level entry
    data_type       VARCHAR(50)     NULL,
    description     NVARCHAR(500)   NULL,
    is_phi          BIT             NOT NULL DEFAULT 0, -- Protected Health Information
    is_pii          BIT             NOT NULL DEFAULT 0, -- Personally Identifiable Information
    phi_category    VARCHAR(50)     NULL,               -- name, dob, ssn, phone, email, address, member_id
    masking_rule    VARCHAR(50)     NULL,               -- full_mask, partial_mask, hash, none
    retention_days  INT             NULL,               -- Data retention policy
    owner           VARCHAR(100)    NULL,
    classification  VARCHAR(50)     NOT NULL DEFAULT 'internal',  -- public, internal, confidential, restricted
    last_scanned_at DATETIME2       NULL,
    created_at      DATETIME2       NOT NULL DEFAULT SYSUTCDATETIME(),
    updated_at      DATETIME2       NOT NULL DEFAULT SYSUTCDATETIME(),

    CONSTRAINT UQ_catalog_entry UNIQUE (schema_name, table_name, column_name)
);
GO

CREATE NONCLUSTERED INDEX IX_catalog_phi ON data_catalog(is_phi) WHERE is_phi = 1;
GO

CREATE NONCLUSTERED INDEX IX_catalog_table ON data_catalog(table_name);
GO

-- Data Lineage — ETL execution tracking
CREATE TABLE data_lineage (
    id              BIGINT IDENTITY(1,1) PRIMARY KEY,
    pipeline_name   VARCHAR(100)    NOT NULL,
    execution_id    UNIQUEIDENTIFIER NOT NULL DEFAULT NEWID(),
    source_table    VARCHAR(128)    NOT NULL,
    target_table    VARCHAR(128)    NOT NULL,
    started_at      DATETIME2       NOT NULL DEFAULT SYSUTCDATETIME(),
    completed_at    DATETIME2       NULL,
    status          VARCHAR(20)     NOT NULL DEFAULT 'running',  -- running, success, failed
    rows_read       INT             NULL,
    rows_written    INT             NULL,
    rows_rejected   INT             NULL,
    error_message   NVARCHAR(2000)  NULL,
    metadata        NVARCHAR(MAX)   NULL                -- JSON: extra context
);
GO

CREATE NONCLUSTERED INDEX IX_lineage_pipeline ON data_lineage(pipeline_name, started_at DESC);
GO

-- PHI Access Log — HIPAA audit trail
CREATE TABLE phi_access_log (
    id              BIGINT IDENTITY(1,1) PRIMARY KEY,
    accessed_at     DATETIME2       NOT NULL DEFAULT SYSUTCDATETIME(),
    user_name       VARCHAR(100)    NOT NULL,
    action          VARCHAR(50)     NOT NULL,           -- SELECT, UPDATE, DELETE, EXPORT
    table_name      VARCHAR(128)    NOT NULL,
    column_names    VARCHAR(500)    NULL,               -- Comma-separated PHI columns accessed
    patient_id      INT             NULL,               -- Specific patient if applicable
    record_count    INT             NULL,
    ip_address      VARCHAR(45)     NULL,
    application     VARCHAR(100)    NULL,
    justification   NVARCHAR(500)   NULL                -- Reason for access
);
GO

CREATE NONCLUSTERED INDEX IX_phi_access_date ON phi_access_log(accessed_at DESC);
GO

CREATE NONCLUSTERED INDEX IX_phi_access_patient ON phi_access_log(patient_id)
    WHERE patient_id IS NOT NULL;
GO

PRINT 'Data governance schema created successfully.';
GO
