-- CPU pressure indicators
SELECT
    record_id,
    SQLProcessUtilization AS sql_cpu_percent,
    SystemIdle AS system_idle_percent,
    100 - SystemIdle - SQLProcessUtilization AS other_process_cpu_percent,
    event_time
FROM (
    SELECT
        record.value('(./Record/@id)[1]', 'int') AS record_id,
        record.value('(./Record/SchedulerMonitorEvent/SystemHealth/SystemIdle)[1]', 'int') AS SystemIdle,
        record.value('(./Record/SchedulerMonitorEvent/SystemHealth/ProcessUtilization)[1]', 'int') AS SQLProcessUtilization,
        timestamp AS event_time
    FROM (
        SELECT timestamp, CAST(record AS XML) AS record
        FROM sys.dm_os_ring_buffers
        WHERE ring_buffer_type = N'RING_BUFFER_SCHEDULER_MONITOR'
            AND record LIKE '%<SystemHealth>%'
    ) AS x
) AS y
ORDER BY record_id DESC;
