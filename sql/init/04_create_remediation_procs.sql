-- Remediation stored procedures
SET QUOTED_IDENTIFIER ON;
GO

USE SentinelDB;
GO

-- Kill a blocking session
IF OBJECT_ID('sp_kill_session', 'P') IS NOT NULL
    DROP PROCEDURE sp_kill_session;
GO

CREATE PROCEDURE sp_kill_session
    @session_id INT
AS
BEGIN
    SET NOCOUNT ON;
    DECLARE @sql NVARCHAR(100) = N'KILL ' + CAST(@session_id AS NVARCHAR(10));
    EXEC sp_executesql @sql;
END;
GO

-- Clean up stale sessions (idle > N minutes)
IF OBJECT_ID('sp_cleanup_stale_sessions', 'P') IS NOT NULL
    DROP PROCEDURE sp_cleanup_stale_sessions;
GO

CREATE PROCEDURE sp_cleanup_stale_sessions
    @idle_minutes INT = 60
AS
BEGIN
    SET NOCOUNT ON;
    DECLARE @sid INT;
    DECLARE @killed INT = 0;

    DECLARE cur CURSOR LOCAL FAST_FORWARD FOR
        SELECT session_id
        FROM sys.dm_exec_sessions
        WHERE is_user_process = 1
          AND status = 'sleeping'
          AND last_request_end_time < DATEADD(MINUTE, -@idle_minutes, GETDATE())
          AND session_id <> @@SPID;

    OPEN cur;
    FETCH NEXT FROM cur INTO @sid;

    WHILE @@FETCH_STATUS = 0
    BEGIN
        BEGIN TRY
            EXEC sp_kill_session @sid;
            SET @killed = @killed + 1;
        END TRY
        BEGIN CATCH
            -- Session may have already closed
        END CATCH
        FETCH NEXT FROM cur INTO @sid;
    END

    CLOSE cur;
    DEALLOCATE cur;

    SELECT @killed AS sessions_killed;
END;
GO

-- Quarantine bad data by moving rows to a quarantine table
IF OBJECT_ID('sp_quarantine_rows', 'P') IS NOT NULL
    DROP PROCEDURE sp_quarantine_rows;
GO

CREATE PROCEDURE sp_quarantine_rows
    @table_name NVARCHAR(200),
    @column_name NVARCHAR(200),
    @match_value NVARCHAR(500)
AS
BEGIN
    SET NOCOUNT ON;

    -- Validate table exists
    IF NOT EXISTS (SELECT 1 FROM sys.tables WHERE name = @table_name)
    BEGIN
        RAISERROR('Table does not exist: %s', 16, 1, @table_name);
        RETURN;
    END

    -- Validate column exists on the table
    IF NOT EXISTS (
        SELECT 1 FROM sys.columns c
        JOIN sys.tables t ON c.object_id = t.object_id
        WHERE t.name = @table_name AND c.name = @column_name
    )
    BEGIN
        RAISERROR('Column does not exist: %s.%s', 16, 1, @table_name, @column_name);
        RETURN;
    END

    DECLARE @quarantine_table NVARCHAR(200) = @table_name + '_quarantine';
    DECLARE @sql NVARCHAR(MAX);

    -- Create quarantine table if not exists (clone structure)
    SET @sql = N'IF NOT EXISTS (SELECT 1 FROM sys.tables WHERE name = ''' + @quarantine_table + N''')
        SELECT TOP 0 *, SYSUTCDATETIME() AS quarantined_at INTO ' + QUOTENAME(@quarantine_table) + N' FROM ' + QUOTENAME(@table_name);
    EXEC sp_executesql @sql;

    -- Move matching rows using parameterized condition
    SET @sql = N'INSERT INTO ' + QUOTENAME(@quarantine_table) + N'
        SELECT *, SYSUTCDATETIME() FROM ' + QUOTENAME(@table_name) + N' WHERE ' + QUOTENAME(@column_name) + N' = @val';
    EXEC sp_executesql @sql, N'@val NVARCHAR(500)', @val = @match_value;

    SET @sql = N'DELETE FROM ' + QUOTENAME(@table_name) + N' WHERE ' + QUOTENAME(@column_name) + N' = @val';
    EXEC sp_executesql @sql, N'@val NVARCHAR(500)', @val = @match_value;

    SELECT @@ROWCOUNT AS rows_quarantined;
END;
GO

PRINT 'Remediation procedures created successfully.';
GO
