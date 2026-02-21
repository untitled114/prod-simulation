-- Monitoring stored procedures
SET QUOTED_IDENTIFIER ON;
GO

USE SentinelDB;
GO

-- Capture a point-in-time health snapshot from DMVs
IF OBJECT_ID('sp_capture_health_snapshot', 'P') IS NOT NULL
    DROP PROCEDURE sp_capture_health_snapshot;
GO

CREATE PROCEDURE sp_capture_health_snapshot
AS
BEGIN
    SET NOCOUNT ON;

    DECLARE @cpu_percent FLOAT;
    DECLARE @memory_used_mb FLOAT;
    DECLARE @memory_total_mb FLOAT;
    DECLARE @connection_count INT;
    DECLARE @blocking_count INT;
    DECLARE @long_query_count INT;
    DECLARE @tempdb_used_mb FLOAT;
    DECLARE @avg_wait_ms FLOAT;
    DECLARE @status VARCHAR(20) = 'healthy';

    -- CPU from ring buffer (last reading)
    SELECT TOP 1 @cpu_percent = record.value('(./Record/SchedulerMonitorEvent/SystemHealth/SystemIdle)[1]', 'int')
    FROM (
        SELECT CAST(record AS XML) AS record
        FROM sys.dm_os_ring_buffers
        WHERE ring_buffer_type = N'RING_BUFFER_SCHEDULER_MONITOR'
    ) AS x;
    SET @cpu_percent = 100.0 - ISNULL(@cpu_percent, 0);

    -- Memory
    SELECT
        @memory_used_mb = (total_physical_memory_kb - available_physical_memory_kb) / 1024.0,
        @memory_total_mb = total_physical_memory_kb / 1024.0
    FROM sys.dm_os_sys_memory;

    -- Connections
    SELECT @connection_count = COUNT(*) FROM sys.dm_exec_connections;

    -- Blocking chains
    SELECT @blocking_count = COUNT(*)
    FROM sys.dm_exec_requests
    WHERE blocking_session_id <> 0;

    -- Long-running queries (>30s)
    SELECT @long_query_count = COUNT(*)
    FROM sys.dm_exec_requests
    WHERE total_elapsed_time > 30000
      AND session_id > 50;

    -- TempDB usage
    SELECT @tempdb_used_mb = SUM(unallocated_extent_page_count) * 8.0 / 1024.0
    FROM sys.dm_db_file_space_usage;

    -- Average wait time
    SELECT @avg_wait_ms = AVG(CAST(wait_time_ms AS FLOAT))
    FROM sys.dm_os_wait_stats
    WHERE wait_type NOT LIKE '%SLEEP%'
      AND wait_type NOT LIKE '%IDLE%'
      AND wait_type NOT LIKE '%QUEUE%';

    INSERT INTO health_snapshots (cpu_percent, memory_used_mb, memory_total_mb,
        connection_count, blocking_count, long_query_count, tempdb_used_mb, avg_wait_ms, status)
    VALUES (@cpu_percent, @memory_used_mb, @memory_total_mb,
        @connection_count, @blocking_count, @long_query_count, @tempdb_used_mb, @avg_wait_ms, @status);

    -- Return the snapshot
    SELECT TOP 1 * FROM health_snapshots ORDER BY id DESC;
END;
GO

PRINT 'Monitoring procedures created successfully.';
GO
