# On-Call Runbook — SQL Server Sentinel

Standard operating procedures for on-call engineers monitoring SQL Server production environments.

---

## Severity Definitions

| Severity | Response Time | Description | Example |
|----------|--------------|-------------|---------|
| **Critical** | 15 minutes | Service-impacting, data at risk | CPU >90%, deadlocks, data corruption |
| **Warning** | 1 hour | Degraded performance, trending toward critical | CPU >70%, blocking chains, memory pressure |
| **Info** | Next business day | Informational, no action required | Job completed, validation passed |

## SLA Targets

| Metric | Target | Measurement |
|--------|--------|-------------|
| **Time to Acknowledge** | < 15 min (critical), < 1 hr (warning) | `acknowledged_at - detected_at` |
| **Time to Resolve** | < 1 hr (critical), < 4 hrs (warning) | `resolved_at - detected_at` |
| **Auto-Remediation Rate** | > 60% of incidents | `resolved_by = 'auto' / total resolved` |
| **False Positive Rate** | < 10% | Manual closures with no action taken |
| **Uptime** | 99.9% | Health status != 'critical' over rolling 30 days |

## Escalation Matrix

```
Detection (0 min)
    │
    ├── Auto-remediation attempts fix (0-30s)
    │       ├── Success → Incident RESOLVED (postmortem generated)
    │       └── Failure → continues to timer
    │
    ▼
Escalation Timer (5 min default)
    │
    ├── CRITICAL: Page on-call DBA immediately
    │       └── No response in 15 min → Page backup DBA + team lead
    │
    └── WARNING: Slack notification to #db-alerts
            └── No acknowledgment in 1 hr → Escalate to CRITICAL
```

### On-Call Rotation

| Role | Responsibility | Contact Method |
|------|---------------|----------------|
| **Primary On-Call** | First responder, acknowledges within SLA | PagerDuty / phone |
| **Secondary On-Call** | Backup if primary unavailable | PagerDuty / phone |
| **Team Lead** | Escalation point for unresolved critical incidents | Phone / Slack |
| **DBA Manager** | Business-hour escalation for recurring issues | Email / Slack |

---

## Incident Response Procedures

### 1. High CPU (> 90%)

**Symptoms:** Dashboard shows red CPU card, health status = critical

**Diagnosis:**
```sql
-- Step 1: Identify top CPU consumers
SELECT TOP 10
    r.session_id,
    r.cpu_time,
    r.total_elapsed_time / 1000 AS elapsed_seconds,
    r.status,
    t.text AS query_text,
    DB_NAME(r.database_id) AS database_name
FROM sys.dm_exec_requests r
CROSS APPLY sys.dm_exec_sql_text(r.sql_handle) t
WHERE r.session_id > 50
ORDER BY r.cpu_time DESC;

-- Step 2: Check if it's a single runaway query or systemic
SELECT
    COUNT(*) AS active_queries,
    AVG(cpu_time) AS avg_cpu_time,
    MAX(cpu_time) AS max_cpu_time
FROM sys.dm_exec_requests
WHERE session_id > 50;
```

**Resolution:**
1. If single runaway query → Kill the session: `KILL <session_id>`
2. If systemic → Check for missing indexes, parameter sniffing, or plan regression
3. If recurring → Add to monitoring thresholds, create alert rule

**Auto-Remediation:** Sentinel kills sessions consuming CPU for >2 minutes with no progress.

---

### 2. Blocking Chain Detected

**Symptoms:** Blocking count > 0, queries timing out, users reporting slowness

**Diagnosis:**
```sql
-- Step 1: Find the root blocker (head of chain)
WITH blocking_tree AS (
    SELECT
        session_id,
        blocking_session_id,
        wait_type,
        wait_time / 1000 AS wait_seconds,
        0 AS depth
    FROM sys.dm_exec_requests
    WHERE blocking_session_id = 0 AND session_id IN (
        SELECT blocking_session_id FROM sys.dm_exec_requests WHERE blocking_session_id <> 0
    )
    UNION ALL
    SELECT
        r.session_id,
        r.blocking_session_id,
        r.wait_type,
        r.wait_time / 1000,
        bt.depth + 1
    FROM sys.dm_exec_requests r
    JOIN blocking_tree bt ON r.blocking_session_id = bt.session_id
    WHERE bt.depth < 10
)
SELECT * FROM blocking_tree ORDER BY depth, session_id;

-- Step 2: Check what the root blocker is doing
SELECT
    s.session_id,
    s.login_name,
    s.host_name,
    s.program_name,
    r.command,
    t.text AS query_text
FROM sys.dm_exec_sessions s
LEFT JOIN sys.dm_exec_requests r ON s.session_id = r.session_id
OUTER APPLY sys.dm_exec_sql_text(r.sql_handle) t
WHERE s.session_id = <root_blocker_session_id>;
```

**Resolution:**
1. If root blocker is idle (no active request) → Kill it: `KILL <session_id>`
2. If root blocker is running a legitimate long query → Wait or optimize the query
3. If application-level issue → Notify development team, add query timeout

**Auto-Remediation:** Sentinel kills idle blocking sessions (idle > 60 minutes) via `sp_cleanup_stale_sessions`.

---

### 3. Memory Pressure (> 90%)

**Symptoms:** Dashboard shows red memory card, queries slowing down

