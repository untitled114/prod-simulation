SET QUOTED_IDENTIFIER ON;
GO

-- ============================================================================
-- Healthcare OLTP Schema
-- Pharmacy claims processing with NDC, NPI, ICD-10 support
-- ============================================================================

-- Providers (physicians, NPs, PAs)
CREATE TABLE providers (
    id              INT IDENTITY(1,1) PRIMARY KEY,
    npi             CHAR(10)        NOT NULL,           -- National Provider Identifier
    dea_number      VARCHAR(20)     NULL,               -- DEA registration for controlled substances
    first_name      NVARCHAR(100)   NOT NULL,
    last_name       NVARCHAR(100)   NOT NULL,
    specialty       VARCHAR(100)    NOT NULL,
    practice_name   NVARCHAR(200)   NULL,
    phone           VARCHAR(20)     NULL,
    fax             VARCHAR(20)     NULL,
    address_line1   NVARCHAR(200)   NULL,
    city            VARCHAR(100)    NULL,
    state_code      CHAR(2)         NULL,
    zip_code        VARCHAR(10)     NULL,
    is_active       BIT             NOT NULL DEFAULT 1,
    created_at      DATETIME2       NOT NULL DEFAULT SYSUTCDATETIME(),
    updated_at      DATETIME2       NOT NULL DEFAULT SYSUTCDATETIME(),

    CONSTRAINT UQ_providers_npi UNIQUE (npi)
);
GO

-- Patients (members)
CREATE TABLE patients (
    id              INT IDENTITY(1,1) PRIMARY KEY,
    member_id       VARCHAR(20)     NOT NULL,           -- Health plan member ID
    first_name      NVARCHAR(100)   NOT NULL,           -- PHI
    last_name       NVARCHAR(100)   NOT NULL,           -- PHI
    date_of_birth   DATE            NOT NULL,           -- PHI
    gender          CHAR(1)         NULL,
    ssn_last_four   CHAR(4)         NULL,               -- PHI (masked)
    phone           VARCHAR(20)     NULL,               -- PHI
    email           VARCHAR(200)    NULL,               -- PHI
    address_line1   NVARCHAR(200)   NULL,               -- PHI
    city            VARCHAR(100)    NULL,
    state_code      CHAR(2)         NULL,
    zip_code        VARCHAR(10)     NULL,
    plan_type       VARCHAR(50)     NULL,               -- Commercial, Medicare, Medicaid
    plan_group      VARCHAR(50)     NULL,
    pcp_provider_id INT             NULL,               -- Primary care physician
    is_active       BIT             NOT NULL DEFAULT 1,
    created_at      DATETIME2       NOT NULL DEFAULT SYSUTCDATETIME(),
    updated_at      DATETIME2       NOT NULL DEFAULT SYSUTCDATETIME(),

    CONSTRAINT UQ_patients_member_id UNIQUE (member_id),
    CONSTRAINT FK_patients_pcp FOREIGN KEY (pcp_provider_id) REFERENCES providers(id)
);
GO

-- Medications (drug master)
CREATE TABLE medications (
    id              INT IDENTITY(1,1) PRIMARY KEY,
    ndc_code        CHAR(11)        NOT NULL,           -- National Drug Code (11-digit)
    drug_name       NVARCHAR(200)   NOT NULL,
    generic_name    NVARCHAR(200)   NULL,
    drug_class      VARCHAR(100)    NOT NULL,           -- Therapeutic class
    dea_schedule    TINYINT         NULL,               -- NULL=non-controlled, 2-5=schedule
    dosage_form     VARCHAR(50)     NULL,               -- tablet, capsule, injection
    strength        VARCHAR(50)     NULL,               -- e.g., "10mg", "500mg/5mL"
    manufacturer    NVARCHAR(200)   NULL,
    is_generic      BIT             NOT NULL DEFAULT 0,
    is_formulary    BIT             NOT NULL DEFAULT 1,
    formulary_tier  TINYINT         NULL,               -- 1=preferred generic, 2=generic, 3=preferred brand, 4=non-preferred
    requires_prior_auth BIT         NOT NULL DEFAULT 0,
    created_at      DATETIME2       NOT NULL DEFAULT SYSUTCDATETIME(),

    CONSTRAINT UQ_medications_ndc UNIQUE (ndc_code)
);
GO

