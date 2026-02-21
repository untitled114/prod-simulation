SET QUOTED_IDENTIFIER ON;
GO

-- ============================================================================
-- Healthcare Star Schema for Analytics
-- Dimensional model: 1 fact table + 5 dimensions + adherence aggregate
-- ============================================================================

-- dim_date — calendar + fiscal dimensions
CREATE TABLE dim_date (
    date_key        INT             NOT NULL PRIMARY KEY,   -- YYYYMMDD
    full_date       DATE            NOT NULL,
    day_of_week     TINYINT         NOT NULL,
    day_name        VARCHAR(10)     NOT NULL,
    day_of_month    TINYINT         NOT NULL,
    day_of_year     SMALLINT        NOT NULL,
    week_of_year    TINYINT         NOT NULL,
    month_number    TINYINT         NOT NULL,
    month_name      VARCHAR(10)     NOT NULL,
    quarter_number  TINYINT         NOT NULL,
    year_number     SMALLINT        NOT NULL,
    is_weekend      BIT             NOT NULL,
    is_holiday      BIT             NOT NULL DEFAULT 0,
    fiscal_quarter  TINYINT         NOT NULL,               -- CVS fiscal calendar
    fiscal_year     SMALLINT        NOT NULL
);
GO

-- dim_patient — SCD Type 2 (track historical changes)
CREATE TABLE dim_patient (
    patient_key     INT IDENTITY(1,1) PRIMARY KEY,          -- Surrogate key
    patient_id      INT             NOT NULL,                -- Natural key (FK to patients)
    member_id       VARCHAR(20)     NOT NULL,
    first_name      NVARCHAR(100)   NOT NULL,
    last_name       NVARCHAR(100)   NOT NULL,
    date_of_birth   DATE            NOT NULL,
    gender          CHAR(1)         NULL,
    zip_code        VARCHAR(10)     NULL,
    plan_type       VARCHAR(50)     NULL,
    plan_group      VARCHAR(50)     NULL,
    age_band        VARCHAR(20)     NULL,                    -- 0-17, 18-34, 35-49, 50-64, 65+
    effective_date  DATE            NOT NULL,
    expiration_date DATE            NOT NULL DEFAULT '9999-12-31',
    is_current      BIT             NOT NULL DEFAULT 1,
    row_hash        VARBINARY(32)   NOT NULL,                -- HASHBYTES for change detection
    created_at      DATETIME2       NOT NULL DEFAULT SYSUTCDATETIME()
);
GO

CREATE NONCLUSTERED INDEX IX_dim_patient_current
    ON dim_patient(patient_id) WHERE is_current = 1;
GO

-- dim_medication
CREATE TABLE dim_medication (
    medication_key  INT IDENTITY(1,1) PRIMARY KEY,
    medication_id   INT             NOT NULL,
    ndc_code        CHAR(11)        NOT NULL,
    drug_name       NVARCHAR(200)   NOT NULL,
    generic_name    NVARCHAR(200)   NULL,
    drug_class      VARCHAR(100)    NOT NULL,
    dosage_form     VARCHAR(50)     NULL,
    strength        VARCHAR(50)     NULL,
    is_generic      BIT             NOT NULL,
    is_formulary    BIT             NOT NULL,
    formulary_tier  TINYINT         NULL,
    dea_schedule    TINYINT         NULL,
    effective_date  DATE            NOT NULL DEFAULT '2020-01-01',
    is_current      BIT             NOT NULL DEFAULT 1
);
GO

-- dim_pharmacy
CREATE TABLE dim_pharmacy (
    pharmacy_key    INT IDENTITY(1,1) PRIMARY KEY,
    pharmacy_id     INT             NOT NULL,
    ncpdp_id        CHAR(7)         NOT NULL,
    name            NVARCHAR(200)   NOT NULL,
    chain_name      VARCHAR(100)    NULL,
    pharmacy_type   VARCHAR(50)     NOT NULL,
    state_code      CHAR(2)         NULL,
    zip_code        VARCHAR(10)     NULL,
    is_preferred    BIT             NOT NULL,
    effective_date  DATE            NOT NULL DEFAULT '2020-01-01',
    is_current      BIT             NOT NULL DEFAULT 1
);
GO

