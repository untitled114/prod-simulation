SET QUOTED_IDENTIFIER ON;
GO

-- ============================================================================
-- Seed Healthcare Data
-- Realistic providers, patients, medications, pharmacies, prescriptions, claims
-- ============================================================================

-- ============================================================================
-- Providers (20)
-- ============================================================================
INSERT INTO providers (npi, dea_number, first_name, last_name, specialty, practice_name, phone, state_code, zip_code)
VALUES
('1234567890', 'AB1234567', 'James', 'Wilson', 'Internal Medicine', 'Metro Primary Care', '555-0101', 'RI', '02903'),
('1234567891', 'BC2345678', 'Sarah', 'Chen', 'Cardiology', 'Heart Health Associates', '555-0102', 'RI', '02904'),
('1234567892', 'CD3456789', 'Michael', 'Patel', 'Endocrinology', 'Diabetes & Thyroid Center', '555-0103', 'MA', '02101'),
('1234567893', 'DE4567890', 'Emily', 'Rodriguez', 'Family Medicine', 'Community Health Partners', '555-0104', 'MA', '02102'),
('1234567894', 'EF5678901', 'David', 'Kim', 'Psychiatry', 'Behavioral Health Group', '555-0105', 'CT', '06101'),
('1234567895', 'FG6789012', 'Lisa', 'Thompson', 'Pulmonology', 'Breathing & Lung Clinic', '555-0106', 'CT', '06102'),
('1234567896', 'GH7890123', 'Robert', 'Jackson', 'Nephrology', 'Kidney Care Specialists', '555-0107', 'NY', '10001'),
('1234567897', 'HI8901234', 'Maria', 'Garcia', 'Oncology', 'Regional Cancer Center', '555-0108', 'NY', '10002'),
('1234567898', 'IJ9012345', 'Daniel', 'Lee', 'Rheumatology', 'Joint & Arthritis Center', '555-0109', 'NJ', '07101'),
('1234567899', 'JK0123456', 'Jennifer', 'Martinez', 'Neurology', 'Brain & Spine Associates', '555-0110', 'NJ', '07102'),
('2345678901', 'KL1234567', 'Thomas', 'Brown', 'Dermatology', 'Skin Health Clinic', '555-0111', 'PA', '19101'),
('2345678902', 'LM2345678', 'Amanda', 'Davis', 'Gastroenterology', 'Digestive Care Center', '555-0112', 'PA', '19102'),
('2345678903', 'MN3456789', 'Christopher', 'Taylor', 'Orthopedics', 'Bone & Joint Institute', '555-0113', 'MA', '02103'),
('2345678904', 'NO4567890', 'Jessica', 'Anderson', 'OB/GYN', 'Womens Wellness Center', '555-0114', 'MA', '02104'),
('2345678905', 'OP5678901', 'Matthew', 'White', 'Urology', 'Advanced Urology Group', '555-0115', 'RI', '02905'),
('2345678906', 'PQ6789012', 'Stephanie', 'Harris', 'Allergy/Immunology', 'Allergy & Asthma Clinic', '555-0116', 'RI', '02906'),
('2345678907', 'QR7890123', 'Andrew', 'Clark', 'Geriatrics', 'Senior Health Center', '555-0117', 'CT', '06103'),
('2345678908', 'RS8901234', 'Rachel', 'Lewis', 'Pediatrics', 'Childrens Medical Group', '555-0118', 'CT', '06104'),
('2345678909', 'ST9012345', 'Kevin', 'Walker', 'Pain Management', 'Pain Relief Specialists', '555-0119', 'NY', '10003'),
('2345678910', 'TU0123456', 'Nicole', 'Hall', 'Infectious Disease', 'ID Consultants', '555-0120', 'NY', '10004');
GO

