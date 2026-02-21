-- Memory pressure indicators
SELECT
    total_physical_memory_kb / 1024 AS total_memory_mb,
    available_physical_memory_kb / 1024 AS available_memory_mb,
    (total_physical_memory_kb - available_physical_memory_kb) / 1024 AS used_memory_mb,
    CAST(100.0 * (total_physical_memory_kb - available_physical_memory_kb) / total_physical_memory_kb AS DECIMAL(5,2)) AS memory_used_percent,
    system_memory_state_desc
FROM sys.dm_os_sys_memory;
