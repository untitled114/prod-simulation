-- ETL stored procedures — demonstrates data extraction, transformation, and loading patterns
-- These are scheduled via the Python job runner (config/jobs.yaml)
SET QUOTED_IDENTIFIER ON;
GO

USE SentinelDB;
GO

-- ============================================================================
-- ETL 1: Daily Order Summary (Extract + Aggregate + Load)
-- Extracts raw order data, computes daily aggregates, loads into summary table
-- ============================================================================

IF NOT EXISTS (SELECT 1 FROM sys.tables WHERE name = 'daily_order_summary')
CREATE TABLE daily_order_summary (
    id              INT IDENTITY(1,1) PRIMARY KEY,
    summary_date    DATE NOT NULL,
    total_orders    INT NOT NULL DEFAULT 0,
    total_revenue   DECIMAL(14,2) NOT NULL DEFAULT 0,
    avg_order_value DECIMAL(10,2) NOT NULL DEFAULT 0,
    cancelled_count INT NOT NULL DEFAULT 0,
    cancel_rate     DECIMAL(5,2) NOT NULL DEFAULT 0,
    top_region      VARCHAR(50) NULL,
    loaded_at       DATETIME2 NOT NULL DEFAULT SYSUTCDATETIME(),
    CONSTRAINT UQ_summary_date UNIQUE (summary_date)
);
GO

IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE name = 'IX_daily_summary_date')
    CREATE INDEX IX_daily_summary_date ON daily_order_summary(summary_date DESC);
GO

IF OBJECT_ID('sp_etl_daily_order_summary', 'P') IS NOT NULL
    DROP PROCEDURE sp_etl_daily_order_summary;
GO

CREATE PROCEDURE sp_etl_daily_order_summary
    @target_date DATE = NULL
AS
BEGIN
    SET NOCOUNT ON;

    -- Default to yesterday if no date provided
    IF @target_date IS NULL
        SET @target_date = CAST(DATEADD(DAY, -1, SYSUTCDATETIME()) AS DATE);

    -- Idempotent: delete existing row for this date (upsert pattern)
    DELETE FROM daily_order_summary WHERE summary_date = @target_date;

    -- Extract + Transform + Load in a single atomic operation
    INSERT INTO daily_order_summary (
        summary_date, total_orders, total_revenue, avg_order_value,
        cancelled_count, cancel_rate, top_region
    )
    SELECT
        @target_date AS summary_date,
        COUNT(*) AS total_orders,
        ISNULL(SUM(total_amount), 0) AS total_revenue,
        ISNULL(AVG(total_amount), 0) AS avg_order_value,
        SUM(CASE WHEN status = 'cancelled' THEN 1 ELSE 0 END) AS cancelled_count,
        CAST(
            SUM(CASE WHEN status = 'cancelled' THEN 1.0 ELSE 0 END) * 100.0 / NULLIF(COUNT(*), 0)
            AS DECIMAL(5,2)
        ) AS cancel_rate,
        -- Subquery for top region by revenue
        (
            SELECT TOP 1 shipping_region
            FROM orders
            WHERE CAST(order_date AS DATE) = @target_date
              AND shipping_region IS NOT NULL
            GROUP BY shipping_region
            ORDER BY SUM(total_amount) DESC
        ) AS top_region
    FROM orders
    WHERE CAST(order_date AS DATE) = @target_date;

    -- Return the loaded row for logging
    SELECT * FROM daily_order_summary WHERE summary_date = @target_date;
END;
GO

-- ============================================================================
-- ETL 2: Customer Health Score (SCD Type 1 — overwrite with latest)
-- Computes a customer "health score" based on order history and recency
-- ============================================================================

IF NOT EXISTS (SELECT 1 FROM sys.tables WHERE name = 'customer_health')
CREATE TABLE customer_health (
    customer_id     INT NOT NULL PRIMARY KEY,
    total_orders    INT NOT NULL DEFAULT 0,
    total_spent     DECIMAL(14,2) NOT NULL DEFAULT 0,
    avg_order_value DECIMAL(10,2) NOT NULL DEFAULT 0,
    last_order_date DATETIME2 NULL,
    days_since_last INT NULL,
    health_score    DECIMAL(5,2) NOT NULL DEFAULT 0,  -- 0-100 composite score
    health_tier     VARCHAR(20) NOT NULL DEFAULT 'new',  -- new, active, at_risk, churned
    computed_at     DATETIME2 NOT NULL DEFAULT SYSUTCDATETIME(),
    CONSTRAINT FK_customer_health FOREIGN KEY (customer_id) REFERENCES customers(id),
    CONSTRAINT CK_health_score CHECK (health_score >= 0 AND health_score <= 100),
    CONSTRAINT CK_health_tier CHECK (health_tier IN ('new', 'active', 'at_risk', 'churned'))
);
GO

IF OBJECT_ID('sp_etl_customer_health', 'P') IS NOT NULL
    DROP PROCEDURE sp_etl_customer_health;
GO