-- ============================================================================
-- Medications (50 — real drug names, realistic NDC codes)
-- ============================================================================
INSERT INTO medications (ndc_code, drug_name, generic_name, drug_class, dea_schedule, dosage_form, strength, manufacturer, is_generic, is_formulary, formulary_tier, requires_prior_auth)
VALUES
-- Cardiovascular
('00071015523', 'Lisinopril', 'Lisinopril', 'ACE Inhibitor', NULL, 'Tablet', '10mg', 'Lupin Pharmaceuticals', 1, 1, 1, 0),
('00071015540', 'Lisinopril', 'Lisinopril', 'ACE Inhibitor', NULL, 'Tablet', '20mg', 'Lupin Pharmaceuticals', 1, 1, 1, 0),
('00093721898', 'Amlodipine', 'Amlodipine Besylate', 'Calcium Channel Blocker', NULL, 'Tablet', '5mg', 'Teva Pharmaceuticals', 1, 1, 1, 0),
('00093721910', 'Amlodipine', 'Amlodipine Besylate', 'Calcium Channel Blocker', NULL, 'Tablet', '10mg', 'Teva Pharmaceuticals', 1, 1, 1, 0),
('00378113001', 'Losartan', 'Losartan Potassium', 'ARB', NULL, 'Tablet', '50mg', 'Mylan Pharmaceuticals', 1, 1, 1, 0),
('00378113101', 'Losartan', 'Losartan Potassium', 'ARB', NULL, 'Tablet', '100mg', 'Mylan Pharmaceuticals', 1, 1, 1, 0),
('00069415030', 'Lipitor', 'Atorvastatin', 'Statin', NULL, 'Tablet', '20mg', 'Pfizer', 0, 1, 3, 0),
('00093505698', 'Atorvastatin', 'Atorvastatin Calcium', 'Statin', NULL, 'Tablet', '20mg', 'Teva Pharmaceuticals', 1, 1, 1, 0),
('00093505710', 'Atorvastatin', 'Atorvastatin Calcium', 'Statin', NULL, 'Tablet', '40mg', 'Teva Pharmaceuticals', 1, 1, 1, 0),
('00310075190', 'Metoprolol Succinate', 'Metoprolol Succinate ER', 'Beta Blocker', NULL, 'Tablet ER', '50mg', 'AstraZeneca', 1, 1, 1, 0),
-- Diabetes
('00002322230', 'Metformin', 'Metformin HCl', 'Biguanide', NULL, 'Tablet', '500mg', 'Bristol-Myers Squibb', 1, 1, 1, 0),
('00002322280', 'Metformin', 'Metformin HCl', 'Biguanide', NULL, 'Tablet', '1000mg', 'Bristol-Myers Squibb', 1, 1, 1, 0),
('00002147380', 'Trulicity', 'Dulaglutide', 'GLP-1 Agonist', NULL, 'Injection', '1.5mg/0.5mL', 'Eli Lilly', 0, 1, 3, 1),
('00169637115', 'Ozempic', 'Semaglutide', 'GLP-1 Agonist', NULL, 'Injection', '1mg/dose', 'Novo Nordisk', 0, 1, 3, 1),
('00310641001', 'Farxiga', 'Dapagliflozin', 'SGLT2 Inhibitor', NULL, 'Tablet', '10mg', 'AstraZeneca', 0, 1, 3, 1),
('00597013005', 'Glipizide', 'Glipizide', 'Sulfonylurea', NULL, 'Tablet', '5mg', 'Par Pharmaceutical', 1, 1, 1, 0),
-- Respiratory
('00173068220', 'Albuterol HFA', 'Albuterol Sulfate', 'Short-Acting Beta Agonist', NULL, 'Inhaler', '90mcg/inh', 'GlaxoSmithKline', 1, 1, 1, 0),
('00173071422', 'Advair Diskus', 'Fluticasone/Salmeterol', 'ICS/LABA Combination', NULL, 'Inhaler', '250/50mcg', 'GlaxoSmithKline', 0, 1, 3, 0),
('00186037020', 'Symbicort', 'Budesonide/Formoterol', 'ICS/LABA Combination', NULL, 'Inhaler', '160/4.5mcg', 'AstraZeneca', 0, 1, 3, 0),
('00597002001', 'Montelukast', 'Montelukast Sodium', 'Leukotriene Modifier', NULL, 'Tablet', '10mg', 'Par Pharmaceutical', 1, 1, 1, 0),
-- Mental Health
('00049490066', 'Sertraline', 'Sertraline HCl', 'SSRI', NULL, 'Tablet', '50mg', 'Pfizer', 1, 1, 1, 0),
('00049490082', 'Sertraline', 'Sertraline HCl', 'SSRI', NULL, 'Tablet', '100mg', 'Pfizer', 1, 1, 1, 0),
('00228206250', 'Escitalopram', 'Escitalopram Oxalate', 'SSRI', NULL, 'Tablet', '10mg', 'Actavis', 1, 1, 1, 0),
('00093013805', 'Bupropion XL', 'Bupropion HCl XL', 'NDRI', NULL, 'Tablet ER', '150mg', 'Teva Pharmaceuticals', 1, 1, 1, 0),
('00093013810', 'Bupropion XL', 'Bupropion HCl XL', 'NDRI', NULL, 'Tablet ER', '300mg', 'Teva Pharmaceuticals', 1, 1, 1, 0),
-- Pain / Controlled
('00591024601', 'Gabapentin', 'Gabapentin', 'Anticonvulsant', NULL, 'Capsule', '300mg', 'Watson Labs', 1, 1, 1, 0),
('52544025228', 'Tramadol', 'Tramadol HCl', 'Opioid Analgesic', 4, 'Tablet', '50mg', 'Teva Pharmaceuticals', 1, 1, 2, 0),
('00406802001', 'Oxycodone', 'Oxycodone HCl', 'Opioid Analgesic', 2, 'Tablet', '5mg', 'Mallinckrodt', 1, 1, 2, 0),
('00228252611', 'Cyclobenzaprine', 'Cyclobenzaprine HCl', 'Muscle Relaxant', NULL, 'Tablet', '10mg', 'Actavis', 1, 1, 1, 0),
('59762170001', 'Meloxicam', 'Meloxicam', 'NSAID', NULL, 'Tablet', '15mg', 'Greenstone', 1, 1, 1, 0),
-- GI
('00378010001', 'Omeprazole', 'Omeprazole', 'Proton Pump Inhibitor', NULL, 'Capsule DR', '20mg', 'Mylan Pharmaceuticals', 1, 1, 1, 0),
('00378010101', 'Omeprazole', 'Omeprazole', 'Proton Pump Inhibitor', NULL, 'Capsule DR', '40mg', 'Mylan Pharmaceuticals', 1, 1, 1, 0),
('66685100203', 'Pantoprazole', 'Pantoprazole Sodium', 'Proton Pump Inhibitor', NULL, 'Tablet DR', '40mg', 'Camber Pharmaceuticals', 1, 1, 1, 0),
-- Thyroid
('00074662690', 'Levothyroxine', 'Levothyroxine Sodium', 'Thyroid Hormone', NULL, 'Tablet', '50mcg', 'AbbVie', 1, 1, 1, 0),
('00074662790', 'Levothyroxine', 'Levothyroxine Sodium', 'Thyroid Hormone', NULL, 'Tablet', '100mcg', 'AbbVie', 1, 1, 1, 0),
-- Anticoagulants
('65162068209', 'Eliquis', 'Apixaban', 'Direct Oral Anticoagulant', NULL, 'Tablet', '5mg', 'Bristol-Myers Squibb', 0, 1, 3, 0),
('63539068390', 'Xarelto', 'Rivaroxaban', 'Direct Oral Anticoagulant', NULL, 'Tablet', '20mg', 'Janssen', 0, 1, 3, 0),
('00555090202', 'Warfarin', 'Warfarin Sodium', 'Vitamin K Antagonist', NULL, 'Tablet', '5mg', 'Teva Pharmaceuticals', 1, 1, 1, 0),
-- Antibiotics
('00093315701', 'Amoxicillin', 'Amoxicillin', 'Penicillin', NULL, 'Capsule', '500mg', 'Teva Pharmaceuticals', 1, 1, 1, 0),
('00093229501', 'Azithromycin', 'Azithromycin', 'Macrolide', NULL, 'Tablet', '250mg', 'Teva Pharmaceuticals', 1, 1, 1, 0),
('00093515701', 'Ciprofloxacin', 'Ciprofloxacin HCl', 'Fluoroquinolone', NULL, 'Tablet', '500mg', 'Teva Pharmaceuticals', 1, 1, 1, 0),
-- Specialty
('59676022528', 'Humira', 'Adalimumab', 'TNF Inhibitor', NULL, 'Injection', '40mg/0.4mL', 'AbbVie', 0, 1, 4, 1),
('50242006006', 'Keytruda', 'Pembrolizumab', 'PD-1 Inhibitor', NULL, 'IV Infusion', '100mg/4mL', 'Merck', 0, 1, 4, 1),
-- Misc common
('00406012305', 'Prednisone', 'Prednisone', 'Corticosteroid', NULL, 'Tablet', '10mg', 'Mallinckrodt', 1, 1, 1, 0),
('00781107501', 'Hydrochlorothiazide', 'Hydrochlorothiazide', 'Thiazide Diuretic', NULL, 'Tablet', '25mg', 'Sandoz', 1, 1, 1, 0),
('00093071498', 'Tamsulosin', 'Tamsulosin HCl', 'Alpha Blocker', NULL, 'Capsule', '0.4mg', 'Teva Pharmaceuticals', 1, 1, 1, 0),
('00093537901', 'Clopidogrel', 'Clopidogrel Bisulfate', 'Antiplatelet', NULL, 'Tablet', '75mg', 'Teva Pharmaceuticals', 1, 1, 1, 0),
('00185001001', 'Furosemide', 'Furosemide', 'Loop Diuretic', NULL, 'Tablet', '40mg', 'Sandoz', 1, 1, 1, 0),
('00093083201', 'Spironolactone', 'Spironolactone', 'Potassium-Sparing Diuretic', NULL, 'Tablet', '25mg', 'Teva Pharmaceuticals', 1, 1, 1, 0),
('00093005601', 'Allopurinol', 'Allopurinol', 'Xanthine Oxidase Inhibitor', NULL, 'Tablet', '300mg', 'Teva Pharmaceuticals', 1, 1, 1, 0);
GO

