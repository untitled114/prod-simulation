-- Blocking chain detection via recursive CTE
WITH BlockingChain AS (
    -- Root blockers (sessions that block others but aren't blocked themselves)
    SELECT
        s.session_id,
        s.session_id AS root_blocker_id,
        0 AS chain_depth,
        CAST(CAST(s.session_id AS VARCHAR(10)) AS VARCHAR(MAX)) AS chain_path
    FROM sys.dm_exec_sessions s
    WHERE s.session_id IN (
        SELECT DISTINCT blocking_session_id
        FROM sys.dm_exec_requests
        WHERE blocking_session_id <> 0
    )
    AND s.session_id NOT IN (
        SELECT session_id
        FROM sys.dm_exec_requests
        WHERE blocking_session_id <> 0
    )

    UNION ALL

    -- Blocked sessions
    SELECT
        r.session_id,
        bc.root_blocker_id,
        bc.chain_depth + 1,
        CAST(bc.chain_path + ' -> ' + CAST(r.session_id AS VARCHAR(10)) AS VARCHAR(MAX))
    FROM sys.dm_exec_requests r
        INNER JOIN BlockingChain bc ON r.blocking_session_id = bc.session_id
    WHERE bc.chain_depth < 10  -- prevent infinite recursion
)
SELECT
    bc.session_id,
    bc.root_blocker_id,
    bc.chain_depth,
    bc.chain_path,
    s.login_name,
    s.host_name,
    s.status AS session_status,
    r.wait_type,
    r.wait_time AS wait_time_ms,
    r.total_elapsed_time AS elapsed_ms,
    SUBSTRING(t.text, 1, 500) AS sql_text
FROM BlockingChain bc
    INNER JOIN sys.dm_exec_sessions s ON bc.session_id = s.session_id
    LEFT JOIN sys.dm_exec_requests r ON bc.session_id = r.session_id
    OUTER APPLY sys.dm_exec_sql_text(r.sql_handle) t
ORDER BY bc.root_blocker_id, bc.chain_depth;