-- Pharmacies
CREATE TABLE pharmacies (
    id              INT IDENTITY(1,1) PRIMARY KEY,
    ncpdp_id        CHAR(7)         NOT NULL,           -- NCPDP Provider ID
    name            NVARCHAR(200)   NOT NULL,
    chain_name      VARCHAR(100)    NULL,               -- CVS, Walgreens, Rite Aid
    pharmacy_type   VARCHAR(50)     NOT NULL DEFAULT 'retail',  -- retail, mail_order, specialty, compounding
    phone           VARCHAR(20)     NULL,
    fax             VARCHAR(20)     NULL,
    address_line1   NVARCHAR(200)   NULL,
    city            VARCHAR(100)    NULL,
    state_code      CHAR(2)         NULL,
    zip_code        VARCHAR(10)     NULL,
    npi             CHAR(10)        NULL,
    is_preferred    BIT             NOT NULL DEFAULT 0, -- In-network preferred
    is_active       BIT             NOT NULL DEFAULT 1,
    created_at      DATETIME2       NOT NULL DEFAULT SYSUTCDATETIME(),

    CONSTRAINT UQ_pharmacies_ncpdp UNIQUE (ncpdp_id)
);
GO

-- Prescriptions
CREATE TABLE prescriptions (
    id              INT IDENTITY(1,1) PRIMARY KEY,
    rx_number       VARCHAR(20)     NOT NULL,
    patient_id      INT             NOT NULL,
    provider_id     INT             NOT NULL,
    medication_id   INT             NOT NULL,
    diagnosis_code  VARCHAR(10)     NULL,               -- ICD-10 code
    diagnosis_desc  NVARCHAR(200)   NULL,
    quantity        DECIMAL(10,2)   NOT NULL,
    days_supply     INT             NOT NULL,
    refills_authorized INT          NOT NULL DEFAULT 0,
    refills_remaining  INT          NOT NULL DEFAULT 0,
    daw_code        TINYINT         NOT NULL DEFAULT 0, -- Dispense As Written (0-9)
    sig_directions  NVARCHAR(500)   NULL,               -- "Take 1 tablet by mouth daily"
    prescribed_date DATE            NOT NULL,
    expiration_date DATE            NULL,
    is_active       BIT             NOT NULL DEFAULT 1,
    created_at      DATETIME2       NOT NULL DEFAULT SYSUTCDATETIME(),

    CONSTRAINT UQ_prescriptions_rx UNIQUE (rx_number),
    CONSTRAINT FK_prescriptions_patient FOREIGN KEY (patient_id) REFERENCES patients(id),
    CONSTRAINT FK_prescriptions_provider FOREIGN KEY (provider_id) REFERENCES providers(id),
    CONSTRAINT FK_prescriptions_medication FOREIGN KEY (medication_id) REFERENCES medications(id),
    CONSTRAINT CK_prescriptions_quantity CHECK (quantity > 0),
    CONSTRAINT CK_prescriptions_days_supply CHECK (days_supply BETWEEN 1 AND 365)
);
GO

-- Partition function + scheme for pharmacy_claims (monthly by service_date)
CREATE PARTITION FUNCTION pf_claims_monthly (DATE)
AS RANGE RIGHT FOR VALUES (
    '2025-01-01', '2025-02-01', '2025-03-01', '2025-04-01',
    '2025-05-01', '2025-06-01', '2025-07-01', '2025-08-01',
    '2025-09-01', '2025-10-01', '2025-11-01', '2025-12-01',
    '2026-01-01', '2026-02-01', '2026-03-01', '2026-04-01',
    '2026-05-01', '2026-06-01', '2026-07-01', '2026-08-01',
    '2026-09-01', '2026-10-01', '2026-11-01', '2026-12-01'
);
GO

CREATE PARTITION SCHEME ps_claims_monthly
AS PARTITION pf_claims_monthly ALL TO ([PRIMARY]);
GO

