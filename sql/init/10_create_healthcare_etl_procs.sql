SET QUOTED_IDENTIFIER ON;
GO

-- ============================================================================
-- Healthcare ETL Stored Procedures
-- Multi-source claim ingestion, SCD Type 2, PDC adherence, pharmacy rollups
-- ============================================================================

-- Staging table for raw claim ingestion (varchar fields for validation)
IF OBJECT_ID('stg_pharmacy_claims', 'U') IS NOT NULL DROP TABLE stg_pharmacy_claims;
GO

CREATE TABLE stg_pharmacy_claims (
    batch_id        UNIQUEIDENTIFIER NOT NULL,
    row_number      INT             NOT NULL,
    claim_number    VARCHAR(50)     NULL,
    member_id       VARCHAR(50)     NULL,
    ndc_code        VARCHAR(20)     NULL,
    ncpdp_id        VARCHAR(20)     NULL,
    provider_npi    VARCHAR(20)     NULL,
    service_date    VARCHAR(20)     NULL,
    fill_number     VARCHAR(10)     NULL,
    quantity        VARCHAR(20)     NULL,
    days_supply     VARCHAR(10)     NULL,
    ingredient_cost VARCHAR(20)     NULL,
    dispensing_fee  VARCHAR(20)     NULL,
    copay_amount    VARCHAR(20)     NULL,
    plan_paid       VARCHAR(20)     NULL,
    daw_code        VARCHAR(5)      NULL,
    reject_code     VARCHAR(10)     NULL,
    loaded_at       DATETIME2       NOT NULL DEFAULT SYSUTCDATETIME(),
    is_valid        BIT             NULL,
    validation_errors NVARCHAR(2000) NULL
);
GO

-- ============================================================================
-- sp_etl_claim_ingestion: Staging → Transform → Load pipeline
-- Validates raw claims, resolves FKs, loads to pharmacy_claims
-- ============================================================================
CREATE OR ALTER PROCEDURE sp_etl_claim_ingestion
    @batch_id UNIQUEIDENTIFIER
