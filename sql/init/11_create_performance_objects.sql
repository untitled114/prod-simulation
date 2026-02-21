SET QUOTED_IDENTIFIER ON;
GO

-- ============================================================================
-- Performance Optimization Objects
-- Indexed view, statistics maintenance, partition monitoring
-- ============================================================================

-- Indexed View: Claims aggregated by drug class (SCHEMABINDING required)
CREATE OR ALTER VIEW vw_claims_by_drug_class
WITH SCHEMABINDING
AS
SELECT
    m.drug_class,
    pc.service_date,
    COUNT_BIG(*) AS claim_count,
    SUM(pc.ingredient_cost + pc.dispensing_fee) AS total_cost,
    SUM(pc.copay_amount) AS total_copays,
    SUM(pc.plan_paid) AS total_plan_paid,
    SUM(CASE WHEN pc.is_generic = 1 THEN 1 ELSE 0 END) AS generic_count,
    SUM(pc.quantity_dispensed) AS total_quantity,
    SUM(CAST(pc.days_supply AS BIGINT)) AS total_days_supply
FROM dbo.pharmacy_claims pc
INNER JOIN dbo.medications m ON m.id = pc.medication_id
WHERE pc.claim_status = 'paid'
GROUP BY m.drug_class, pc.service_date;
GO

-- Clustered index on the view (materializes it)
CREATE UNIQUE CLUSTERED INDEX IX_vw_claims_drug_class
    ON vw_claims_by_drug_class(drug_class, service_date);
GO

-- ============================================================================
-- sp_maintenance_update_statistics: Update statistics for all user tables
-- ============================================================================
CREATE OR ALTER PROCEDURE sp_maintenance_update_statistics
    @sample_percent INT = 50
AS
BEGIN
    SET NOCOUNT ON;

    DECLARE @sql NVARCHAR(500);
    DECLARE @table_name NVARCHAR(256);
    DECLARE @tables_updated INT = 0;

    DECLARE table_cursor CURSOR LOCAL FAST_FORWARD FOR
        SELECT QUOTENAME(s.name) + '.' + QUOTENAME(t.name)
        FROM sys.tables t
        INNER JOIN sys.schemas s ON s.schema_id = t.schema_id
        WHERE t.type = 'U'
          AND t.is_ms_shipped = 0
        ORDER BY t.name;

    OPEN table_cursor;
    FETCH NEXT FROM table_cursor INTO @table_name;

    WHILE @@FETCH_STATUS = 0
    BEGIN
        SET @sql = N'UPDATE STATISTICS ' + @table_name
                 + N' WITH SAMPLE ' + CAST(@sample_percent AS NVARCHAR(3)) + N' PERCENT';
        EXEC sp_executesql @sql;
        SET @tables_updated = @tables_updated + 1;
        FETCH NEXT FROM table_cursor INTO @table_name;
    END

    CLOSE table_cursor;
    DEALLOCATE table_cursor;

    SELECT @tables_updated AS tables_updated, 'success' AS status;
END;
GO

-- ============================================================================
-- sp_maintenance_partition_info: Partition monitoring utility
-- Shows row counts and space usage per partition
-- ============================================================================
CREATE OR ALTER PROCEDURE sp_maintenance_partition_info
    @table_name NVARCHAR(128) = 'pharmacy_claims'
AS
BEGIN
    SET NOCOUNT ON;

    SELECT
        t.name AS table_name,
        ps.name AS partition_scheme,
        pf.name AS partition_function,
        p.partition_number,
        prv.value AS boundary_value,
        p.rows AS row_count,
        CAST(
            SUM(au.total_pages) * 8.0 / 1024 AS DECIMAL(10,2)
        ) AS size_mb,
        p.data_compression_desc AS compression
    FROM sys.partitions p
    INNER JOIN sys.tables t ON t.object_id = p.object_id
    INNER JOIN sys.indexes i ON i.object_id = p.object_id AND i.index_id = p.index_id
    INNER JOIN sys.allocation_units au ON au.container_id = p.hobt_id
    LEFT JOIN sys.partition_schemes ps ON ps.data_space_id = i.data_space_id
    LEFT JOIN sys.partition_functions pf ON pf.function_id = ps.function_id
    LEFT JOIN sys.partition_range_values prv
        ON prv.function_id = pf.function_id
        AND prv.boundary_id = p.partition_number - 1
    WHERE t.name = @table_name
      AND i.index_id IN (0, 1)  -- Heap or clustered index
    GROUP BY t.name, ps.name, pf.name, p.partition_number,
             prv.value, p.rows, p.data_compression_desc
    ORDER BY p.partition_number;
END;
GO

PRINT 'Performance optimization objects created successfully.';
GO
