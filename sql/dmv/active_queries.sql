-- Active queries with execution details
SELECT
    r.session_id,
    r.status,
    r.command,
    r.wait_type,
    r.wait_time AS wait_time_ms,
    r.total_elapsed_time AS elapsed_ms,
    r.cpu_time AS cpu_ms,
    r.reads AS logical_reads,
    r.writes,
    DB_NAME(r.database_id) AS database_name,
    SUBSTRING(t.text, (r.statement_start_offset/2)+1,
        ((CASE r.statement_end_offset
            WHEN -1 THEN DATALENGTH(t.text)
            ELSE r.statement_end_offset
        END - r.statement_start_offset)/2)+1) AS current_statement,
    r.blocking_session_id,
    s.login_name,
    s.host_name,
    s.program_name
FROM sys.dm_exec_requests r
    INNER JOIN sys.dm_exec_sessions s ON r.session_id = s.session_id
    CROSS APPLY sys.dm_exec_sql_text(r.sql_handle) t
WHERE r.session_id > 50
ORDER BY r.total_elapsed_time DESC;