-- ============================================================================
-- Pharmacies (10)
-- ============================================================================
INSERT INTO pharmacies (ncpdp_id, name, chain_name, pharmacy_type, phone, state_code, zip_code, npi, is_preferred)
VALUES
('3456789', 'CVS Pharmacy #4521', 'CVS Health', 'retail', '555-0201', 'RI', '02903', '1111111111', 1),
('3456790', 'CVS Pharmacy #8734', 'CVS Health', 'retail', '555-0202', 'MA', '02101', '1111111112', 1),
('3456791', 'CVS Specialty Pharmacy', 'CVS Health', 'specialty', '555-0203', 'RI', '02905', '1111111113', 1),
('3456792', 'CVS Caremark Mail Order', 'CVS Health', 'mail_order', '555-0204', 'AZ', '85281', '1111111114', 1),
('3456793', 'Walgreens #12345', 'Walgreens', 'retail', '555-0205', 'MA', '02102', '2222222221', 0),
('3456794', 'Rite Aid #9876', 'Rite Aid', 'retail', '555-0206', 'CT', '06101', '3333333331', 0),
('3456795', 'Walmart Pharmacy #5432', 'Walmart', 'retail', '555-0207', 'NY', '10001', '4444444441', 0),
('3456796', 'Costco Pharmacy #123', 'Costco', 'retail', '555-0208', 'NJ', '07101', '5555555551', 0),
('3456797', 'Community Compounding Rx', NULL, 'compounding', '555-0209', 'PA', '19101', '6666666661', 0),
('3456798', 'Express Scripts Mail', 'Express Scripts', 'mail_order', '555-0210', 'MO', '63101', '7777777771', 0);
GO