CREATE PROCEDURE sp_etl_customer_health
AS
BEGIN
    SET NOCOUNT ON;

    -- MERGE pattern: upsert customer health scores
    -- This is the standard SCD Type 1 ETL pattern in SQL Server
    MERGE customer_health AS target
    USING (
        SELECT
            c.id AS customer_id,
            COUNT(o.id) AS total_orders,
            ISNULL(SUM(o.total_amount), 0) AS total_spent,
            ISNULL(AVG(o.total_amount), 0) AS avg_order_value,
            MAX(o.order_date) AS last_order_date,
            DATEDIFF(DAY, MAX(o.order_date), SYSUTCDATETIME()) AS days_since_last,
            -- Health score: weighted composite (0-100)
            CAST(
                -- Recency: 40% weight (100 if ordered today, 0 if >180 days)
                CASE
                    WHEN MAX(o.order_date) IS NULL THEN 0
                    ELSE GREATEST(0, 100.0 - (DATEDIFF(DAY, MAX(o.order_date), SYSUTCDATETIME()) * 100.0 / 180.0))
                END * 0.4
                +
                -- Frequency: 30% weight (capped at 100 for 10+ orders)
                LEAST(COUNT(o.id) * 10.0, 100.0) * 0.3
                +
                -- Monetary: 30% weight (capped at 100 for $5000+ total)
                LEAST(ISNULL(SUM(o.total_amount), 0) / 50.0, 100.0) * 0.3
            AS DECIMAL(5,2)) AS health_score,
            -- Tier assignment based on recency
            CASE
                WHEN MAX(o.order_date) IS NULL THEN 'new'
                WHEN DATEDIFF(DAY, MAX(o.order_date), SYSUTCDATETIME()) <= 30 THEN 'active'
                WHEN DATEDIFF(DAY, MAX(o.order_date), SYSUTCDATETIME()) <= 90 THEN 'at_risk'
                ELSE 'churned'
            END AS health_tier
        FROM customers c
        LEFT JOIN orders o ON o.customer_id = c.id AND o.status <> 'cancelled'
        GROUP BY c.id
    ) AS source
    ON target.customer_id = source.customer_id
    WHEN MATCHED THEN
        UPDATE SET
            total_orders    = source.total_orders,
            total_spent     = source.total_spent,
            avg_order_value = source.avg_order_value,
            last_order_date = source.last_order_date,
            days_since_last = source.days_since_last,
            health_score    = source.health_score,
            health_tier     = source.health_tier,
            computed_at     = SYSUTCDATETIME()
    WHEN NOT MATCHED THEN
        INSERT (customer_id, total_orders, total_spent, avg_order_value,
                last_order_date, days_since_last, health_score, health_tier)
        VALUES (source.customer_id, source.total_orders, source.total_spent,
                source.avg_order_value, source.last_order_date, source.days_since_last,
                source.health_score, source.health_tier);

    -- Return summary for logging
    SELECT
        health_tier,
        COUNT(*) AS customer_count,
        AVG(health_score) AS avg_score
    FROM customer_health
    GROUP BY health_tier
    ORDER BY avg_score DESC;
END;
GO

-- ============================================================================
-- ETL 3: Incident Metrics Aggregation (for SLA reporting)
-- Rolls up incident data into hourly metrics for trend analysis
-- ============================================================================

IF NOT EXISTS (SELECT 1 FROM sys.tables WHERE name = 'incident_metrics')
CREATE TABLE incident_metrics (
    id                  INT IDENTITY(1,1) PRIMARY KEY,
    metric_hour         DATETIME2 NOT NULL,
    incidents_detected  INT NOT NULL DEFAULT 0,
    incidents_resolved  INT NOT NULL DEFAULT 0,
    incidents_escalated INT NOT NULL DEFAULT 0,
    avg_resolution_min  DECIMAL(8,2) NULL,
    max_resolution_min  DECIMAL(8,2) NULL,
    critical_count      INT NOT NULL DEFAULT 0,
    auto_resolved_count INT NOT NULL DEFAULT 0,
    loaded_at           DATETIME2 NOT NULL DEFAULT SYSUTCDATETIME(),
    CONSTRAINT UQ_metric_hour UNIQUE (metric_hour)
);
GO

IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE name = 'IX_incident_metrics_hour')
    CREATE INDEX IX_incident_metrics_hour ON incident_metrics(metric_hour DESC);
GO

IF OBJECT_ID('sp_etl_incident_metrics', 'P') IS NOT NULL
    DROP PROCEDURE sp_etl_incident_metrics;
GO

CREATE PROCEDURE sp_etl_incident_metrics
    @hours_back INT = 1
AS
BEGIN
    SET NOCOUNT ON;

    DECLARE @cutoff DATETIME2 = DATEADD(HOUR, -@hours_back, SYSUTCDATETIME());
    DECLARE @hour_start DATETIME2 = DATEADD(HOUR, DATEDIFF(HOUR, 0, @cutoff), 0);

    -- Idempotent: delete existing metrics for this hour
    DELETE FROM incident_metrics WHERE metric_hour = @hour_start;

    INSERT INTO incident_metrics (
        metric_hour, incidents_detected, incidents_resolved, incidents_escalated,
        avg_resolution_min, max_resolution_min, critical_count, auto_resolved_count
    )
    SELECT
        @hour_start AS metric_hour,
        COUNT(*) AS incidents_detected,
        SUM(CASE WHEN status = 'resolved' THEN 1 ELSE 0 END) AS incidents_resolved,
        SUM(CASE WHEN status = 'escalated' THEN 1 ELSE 0 END) AS incidents_escalated,
        AVG(
            CASE WHEN resolved_at IS NOT NULL
                THEN DATEDIFF(SECOND, detected_at, resolved_at) / 60.0
            END
        ) AS avg_resolution_min,
        MAX(
            CASE WHEN resolved_at IS NOT NULL
                THEN DATEDIFF(SECOND, detected_at, resolved_at) / 60.0
            END
        ) AS max_resolution_min,
        SUM(CASE WHEN severity = 'critical' THEN 1 ELSE 0 END) AS critical_count,
        SUM(CASE WHEN resolved_by = 'auto' THEN 1 ELSE 0 END) AS auto_resolved_count
    FROM incidents
    WHERE detected_at >= @hour_start
      AND detected_at < DATEADD(HOUR, 1, @hour_start);

    -- Return the metrics row
    SELECT * FROM incident_metrics WHERE metric_hour = @hour_start;
END;
GO

PRINT 'ETL procedures created successfully.';
GO