-- dim_provider
CREATE TABLE dim_provider (
    provider_key    INT IDENTITY(1,1) PRIMARY KEY,
    provider_id     INT             NOT NULL,
    npi             CHAR(10)        NOT NULL,
    first_name      NVARCHAR(100)   NOT NULL,
    last_name       NVARCHAR(100)   NOT NULL,
    specialty       VARCHAR(100)    NOT NULL,
    state_code      CHAR(2)         NULL,
    is_active       BIT             NOT NULL,
    effective_date  DATE            NOT NULL DEFAULT '2020-01-01',
    is_current      BIT             NOT NULL DEFAULT 1
);
GO

-- fact_pharmacy_claims — central fact table
CREATE TABLE fact_pharmacy_claims (
    fact_id         BIGINT IDENTITY(1,1) PRIMARY KEY,
    claim_id        BIGINT          NOT NULL,
    date_key        INT             NOT NULL,
    patient_key     INT             NOT NULL,
    medication_key  INT             NOT NULL,
    pharmacy_key    INT             NOT NULL,
    provider_key    INT             NOT NULL,
    fill_number     INT             NOT NULL,
    quantity_dispensed DECIMAL(10,2) NOT NULL,
    days_supply     INT             NOT NULL,
    ingredient_cost DECIMAL(10,2)   NOT NULL,
    dispensing_fee  DECIMAL(10,2)   NOT NULL,
    copay_amount    DECIMAL(10,2)   NOT NULL,
    plan_paid       DECIMAL(10,2)   NOT NULL,
    total_cost      DECIMAL(10,2)   NOT NULL,
    is_generic      BIT             NOT NULL,
    is_mail_order   BIT             NOT NULL,
    is_specialty    BIT             NOT NULL,
    claim_status    VARCHAR(20)     NOT NULL,

    CONSTRAINT FK_fact_date FOREIGN KEY (date_key) REFERENCES dim_date(date_key),
    CONSTRAINT FK_fact_patient FOREIGN KEY (patient_key) REFERENCES dim_patient(patient_key),
    CONSTRAINT FK_fact_medication FOREIGN KEY (medication_key) REFERENCES dim_medication(medication_key),
    CONSTRAINT FK_fact_pharmacy FOREIGN KEY (pharmacy_key) REFERENCES dim_pharmacy(pharmacy_key),
    CONSTRAINT FK_fact_provider FOREIGN KEY (provider_key) REFERENCES dim_provider(provider_key)
);
GO

-- Nonclustered columnstore index for analytical queries
CREATE NONCLUSTERED COLUMNSTORE INDEX NCCX_fact_pharmacy_claims
    ON fact_pharmacy_claims (
        date_key, patient_key, medication_key, pharmacy_key, provider_key,
        quantity_dispensed, days_supply, ingredient_cost, dispensing_fee,
        copay_amount, plan_paid, total_cost, is_generic, is_mail_order, is_specialty
    );
GO

-- Patient Adherence (PDC — Proportion of Days Covered)
-- Used in CMS Star Ratings for Medicare Part D
CREATE TABLE patient_adherence (
    id              INT IDENTITY(1,1) PRIMARY KEY,
    patient_id      INT             NOT NULL,
    drug_class      VARCHAR(100)    NOT NULL,
    measure_period_start DATE       NOT NULL,
    measure_period_end   DATE       NOT NULL,
    days_in_period  INT             NOT NULL,
    days_covered    INT             NOT NULL,
    pdc_ratio       DECIMAL(5,4)    NOT NULL,           -- 0.0000 to 1.0000
    is_adherent     AS (CASE WHEN pdc_ratio >= 0.80 THEN 1 ELSE 0 END),  -- CMS threshold
    total_fills     INT             NOT NULL DEFAULT 0,
    unique_medications INT          NOT NULL DEFAULT 0,
    gap_days        INT             NOT NULL DEFAULT 0, -- Total uncovered days
    risk_score      DECIMAL(5,2)    NULL,               -- ML-derived risk score
    calculated_at   DATETIME2       NOT NULL DEFAULT SYSUTCDATETIME(),

    CONSTRAINT FK_adherence_patient FOREIGN KEY (patient_id) REFERENCES patients(id),
    CONSTRAINT CK_adherence_pdc CHECK (pdc_ratio BETWEEN 0 AND 1),
    CONSTRAINT UQ_adherence_patient_class_period
        UNIQUE (patient_id, drug_class, measure_period_start)
);
GO

CREATE NONCLUSTERED INDEX IX_adherence_pdc
    ON patient_adherence(drug_class, pdc_ratio) INCLUDE (patient_id, is_adherent);
GO

PRINT 'Healthcare star schema created successfully.';
GO