-- ============================================================================
-- Patients (200) — generated via cross-join patterns
-- ============================================================================
;WITH first_names AS (
    SELECT * FROM (VALUES
        ('John'), ('Jane'), ('Robert'), ('Maria'), ('Michael'),
        ('Sarah'), ('David'), ('Emily'), ('James'), ('Lisa'),
        ('William'), ('Jennifer'), ('Richard'), ('Amanda'), ('Thomas'),
        ('Jessica'), ('Daniel'), ('Stephanie'), ('Kevin'), ('Nicole')
    ) AS t(name)
),
last_names AS (
    SELECT * FROM (VALUES
        ('Smith'), ('Johnson'), ('Williams'), ('Brown'), ('Jones'),
        ('Garcia'), ('Miller'), ('Davis'), ('Rodriguez'), ('Martinez')
    ) AS t(name)
),
numbered AS (
    SELECT
        f.name AS first_name,
        l.name AS last_name,
        ROW_NUMBER() OVER (ORDER BY f.name, l.name) AS rn
    FROM first_names f CROSS JOIN last_names l
)
INSERT INTO patients (member_id, first_name, last_name, date_of_birth, gender, phone, email,
                      state_code, zip_code, plan_type, plan_group, pcp_provider_id)
SELECT
    'MBR' + RIGHT('000000' + CAST(rn AS VARCHAR), 6),
    first_name,
    last_name,
    DATEADD(DAY, -(rn * 137 % 25000 + 6570), '2026-01-01'),  -- Ages 18-86
    CASE WHEN rn % 2 = 0 THEN 'F' ELSE 'M' END,
    '555-' + RIGHT('0000' + CAST(1000 + rn AS VARCHAR), 4),
    LOWER(first_name) + '.' + LOWER(last_name) + CAST(rn AS VARCHAR) + '@email.com',
    CASE rn % 6
        WHEN 0 THEN 'RI' WHEN 1 THEN 'MA' WHEN 2 THEN 'CT'
        WHEN 3 THEN 'NY' WHEN 4 THEN 'NJ' ELSE 'PA' END,
    CASE rn % 6
        WHEN 0 THEN '02903' WHEN 1 THEN '02101' WHEN 2 THEN '06101'
        WHEN 3 THEN '10001' WHEN 4 THEN '07101' ELSE '19101' END,
    CASE rn % 4
        WHEN 0 THEN 'Commercial' WHEN 1 THEN 'Medicare'
        WHEN 2 THEN 'Medicaid' ELSE 'Commercial' END,
    'GRP' + RIGHT('000' + CAST(rn % 20 + 1 AS VARCHAR), 3),
    (rn % 20) + 1  -- Distribute across 20 providers