AS
BEGIN
    SET NOCOUNT ON;

    DECLARE @rows_read INT, @rows_written INT, @rows_rejected INT;
    DECLARE @lineage_id BIGINT;
    DECLARE @started_at DATETIME2 = SYSUTCDATETIME();

    -- Record lineage start
    INSERT INTO data_lineage (pipeline_name, execution_id, source_table, target_table, status)
    VALUES ('claim_ingestion', @batch_id, 'stg_pharmacy_claims', 'pharmacy_claims', 'running');
    SET @lineage_id = SCOPE_IDENTITY();

    BEGIN TRY
        -- Count incoming rows
        SELECT @rows_read = COUNT(*) FROM stg_pharmacy_claims WHERE batch_id = @batch_id;

        -- Step 1: Validate staging data
        UPDATE stg
        SET is_valid = 0,
            validation_errors = CONCAT(
                CASE WHEN stg.claim_number IS NULL OR LEN(stg.claim_number) = 0
                     THEN 'missing claim_number; ' ELSE '' END,
                CASE WHEN stg.member_id IS NULL OR LEN(stg.member_id) = 0
                     THEN 'missing member_id; ' ELSE '' END,
                CASE WHEN stg.ndc_code IS NULL OR LEN(stg.ndc_code) <> 11
                     THEN 'invalid ndc_code; ' ELSE '' END,
                CASE WHEN TRY_CAST(stg.service_date AS DATE) IS NULL
                     THEN 'invalid service_date; ' ELSE '' END,
                CASE WHEN TRY_CAST(stg.quantity AS DECIMAL(10,2)) IS NULL
                     OR TRY_CAST(stg.quantity AS DECIMAL(10,2)) <= 0
                     THEN 'invalid quantity; ' ELSE '' END,
                CASE WHEN TRY_CAST(stg.days_supply AS INT) IS NULL
                     OR TRY_CAST(stg.days_supply AS INT) < 1
                     OR TRY_CAST(stg.days_supply AS INT) > 365
                     THEN 'invalid days_supply; ' ELSE '' END,
                CASE WHEN p.id IS NULL THEN 'patient not found; ' ELSE '' END,
                CASE WHEN m.id IS NULL THEN 'medication not found; ' ELSE '' END,
                CASE WHEN ph.id IS NULL THEN 'pharmacy not found; ' ELSE '' END,
                CASE WHEN pr.id IS NULL THEN 'provider not found; ' ELSE '' END
            )
        FROM stg_pharmacy_claims stg
        LEFT JOIN patients p ON p.member_id = stg.member_id
        LEFT JOIN medications m ON m.ndc_code = stg.ndc_code
        LEFT JOIN pharmacies ph ON ph.ncpdp_id = stg.ncpdp_id
        LEFT JOIN providers pr ON pr.npi = stg.provider_npi
        WHERE stg.batch_id = @batch_id;

        -- Mark valid rows
        UPDATE stg_pharmacy_claims
        SET is_valid = 1
        WHERE batch_id = @batch_id
          AND (validation_errors IS NULL OR LEN(validation_errors) = 0);

        -- Step 2: Load valid rows into pharmacy_claims
        INSERT INTO pharmacy_claims (
            claim_number, patient_id, pharmacy_id, provider_id, medication_id,
            service_date, fill_number, quantity_dispensed, days_supply,
            ingredient_cost, dispensing_fee, copay_amount, plan_paid,
            daw_code, claim_status, reject_code
        )
        SELECT
            stg.claim_number,
            p.id,
            ph.id,
            pr.id,
            m.id,
            TRY_CAST(stg.service_date AS DATE),
            ISNULL(TRY_CAST(stg.fill_number AS INT), 1),
            TRY_CAST(stg.quantity AS DECIMAL(10,2)),
            TRY_CAST(stg.days_supply AS INT),
            ISNULL(TRY_CAST(stg.ingredient_cost AS DECIMAL(10,2)), 0),
            ISNULL(TRY_CAST(stg.dispensing_fee AS DECIMAL(10,2)), 0),
            ISNULL(TRY_CAST(stg.copay_amount AS DECIMAL(10,2)), 0),
            ISNULL(TRY_CAST(stg.plan_paid AS DECIMAL(10,2)), 0),
            ISNULL(TRY_CAST(stg.daw_code AS TINYINT), 0),
            CASE WHEN stg.reject_code IS NOT NULL THEN 'rejected' ELSE 'paid' END,
            stg.reject_code
        FROM stg_pharmacy_claims stg
        INNER JOIN patients p ON p.member_id = stg.member_id
        INNER JOIN medications m ON m.ndc_code = stg.ndc_code
        INNER JOIN pharmacies ph ON ph.ncpdp_id = stg.ncpdp_id
        INNER JOIN providers pr ON pr.npi = stg.provider_npi
        WHERE stg.batch_id = @batch_id AND stg.is_valid = 1;

        SET @rows_written = @@ROWCOUNT;
        SET @rows_rejected = @rows_read - @rows_written;

        -- Update lineage
        UPDATE data_lineage
        SET status = 'success',
            completed_at = SYSUTCDATETIME(),
            rows_read = @rows_read,
            rows_written = @rows_written,
            rows_rejected = @rows_rejected
        WHERE id = @lineage_id;

        SELECT @rows_read AS rows_read, @rows_written AS rows_written,
               @rows_rejected AS rows_rejected, 'success' AS status;
    END TRY
    BEGIN CATCH
        UPDATE data_lineage
        SET status = 'failed',
            completed_at = SYSUTCDATETIME(),
            rows_read = @rows_read,
            error_message = ERROR_MESSAGE()
        WHERE id = @lineage_id;

        THROW;
    END CATCH
END;
GO

