-- Connection statistics
SELECT
    s.login_name,
    s.host_name,
    s.program_name,
    COUNT(*) AS connection_count,
    SUM(CASE WHEN s.status = 'running' THEN 1 ELSE 0 END) AS active,
    SUM(CASE WHEN s.status = 'sleeping' THEN 1 ELSE 0 END) AS sleeping,
    MIN(s.login_time) AS oldest_connection,
    MAX(s.last_request_end_time) AS last_activity
FROM sys.dm_exec_sessions s
WHERE s.is_user_process = 1
GROUP BY s.login_name, s.host_name, s.program_name
ORDER BY connection_count DESC;