-- Pharmacy Claims (PARTITIONED by service_date)
CREATE TABLE pharmacy_claims (
    id              BIGINT IDENTITY(1,1),
    claim_number    VARCHAR(30)     NOT NULL,
    patient_id      INT             NOT NULL,
    prescription_id INT             NULL,
    pharmacy_id     INT             NOT NULL,
    provider_id     INT             NOT NULL,
    medication_id   INT             NOT NULL,
    service_date    DATE            NOT NULL,
    fill_number     INT             NOT NULL DEFAULT 1,
    quantity_dispensed DECIMAL(10,2) NOT NULL,
    days_supply     INT             NOT NULL,
    ingredient_cost DECIMAL(10,2)   NOT NULL,
    dispensing_fee  DECIMAL(10,2)   NOT NULL DEFAULT 0,
    copay_amount    DECIMAL(10,2)   NOT NULL DEFAULT 0,
    plan_paid       DECIMAL(10,2)   NOT NULL DEFAULT 0,
    total_cost      AS (ingredient_cost + dispensing_fee),  -- Computed column
    claim_status    VARCHAR(20)     NOT NULL DEFAULT 'paid',  -- paid, rejected, reversed
    reject_code     VARCHAR(10)     NULL,               -- NCPDP reject codes
    reject_reason   NVARCHAR(200)   NULL,
    prior_auth_number VARCHAR(30)   NULL,
    daw_code        TINYINT         NOT NULL DEFAULT 0,
    is_generic      BIT             NOT NULL DEFAULT 0,
    is_mail_order   BIT             NOT NULL DEFAULT 0,
    is_specialty    BIT             NOT NULL DEFAULT 0,
    submitted_at    DATETIME2       NOT NULL DEFAULT SYSUTCDATETIME(),
    adjudicated_at  DATETIME2       NULL,
    created_at      DATETIME2       NOT NULL DEFAULT SYSUTCDATETIME(),

    CONSTRAINT PK_pharmacy_claims PRIMARY KEY CLUSTERED (service_date, id),
    CONSTRAINT FK_claims_patient FOREIGN KEY (patient_id) REFERENCES patients(id),
    CONSTRAINT FK_claims_pharmacy FOREIGN KEY (pharmacy_id) REFERENCES pharmacies(id),
    CONSTRAINT FK_claims_provider FOREIGN KEY (provider_id) REFERENCES providers(id),
    CONSTRAINT FK_claims_medication FOREIGN KEY (medication_id) REFERENCES medications(id),
    CONSTRAINT CK_claims_quantity CHECK (quantity_dispensed > 0),
    CONSTRAINT CK_claims_days_supply CHECK (days_supply BETWEEN 1 AND 365)
) ON ps_claims_monthly(service_date);
GO

-- Indexes for pharmacy_claims
CREATE NONCLUSTERED INDEX IX_claims_patient ON pharmacy_claims(patient_id, service_date)
    ON ps_claims_monthly(service_date);
GO

CREATE NONCLUSTERED INDEX IX_claims_medication ON pharmacy_claims(medication_id, service_date)
    ON ps_claims_monthly(service_date);
GO

CREATE NONCLUSTERED INDEX IX_claims_pharmacy ON pharmacy_claims(pharmacy_id, service_date)
    ON ps_claims_monthly(service_date);
GO

CREATE NONCLUSTERED INDEX IX_claims_claim_number ON pharmacy_claims(claim_number)
    ON ps_claims_monthly(service_date);
GO

-- Drug Interactions
CREATE TABLE drug_interactions (
    id              INT IDENTITY(1,1) PRIMARY KEY,
    medication_id_1 INT             NOT NULL,
    medication_id_2 INT             NOT NULL,
    severity        VARCHAR(20)     NOT NULL,           -- mild, moderate, severe, contraindicated
    clinical_effect NVARCHAR(500)   NOT NULL,
    recommendation  NVARCHAR(500)   NULL,
    source          VARCHAR(50)     NULL,               -- FDA, DrugBank, clinical study

    CONSTRAINT FK_interactions_med1 FOREIGN KEY (medication_id_1) REFERENCES medications(id),
    CONSTRAINT FK_interactions_med2 FOREIGN KEY (medication_id_2) REFERENCES medications(id),
    CONSTRAINT CK_interactions_severity CHECK (severity IN ('mild', 'moderate', 'severe', 'contraindicated'))
);
GO

-- Prior Authorizations
CREATE TABLE prior_authorizations (
    id              INT IDENTITY(1,1) PRIMARY KEY,
    auth_number     VARCHAR(30)     NOT NULL,
    patient_id      INT             NOT NULL,
    provider_id     INT             NOT NULL,
    medication_id   INT             NOT NULL,
    diagnosis_code  VARCHAR(10)     NULL,
    status          VARCHAR(20)     NOT NULL DEFAULT 'pending',  -- pending, approved, denied, expired
    requested_date  DATE            NOT NULL,
    decision_date   DATE            NULL,
    effective_date  DATE            NULL,
    expiration_date DATE            NULL,
    quantity_limit  DECIMAL(10,2)   NULL,
    days_supply_limit INT           NULL,
    denial_reason   NVARCHAR(500)   NULL,
    reviewer_notes  NVARCHAR(1000)  NULL,
    created_at      DATETIME2       NOT NULL DEFAULT SYSUTCDATETIME(),
    updated_at      DATETIME2       NOT NULL DEFAULT SYSUTCDATETIME(),

    CONSTRAINT UQ_prior_auth_number UNIQUE (auth_number),
    CONSTRAINT FK_prior_auth_patient FOREIGN KEY (patient_id) REFERENCES patients(id),
    CONSTRAINT FK_prior_auth_provider FOREIGN KEY (provider_id) REFERENCES providers(id),
    CONSTRAINT FK_prior_auth_medication FOREIGN KEY (medication_id) REFERENCES medications(id),
    CONSTRAINT CK_prior_auth_status CHECK (status IN ('pending', 'approved', 'denied', 'expired'))
);
GO

PRINT 'Healthcare OLTP schema created successfully.';
GO