FROM numbered
WHERE rn <= 200;
GO

-- ============================================================================
-- Prescriptions (500) — distributed across patients, providers, medications
-- ============================================================================
;WITH rx_data AS (
    SELECT
        ROW_NUMBER() OVER (ORDER BY p.id, m.id) AS rn,
        p.id AS patient_id,
        ((p.id - 1) % 20) + 1 AS provider_id,
        m.id AS medication_id
    FROM patients p
    CROSS JOIN medications m
    WHERE p.id <= 100 AND m.id <= 50  -- 100 patients × 50 meds, take first 500
)
INSERT INTO prescriptions (rx_number, patient_id, provider_id, medication_id, diagnosis_code,
                           quantity, days_supply, refills_authorized, refills_remaining,
                           daw_code, prescribed_date)
SELECT
    'RX' + RIGHT('00000000' + CAST(rn AS VARCHAR), 8),
    patient_id,
    provider_id,
    medication_id,
    CASE (rn % 10)
        WHEN 0 THEN 'I10'      -- Hypertension
        WHEN 1 THEN 'E11.9'    -- Type 2 Diabetes
        WHEN 2 THEN 'E78.5'    -- Hyperlipidemia
        WHEN 3 THEN 'J45.909'  -- Asthma
        WHEN 4 THEN 'F32.9'    -- Major Depression
        WHEN 5 THEN 'M79.3'    -- Fibromyalgia
        WHEN 6 THEN 'K21.0'    -- GERD
        WHEN 7 THEN 'E03.9'    -- Hypothyroidism
        WHEN 8 THEN 'I48.91'   -- Atrial Fibrillation
        ELSE 'J06.9'           -- Upper Respiratory Infection
    END,
    CASE WHEN rn % 3 = 0 THEN 90 WHEN rn % 3 = 1 THEN 30 ELSE 60 END,
    CASE WHEN rn % 3 = 0 THEN 90 WHEN rn % 3 = 1 THEN 30 ELSE 60 END,
    CASE WHEN rn % 5 = 0 THEN 0 ELSE 3 END,
    CASE WHEN rn % 5 = 0 THEN 0 ELSE 3 END,
    0,
    DATEADD(DAY, -(rn % 365), '2025-12-31')