-- ============================================================================
-- sp_etl_dim_patient_scd2: SCD Type 2 with HASHBYTES change detection
-- Detects changes in patient attributes and creates new dimension rows
-- ============================================================================
CREATE OR ALTER PROCEDURE sp_etl_dim_patient_scd2
AS
BEGIN
    SET NOCOUNT ON;

    DECLARE @today DATE = CAST(SYSUTCDATETIME() AS DATE);
    DECLARE @lineage_id BIGINT;
    DECLARE @rows_written INT = 0;

    INSERT INTO data_lineage (pipeline_name, source_table, target_table, status)
    VALUES ('dim_patient_scd2', 'patients', 'dim_patient', 'running');
    SET @lineage_id = SCOPE_IDENTITY();

    BEGIN TRY
        -- Step 1: Expire changed records
        UPDATE dp
        SET dp.expiration_date = DATEADD(DAY, -1, @today),
            dp.is_current = 0
        FROM dim_patient dp
        INNER JOIN patients p ON p.id = dp.patient_id
        WHERE dp.is_current = 1
          AND dp.row_hash <> HASHBYTES('SHA2_256',
              CONCAT(p.first_name, '|', p.last_name, '|',
                     CONVERT(VARCHAR, p.date_of_birth, 23), '|',
                     ISNULL(p.gender, ''), '|',
                     ISNULL(p.zip_code, ''), '|',
                     ISNULL(p.plan_type, ''), '|',
                     ISNULL(p.plan_group, '')));

        -- Step 2: Insert new/changed records
        INSERT INTO dim_patient (
            patient_id, member_id, first_name, last_name, date_of_birth,
            gender, zip_code, plan_type, plan_group, age_band,
            effective_date, row_hash
        )
        SELECT
            p.id,
            p.member_id,
            p.first_name,
            p.last_name,
            p.date_of_birth,
            p.gender,
            p.zip_code,
            p.plan_type,
            p.plan_group,
            CASE
                WHEN DATEDIFF(YEAR, p.date_of_birth, @today) < 18 THEN '0-17'
                WHEN DATEDIFF(YEAR, p.date_of_birth, @today) < 35 THEN '18-34'
                WHEN DATEDIFF(YEAR, p.date_of_birth, @today) < 50 THEN '35-49'
                WHEN DATEDIFF(YEAR, p.date_of_birth, @today) < 65 THEN '50-64'
                ELSE '65+'
            END,
            @today,
            HASHBYTES('SHA2_256',
                CONCAT(p.first_name, '|', p.last_name, '|',
                       CONVERT(VARCHAR, p.date_of_birth, 23), '|',
                       ISNULL(p.gender, ''), '|',
                       ISNULL(p.zip_code, ''), '|',
                       ISNULL(p.plan_type, ''), '|',
                       ISNULL(p.plan_group, '')))
        FROM patients p
        WHERE NOT EXISTS (
            SELECT 1 FROM dim_patient dp
            WHERE dp.patient_id = p.id AND dp.is_current = 1
        );

        SET @rows_written = @@ROWCOUNT;

        UPDATE data_lineage
        SET status = 'success', completed_at = SYSUTCDATETIME(),
            rows_read = (SELECT COUNT(*) FROM patients),
            rows_written = @rows_written
        WHERE id = @lineage_id;

        SELECT @rows_written AS rows_written, 'success' AS status;
    END TRY
    BEGIN CATCH
        UPDATE data_lineage
        SET status = 'failed', completed_at = SYSUTCDATETIME(),
            error_message = ERROR_MESSAGE()
        WHERE id = @lineage_id;
        THROW;
    END CATCH
END;
GO

-- ============================================================================
-- sp_etl_patient_adherence: Monthly PDC (Proportion of Days Covered)
-- Key CMS Star Rating metric for Medicare Part D
-- ============================================================================
CREATE OR ALTER PROCEDURE sp_etl_patient_adherence
    @measure_start DATE = NULL,
    @measure_end   DATE = NULL