**Diagnosis:**
```sql
-- Step 1: Check overall memory state
SELECT
    total_physical_memory_kb / 1024 AS total_mb,
    available_physical_memory_kb / 1024 AS available_mb,
    system_memory_state_desc
FROM sys.dm_os_sys_memory;

-- Step 2: Find top memory consumers (cached plans)
SELECT TOP 10
    objtype,
    COUNT(*) AS plan_count,
    SUM(size_in_bytes) / 1024 / 1024 AS total_mb
FROM sys.dm_exec_cached_plans
GROUP BY objtype
ORDER BY total_mb DESC;

-- Step 3: Check for memory grants waiting
SELECT
    session_id,
    requested_memory_kb / 1024 AS requested_mb,
    granted_memory_kb / 1024 AS granted_mb,
    wait_time_ms / 1000 AS wait_seconds
FROM sys.dm_exec_query_memory_grants
WHERE granted_memory_kb IS NULL;
```

**Resolution:**
1. If plan cache bloat → `DBCC FREEPROCCACHE` (caution: causes plan recompilation)
2. If specific query consuming too much → Optimize the query or add `OPTION (MAX_GRANT_PERCENT = 25)`
3. If systemic → Review max server memory setting

---

### 4. Data Corruption Detected

**Symptoms:** Validation rules failing, unexpected NULL/negative values in business tables

**Diagnosis:**
```sql
-- Step 1: Run validation scorecard
-- API: POST /api/validation/run
-- Check which rules failed and examine sample_values

-- Step 2: Quantify the damage
SELECT COUNT(*) AS corrupt_rows
FROM orders
WHERE total_amount < 0 OR total_amount IS NULL;

-- Step 3: Identify when corruption started
SELECT MIN(order_date) AS first_corrupt_date
FROM orders
WHERE total_amount < 0;

-- Step 4: Check audit trail for source
SELECT TOP 10 *
FROM remediation_log
ORDER BY executed_at DESC;
```

**Resolution:**
1. Quarantine corrupt rows: `EXEC sp_quarantine_rows @table='orders', @column='status', @value='corrupted'`
2. Identify source (application bug, chaos scenario, manual insert)
3. Restore from backup if data loss is significant
4. Add CHECK constraints to prevent recurrence

**Auto-Remediation:** Sentinel quarantines rows matching corruption patterns.

---

### 5. Job Failure

**Symptoms:** Job status = 'failed' in job_runs table, scheduled tasks not completing

**Diagnosis:**
```sql
-- Step 1: Check recent failures
SELECT TOP 10
    job_name,
    started_at,
    completed_at,
    duration_ms,
    status,
    error_message
FROM job_runs
WHERE status = 'failed'
ORDER BY started_at DESC;

-- Step 2: Check if it's a recurring pattern
SELECT
    job_name,
    COUNT(*) AS failure_count,
    MAX(started_at) AS last_failure
FROM job_runs
WHERE status = 'failed'
  AND started_at > DATEADD(DAY, -7, SYSUTCDATETIME())
GROUP BY job_name
ORDER BY failure_count DESC;
```

**Resolution:**
1. Check error_message for root cause (timeout, permission, lock contention)
2. Re-run manually: `POST /api/jobs/trigger {"job_name": "<name>"}`
3. If recurring → adjust timeout, optimize underlying query, or reschedule to off-peak hours

---

### 6. Connection Flood (> 150 connections)

**Symptoms:** Connection count critical alert, new connections being refused

**Diagnosis:**
```sql
-- Step 1: Count connections by source
SELECT
    login_name,
    host_name,
    program_name,
    COUNT(*) AS connection_count
FROM sys.dm_exec_sessions
WHERE session_id > 50
GROUP BY login_name, host_name, program_name
ORDER BY connection_count DESC;

-- Step 2: Check for connection pool leaks (many sleeping connections)
SELECT
    status,
    COUNT(*) AS cnt
FROM sys.dm_exec_sessions
WHERE session_id > 50
GROUP BY status;
```

**Resolution:**
1. Kill idle connections: `EXEC sp_cleanup_stale_sessions @idle_minutes = 30`
2. If single application flooding → contact application team, check connection pool settings
3. Temporary measure: increase max connections in SQL Server config

---

## Monitoring Checklist (Start of Shift)

Run through these checks at the start of every on-call shift:

```bash
# 1. Check overall health
curl -s http://localhost:8000/api/health | python3 -m json.tool

# 2. Check for open incidents
curl -s http://localhost:8000/api/incidents/open | python3 -m json.tool

# 3. Review job history (last 24 hours)
curl -s "http://localhost:8000/api/jobs/history?limit=50" | python3 -m json.tool

# 4. Run validation scorecard
curl -s http://localhost:8000/api/validation/scorecard | python3 -m json.tool

# 5. Review recent postmortems for lessons learned
curl -s http://localhost:8000/api/incidents/postmortems/recent | python3 -m json.tool
```

## Handoff Template

Use this template when handing off to the next on-call engineer:

```
## On-Call Handoff — [DATE]

### Current State
- Health: [healthy/warning/critical]
- Open incidents: [count and brief description]
- Active chaos scenarios: [if any]

### Actions Taken This Shift
- [Incident #X]: [what happened, what was done, current state]
- [Job failure]: [which job, root cause, fixed?]

### Watch Items
- [Any trends to monitor]
- [Recurring issues to track]

### Upcoming Maintenance
- [Scheduled tasks, deployments, etc.]
```

## Post-Incident Review Process

After every **Critical** incident is resolved:

1. **Postmortem auto-generated** by Sentinel (summary, timeline, root cause)
2. **Review postmortem** within 24 hours — update root cause and lessons learned
3. **Action items** — file tickets for:
   - Missing monitoring (should we have caught this sooner?)
   - Missing automation (can we auto-remediate next time?)
   - Missing constraints (can we prevent at the DB level?)
4. **Share with team** — post in #db-incidents channel

### Blameless Postmortem Principles

- Focus on **systems**, not people
- Ask "how did the system allow this?" not "who caused this?"
- Every incident is a learning opportunity
- Better monitoring and automation prevent recurrence