FROM rx_data
WHERE rn <= 500;
GO

-- ============================================================================
-- Pharmacy Claims (2000) — spread across 2025
-- ============================================================================
;WITH claim_data AS (
    SELECT
        ROW_NUMBER() OVER (ORDER BY rx.id, n.n) AS rn,
        rx.id AS prescription_id,
        rx.patient_id,
        (rx.patient_id % 10) + 1 AS pharmacy_id,
        ((rx.patient_id - 1) % 20) + 1 AS provider_id,
        rx.medication_id,
        n.n AS fill_seq
    FROM prescriptions rx
    CROSS JOIN (VALUES (1),(2),(3),(4)) AS n(n)
    WHERE rx.id <= 500
)
INSERT INTO pharmacy_claims (
    claim_number, patient_id, prescription_id, pharmacy_id, provider_id,
    medication_id, service_date, fill_number, quantity_dispensed, days_supply,
    ingredient_cost, dispensing_fee, copay_amount, plan_paid,
    claim_status, daw_code, is_generic, is_mail_order, is_specialty
)
SELECT
    'CLM' + RIGHT('0000000000' + CAST(rn AS VARCHAR), 10),
    patient_id,
    prescription_id,
    pharmacy_id,
    provider_id,
    medication_id,
    DATEADD(DAY, (fill_seq - 1) * 30 + (rn % 28), '2025-01-01'),
    fill_seq,
    CASE WHEN rn % 3 = 0 THEN 90.00 WHEN rn % 3 = 1 THEN 30.00 ELSE 60.00 END,
    CASE WHEN rn % 3 = 0 THEN 90 WHEN rn % 3 = 1 THEN 30 ELSE 60 END,
    CAST(5.00 + (rn % 200) * 1.50 AS DECIMAL(10,2)),     -- $5-$305 ingredient cost
    CAST(1.50 + (rn % 5) * 0.50 AS DECIMAL(10,2)),       -- $1.50-$3.50 dispensing
    CASE WHEN rn % 4 = 0 THEN 0.00
         WHEN rn % 4 = 1 THEN 10.00
         WHEN rn % 4 = 2 THEN 25.00
         ELSE 50.00 END,
    CAST(5.00 + (rn % 200) * 1.50 + 1.50 + (rn % 5) * 0.50
         - CASE WHEN rn % 4 = 0 THEN 0.00
                WHEN rn % 4 = 1 THEN 10.00
                WHEN rn % 4 = 2 THEN 25.00
                ELSE 50.00 END AS DECIMAL(10,2)),
    CASE WHEN rn % 50 = 0 THEN 'rejected'
         WHEN rn % 100 = 0 THEN 'reversed'
         ELSE 'paid' END,
    0,
    CASE WHEN medication_id <= 40 THEN 1 ELSE 0 END,     -- Most generics
    CASE WHEN pharmacy_id IN (4, 10) THEN 1 ELSE 0 END,  -- Mail order pharmacies
    CASE WHEN medication_id IN (42, 43) THEN 1 ELSE 0 END -- Specialty meds