AS
BEGIN
    SET NOCOUNT ON;

    -- Default: previous calendar month
    IF @measure_start IS NULL
        SET @measure_start = DATEADD(MONTH, DATEDIFF(MONTH, 0, SYSUTCDATETIME()) - 1, 0);
    IF @measure_end IS NULL
        SET @measure_end = DATEADD(DAY, -1, DATEADD(MONTH, DATEDIFF(MONTH, 0, SYSUTCDATETIME()), 0));

    DECLARE @days_in_period INT = DATEDIFF(DAY, @measure_start, @measure_end) + 1;
    DECLARE @lineage_id BIGINT;

    INSERT INTO data_lineage (pipeline_name, source_table, target_table, status)
    VALUES ('patient_adherence', 'pharmacy_claims', 'patient_adherence', 'running');
    SET @lineage_id = SCOPE_IDENTITY();

    BEGIN TRY
        -- Calculate PDC per patient per drug class
        ;WITH claim_coverage AS (
            SELECT
                pc.patient_id,
                m.drug_class,
                pc.service_date AS fill_date,
                pc.days_supply,
                -- Clip coverage to measurement period
                CASE WHEN pc.service_date < @measure_start THEN @measure_start
                     ELSE pc.service_date END AS coverage_start,
                CASE WHEN DATEADD(DAY, pc.days_supply - 1, pc.service_date) > @measure_end
                     THEN @measure_end
                     ELSE DATEADD(DAY, pc.days_supply - 1, pc.service_date) END AS coverage_end
            FROM pharmacy_claims pc
            INNER JOIN medications m ON m.id = pc.medication_id
            WHERE pc.claim_status = 'paid'
              AND pc.service_date <= @measure_end
              AND DATEADD(DAY, pc.days_supply - 1, pc.service_date) >= @measure_start
        ),
        patient_stats AS (
            SELECT
                patient_id,
                drug_class,
                COUNT(DISTINCT fill_date) AS total_fills,
                COUNT(DISTINCT CONCAT(patient_id, '-', drug_class)) AS unique_medications,
                SUM(DATEDIFF(DAY, coverage_start, coverage_end) + 1) AS raw_days_covered
            FROM claim_coverage
            GROUP BY patient_id, drug_class
        )
        MERGE INTO patient_adherence AS tgt
        USING (
            SELECT
                ps.patient_id,
                ps.drug_class,
                @measure_start AS measure_period_start,
                @measure_end AS measure_period_end,
                @days_in_period AS days_in_period,
                -- Cap at period length (overlapping fills)
                CASE WHEN ps.raw_days_covered > @days_in_period
                     THEN @days_in_period ELSE ps.raw_days_covered END AS days_covered,
                CAST(
                    CASE WHEN ps.raw_days_covered > @days_in_period
                         THEN 1.0
                         ELSE CAST(ps.raw_days_covered AS DECIMAL(10,4)) / @days_in_period
                    END AS DECIMAL(5,4)
                ) AS pdc_ratio,
                ps.total_fills,
                ps.unique_medications,
                @days_in_period - CASE WHEN ps.raw_days_covered > @days_in_period
                    THEN @days_in_period ELSE ps.raw_days_covered END AS gap_days
            FROM patient_stats ps
        ) AS src
        ON tgt.patient_id = src.patient_id
           AND tgt.drug_class = src.drug_class
           AND tgt.measure_period_start = src.measure_period_start
        WHEN MATCHED THEN UPDATE SET
            days_covered = src.days_covered,
            pdc_ratio = src.pdc_ratio,
            total_fills = src.total_fills,
            gap_days = src.gap_days,
            calculated_at = SYSUTCDATETIME()
        WHEN NOT MATCHED THEN INSERT (
            patient_id, drug_class, measure_period_start, measure_period_end,
            days_in_period, days_covered, pdc_ratio, total_fills,
            unique_medications, gap_days
        ) VALUES (
            src.patient_id, src.drug_class, src.measure_period_start, src.measure_period_end,
            src.days_in_period, src.days_covered, src.pdc_ratio, src.total_fills,
            src.unique_medications, src.gap_days
        );

        UPDATE data_lineage
        SET status = 'success', completed_at = SYSUTCDATETIME(),
            rows_written = @@ROWCOUNT
        WHERE id = @lineage_id;
    END TRY
    BEGIN CATCH
        UPDATE data_lineage
        SET status = 'failed', completed_at = SYSUTCDATETIME(),
            error_message = ERROR_MESSAGE()
        WHERE id = @lineage_id;
        THROW;
    END CATCH
END;
GO

-- ============================================================================
-- sp_etl_pharmacy_fill_summary: Daily pharmacy rollups with generic fill rate
-- ============================================================================
IF OBJECT_ID('pharmacy_fill_summary', 'U') IS NOT NULL DROP TABLE pharmacy_fill_summary;
GO

