SET QUOTED_IDENTIFIER ON;
GO

-- ============================================================
-- sp_mask_phi_for_export: Returns patient data with PHI masked
-- ============================================================
CREATE OR ALTER PROCEDURE sp_mask_phi_for_export
AS
BEGIN
    SET NOCOUNT ON;

    SELECT
        LEFT(CONVERT(VARCHAR(64), HASHBYTES('SHA2_256', member_id), 2), 12)
            AS member_id,
        LEFT(first_name, 1) + '***' AS first_name,
        LEFT(last_name, 1) + '***' AS last_name,
        DATEFROMPARTS(YEAR(date_of_birth), 1, 1) AS date_of_birth,
        '****' AS ssn_last_four,
        '***-***-' + RIGHT(phone, 4) AS phone,
        LEFT(email, 1) + '***@***' AS email,
        '[REDACTED]' AS address_line1,
        city,
        state_code,
        zip_code,
        plan_type,
        group_number,
        effective_date,
        termination_date,
        is_active
    FROM patients;
END;
GO

-- ============================================================
-- sp_audit_phi_access: Records a PHI access event for HIPAA
-- ============================================================
CREATE OR ALTER PROCEDURE sp_audit_phi_access
    @user_name NVARCHAR(100),
    @action NVARCHAR(50),
    @table_name NVARCHAR(100),
    @record_count INT,
    @justification NVARCHAR(500)
AS
BEGIN
    SET NOCOUNT ON;

    INSERT INTO phi_access_log
        (user_name, action, table_name, record_count, justification, access_time)
    VALUES
        (@user_name, @action, @table_name, @record_count, @justification, SYSUTCDATETIME());
END;
GO