FROM claim_data
WHERE rn <= 2000;
GO

-- ============================================================================
-- Populate dim_date (2025-2026)
-- ============================================================================
;WITH dates AS (
    SELECT CAST('2025-01-01' AS DATE) AS dt
    UNION ALL
    SELECT DATEADD(DAY, 1, dt)
    FROM dates
    WHERE dt < '2026-12-31'
)
INSERT INTO dim_date (
    date_key, full_date, day_of_week, day_name, day_of_month, day_of_year,
    week_of_year, month_number, month_name, quarter_number, year_number,
    is_weekend, fiscal_quarter, fiscal_year
)
SELECT
    YEAR(dt) * 10000 + MONTH(dt) * 100 + DAY(dt),
    dt,
    DATEPART(WEEKDAY, dt),
    DATENAME(WEEKDAY, dt),
    DAY(dt),
    DATEPART(DAYOFYEAR, dt),
    DATEPART(WEEK, dt),
    MONTH(dt),
    DATENAME(MONTH, dt),
    DATEPART(QUARTER, dt),
    YEAR(dt),
    CASE WHEN DATEPART(WEEKDAY, dt) IN (1, 7) THEN 1 ELSE 0 END,
    -- CVS fiscal quarter (Feb start)
    CASE WHEN MONTH(dt) IN (2,3,4) THEN 1
         WHEN MONTH(dt) IN (5,6,7) THEN 2
         WHEN MONTH(dt) IN (8,9,10) THEN 3
         ELSE 4 END,
    CASE WHEN MONTH(dt) >= 2 THEN YEAR(dt) ELSE YEAR(dt) - 1 END
FROM dates
OPTION (MAXRECURSION 800);
GO

-- ============================================================================
-- Drug Interactions (10 common interactions)
-- ============================================================================
INSERT INTO drug_interactions (medication_id_1, medication_id_2, severity, clinical_effect, recommendation, source)
VALUES
(1, 48, 'moderate', 'ACE inhibitors + potassium-sparing diuretics may cause hyperkalemia', 'Monitor serum potassium levels regularly', 'FDA'),
(27, 28, 'severe', 'Tramadol + Oxycodone: additive CNS depression and respiratory depression', 'Avoid concurrent use; use lowest effective doses', 'FDA'),
(21, 24, 'moderate', 'Sertraline + Bupropion: increased seizure risk', 'Monitor for seizure activity; consider dose adjustment', 'DrugBank'),
(36, 47, 'severe', 'Apixaban + Clopidogrel: significantly increased bleeding risk', 'Use with caution; monitor for signs of bleeding', 'FDA'),
(1, 30, 'moderate', 'ACE inhibitors + NSAIDs may reduce antihypertensive effect and impair renal function', 'Monitor blood pressure and renal function', 'Clinical Study'),
(27, 21, 'severe', 'Tramadol + SSRI: risk of serotonin syndrome', 'Monitor for agitation, confusion, rapid heart rate', 'FDA'),
(28, 29, 'moderate', 'Oxycodone + Cyclobenzaprine: enhanced CNS depression', 'Reduce doses; monitor for sedation', 'DrugBank'),
(37, 38, 'severe', 'Xarelto + Warfarin: critically increased bleeding risk', 'Never use concurrently; proper washout required', 'FDA'),
(13, 14, 'moderate', 'Trulicity + Ozempic: duplicate GLP-1 therapy with no added benefit', 'Use only one GLP-1 agonist at a time', 'Clinical Study'),
(7, 8, 'mild', 'Lipitor brand + Atorvastatin generic: therapeutic duplication', 'Verify not dispensing both brand and generic', 'Pharmacy');
GO

PRINT 'Healthcare data seeded successfully.';
GO