CREATE TABLE pharmacy_fill_summary (
    id              INT IDENTITY(1,1) PRIMARY KEY,
    pharmacy_id     INT             NOT NULL,
    summary_date    DATE            NOT NULL,
    total_fills     INT             NOT NULL DEFAULT 0,
    generic_fills   INT             NOT NULL DEFAULT 0,
    brand_fills     INT             NOT NULL DEFAULT 0,
    specialty_fills INT             NOT NULL DEFAULT 0,
    total_revenue   DECIMAL(12,2)   NOT NULL DEFAULT 0,
    total_copays    DECIMAL(12,2)   NOT NULL DEFAULT 0,
    total_plan_paid DECIMAL(12,2)   NOT NULL DEFAULT 0,
    avg_days_supply DECIMAL(5,1)    NULL,
    generic_fill_rate AS (
        CASE WHEN total_fills > 0
             THEN CAST(generic_fills AS DECIMAL(5,4)) / total_fills
             ELSE 0 END
    ),
    unique_patients INT             NOT NULL DEFAULT 0,
    rejection_count INT             NOT NULL DEFAULT 0,
    calculated_at   DATETIME2       NOT NULL DEFAULT SYSUTCDATETIME(),

    CONSTRAINT FK_fill_summary_pharmacy FOREIGN KEY (pharmacy_id) REFERENCES pharmacies(id),
    CONSTRAINT UQ_fill_summary UNIQUE (pharmacy_id, summary_date)
);
GO

CREATE OR ALTER PROCEDURE sp_etl_pharmacy_fill_summary
    @summary_date DATE = NULL
AS
BEGIN
    SET NOCOUNT ON;

    IF @summary_date IS NULL
        SET @summary_date = CAST(DATEADD(DAY, -1, SYSUTCDATETIME()) AS DATE);

    DECLARE @lineage_id BIGINT;

    INSERT INTO data_lineage (pipeline_name, source_table, target_table, status)
    VALUES ('pharmacy_fill_summary', 'pharmacy_claims', 'pharmacy_fill_summary', 'running');
    SET @lineage_id = SCOPE_IDENTITY();

    BEGIN TRY
        MERGE INTO pharmacy_fill_summary AS tgt
        USING (
            SELECT
                pc.pharmacy_id,
                @summary_date AS summary_date,
                COUNT(*) AS total_fills,
                SUM(CASE WHEN pc.is_generic = 1 THEN 1 ELSE 0 END) AS generic_fills,
                SUM(CASE WHEN pc.is_generic = 0 THEN 1 ELSE 0 END) AS brand_fills,
                SUM(CASE WHEN pc.is_specialty = 1 THEN 1 ELSE 0 END) AS specialty_fills,
                SUM(pc.ingredient_cost + pc.dispensing_fee) AS total_revenue,
                SUM(pc.copay_amount) AS total_copays,
                SUM(pc.plan_paid) AS total_plan_paid,
                AVG(CAST(pc.days_supply AS DECIMAL(5,1))) AS avg_days_supply,
                COUNT(DISTINCT pc.patient_id) AS unique_patients,
                SUM(CASE WHEN pc.claim_status = 'rejected' THEN 1 ELSE 0 END) AS rejection_count
            FROM pharmacy_claims pc
            WHERE pc.service_date = @summary_date
            GROUP BY pc.pharmacy_id
        ) AS src
        ON tgt.pharmacy_id = src.pharmacy_id AND tgt.summary_date = src.summary_date
        WHEN MATCHED THEN UPDATE SET
            total_fills = src.total_fills,
            generic_fills = src.generic_fills,
            brand_fills = src.brand_fills,
            specialty_fills = src.specialty_fills,
            total_revenue = src.total_revenue,
            total_copays = src.total_copays,
            total_plan_paid = src.total_plan_paid,
            avg_days_supply = src.avg_days_supply,
            unique_patients = src.unique_patients,
            rejection_count = src.rejection_count,
            calculated_at = SYSUTCDATETIME()
        WHEN NOT MATCHED THEN INSERT (
            pharmacy_id, summary_date, total_fills, generic_fills, brand_fills,
            specialty_fills, total_revenue, total_copays, total_plan_paid,
            avg_days_supply, unique_patients, rejection_count
        ) VALUES (
            src.pharmacy_id, src.summary_date, src.total_fills, src.generic_fills,
            src.brand_fills, src.specialty_fills, src.total_revenue, src.total_copays,
            src.total_plan_paid, src.avg_days_supply, src.unique_patients, src.rejection_count
        );

        UPDATE data_lineage
        SET status = 'success', completed_at = SYSUTCDATETIME(),
            rows_written = @@ROWCOUNT
        WHERE id = @lineage_id;
    END TRY
    BEGIN CATCH
        UPDATE data_lineage
        SET status = 'failed', completed_at = SYSUTCDATETIME(),
            error_message = ERROR_MESSAGE()
        WHERE id = @lineage_id;
        THROW;
    END CATCH
END;
GO

PRINT 'Healthcare ETL procedures created successfully.';
GO
