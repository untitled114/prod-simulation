# SQL Server Sentinel — Beginner's Guide

A step-by-step walkthrough of how this project works, why each piece exists, and how to use it. No SQL Server experience required.

---

## Table of Contents

1. [What Is This Project?](#what-is-this-project)
2. [Prerequisites](#prerequisites)
3. [Getting Started](#getting-started)
4. [Understanding the Architecture](#understanding-the-architecture)
5. [Tour of the Codebase](#tour-of-the-codebase)
6. [How Monitoring Works](#how-monitoring-works)
7. [How Incidents Work](#how-incidents-work)
8. [How Data Validation Works](#how-data-validation-works)
9. [How Chaos Engineering Works](#how-chaos-engineering-works)
10. [How Auto-Remediation Works](#how-auto-remediation-works)
11. [How Jobs Work](#how-jobs-work)
12. [Using the API](#using-the-api)
13. [Using the Dashboard](#using-the-dashboard)
14. [Configuration Deep Dive](#configuration-deep-dive)
15. [Running Tests](#running-tests)
16. [Common Tasks](#common-tasks)
17. [Troubleshooting](#troubleshooting)
18. [Glossary](#glossary)

---

## What Is This Project?

SQL Server Sentinel is a **production monitoring system** for Microsoft SQL Server. In real companies, database administrators need to:

- **Watch** the database for problems (high CPU, memory pressure, blocked queries)
- **Detect** issues automatically, not wait for users to complain
- **Fix** problems automatically when possible
- **Document** what happened so the team can learn from it

This project simulates all of that. It has three layers:

| Layer | What It Does | Real-World Equivalent |
|-------|-------------|----------------------|
| **Chaos Engine** | Breaks things on purpose | Netflix's Chaos Monkey — tests resilience |
| **Sentinel Monitor** | Watches for problems and fixes them | Datadog, PagerDuty, or a DBA's monitoring scripts |
| **War Room Dashboard** | Shows everything in one place | Grafana dashboard in a NOC (Network Operations Center) |

**Why build this?** It demonstrates every skill a Data Engineer / SQL Server DBA needs: monitoring, troubleshooting, data quality, incident response, and automation.

---

## Prerequisites

You need two things installed:

### 1. Docker

Docker runs SQL Server in a container so you don't need to install it on your machine.

```bash
# Check if Docker is installed
docker --version
# Should show: Docker version 24+ or newer
```

If not installed: [Get Docker](https://docs.docker.com/get-docker/)

### 2. Docker Compose

Docker Compose orchestrates multiple containers (SQL Server + our Python app).

```bash
# Check if Docker Compose is installed (try both)
docker compose version       # Docker Compose V2 (plugin)
docker-compose version       # Docker Compose V1 (standalone)
# Either one works — you need at least version 2.0+
```

### Optional (for development)

- **Python 3.10+** — only needed if you want to run tests or develop locally
- **curl** — for testing API endpoints from the terminal
- **A web browser** — for the dashboard

---

## Getting Started

### Step 1: Clone the Repository

```bash
git clone https://github.com/untitled114/sql-server-sentinel.git
cd sql-server-sentinel
```

### Step 2: Create Your Environment File

The `.env` file holds your database password. We ship a template:

```bash
cp .env.example .env
```

Open `.env` and set a strong password:

```
SA_PASSWORD=YourStrongPasswordHere
```

**Why?** SQL Server requires a password for the `sa` (system administrator) account. The `.env` file is listed in `.gitignore` so it never gets committed to source control. This is standard practice — secrets stay local.

### Step 3: Start Everything

```bash
docker compose up -d
# or: docker-compose up -d
```

**What just happened?** Docker started three services:

1. **sqlserver** — Microsoft SQL Server 2022 Developer Edition
2. **init-db** — A one-shot container that runs 5 SQL scripts to create tables and seed data
3. **sentinel** — Our Python application (FastAPI + monitoring engine)

The `-d` flag runs them in the background (detached mode).

### Step 4: Verify It's Running

```bash
# Check all containers are healthy
docker compose ps
```

You should see:
- `sqlserver` — Status: **healthy**
- `init-db` — Status: **exited (0)** (it ran once and finished — that's correct)
- `sentinel` — Status: **up**

### Step 5: Open the Dashboard

Visit **http://localhost:8000** in your browser.

You'll see the War Room Dashboard with live health metrics updating every 5 seconds.

> **Port conflict?** If port 8000 is already in use, edit `.env` and add `SENTINEL_PORT=8080`, then restart with `docker compose up -d`.

### Step 6: Explore the API

Visit **http://localhost:8000/docs** for the interactive Swagger UI. You can try every endpoint directly from your browser.

---

## Understanding the Architecture

Here's how data flows through the system:

```
┌──────────────────────────────────────────────────────────────────┐
│                        SQL Server 2022                           │
│                                                                  │
│  ┌─────────────┐  ┌─────────────┐  ┌───────────────────────┐   │
│  │  DMVs        │  │  App Tables  │  │  Sentinel Tables      │   │
│  │  (built-in   │  │  customers   │  │  health_snapshots     │   │
│  │   system     │  │  orders      │  │  incidents            │   │
│  │   views)     │  │  order_items │  │  job_runs             │   │
│  └──────┬───────┘  └──────┬──────┘  │  validation_results   │   │
│         │                 │         │  remediation_log       │   │
│         │                 │         │  postmortems           │   │
│         │                 │         └───────────┬────────────┘   │
└─────────┼─────────────────┼─────────────────────┼────────────────┘
          │                 │                     │
          ▼                 ▼                     ▼
┌──────────────────────────────────────────────────────────────────┐
│                    Sentinel Python App                            │
│                                                                  │
│  ┌────────────┐  ┌──────────────┐  ┌────────────────────────┐   │
│  │  Health     │  │  Validation  │  │  Incident Manager      │   │
│  │  Collector  │  │  Engine      │  │  (lifecycle, dedup,    │   │
│  │  (reads     │  │  (checks     │  │   escalation,          │   │
│  │   DMVs)     │  │   data       │  │   postmortems)         │   │
│  └──────┬──────┘  │   quality)   │  └────────────┬───────────┘   │
│         │         └──────┬───────┘               │               │
│         │                │         ┌─────────────┴──────────┐   │
│         │                │         │  Remediation Engine     │   │
│         │                │         │  (auto-fixes problems)  │   │
│         │                │         └─────────────────────────┘   │
│  ┌──────┴──────┐  ┌──────┴───────┐  ┌──────────────────────┐   │
│  │  Chaos      │  │  Job         │  │  FastAPI              │   │
│  │  Engine     │  │  Runner      │  │  (REST API +          │   │
│  │  (breaks    │  │  (schedules  │  │   dashboard)           │   │
│  │   things)   │  │   tasks)     │  │                        │   │
│  └─────────────┘  └──────────────┘  └──────────────────────┘   │
└──────────────────────────────────────────────────────────────────┘
```

### What Are DMVs?

**Dynamic Management Views (DMVs)** are built-in SQL Server system views that expose real-time internal metrics. They're how DBAs monitor SQL Server in production:

| DMV | What It Shows |
|-----|---------------|
| `sys.dm_exec_requests` | Currently running queries (including blocked ones) |
| `sys.dm_os_ring_buffers` | CPU usage over time |
| `sys.dm_os_sys_memory` | RAM usage |
| `sys.dm_exec_connections` | Active connections |
| `sys.dm_db_file_space_usage` | TempDB disk usage |
| `sys.dm_os_wait_stats` | What queries are waiting on |

Sentinel reads these every 10 seconds and stores the results in the `health_snapshots` table.

---

## Tour of the Codebase

```
sql-server-sentinel/
│
├── sentinel/                  # Python application code
│   ├── api/                   # REST API layer (FastAPI)
│   │   ├── main.py            # App entry point, starts background tasks
│   │   ├── schemas.py         # Request/response data models (Pydantic)
│   │   ├── dependencies.py    # Shared state (engines, DB connection)
│   │   └── routes/            # One file per API group
│   │       ├── health.py      # GET /api/health, /api/health/sql
│   │       ├── incidents.py   # CRUD for incidents
│   │       ├── jobs.py        # List/trigger jobs
│   │       ├── validation.py  # Run validation, get scorecard
│   │       ├── chaos.py       # Trigger chaos scenarios
│   │       └── dashboard.py   # Aggregated data for the UI
│   │
│   ├── monitor/               # Core monitoring engines
│   │   ├── health.py          # Reads DMVs, evaluates thresholds
│   │   ├── blocker_detector.py # Finds blocking chains via recursive CTE
│   │   └── incident_manager.py # Incident lifecycle state machine
│   │
│   ├── validation/            # Data quality checks
│   │   ├── rules.py           # 6 rule types (null, range, FK, duplicate, etc.)
│   │   └── engine.py          # Runs all rules, generates scorecard
│   │
│   ├── chaos/                 # Chaos engineering
│   │   ├── scenarios.py       # 6 built-in failure scenarios
│   │   └── engine.py          # Manages cooldowns, triggers scenarios
│   │
│   ├── remediation/           # Auto-fix engine
│   │   ├── actions.py         # Built-in fix actions (kill session, restart job)
│   │   └── engine.py          # Pattern-matches incidents to fixes
│   │
│   ├── jobs/                  # Job scheduler
│   │   └── runner.py          # Cron-like scheduler for recurring T-SQL tasks
│   │
│   ├── config/                # Configuration
│   │   ├── models.py          # Pydantic models for YAML config
│   │   └── loader.py          # Loads YAML with ${ENV_VAR} substitution
│   │
│   ├── db/                    # Database layer
│   │   ├── connection.py      # pyodbc connection manager
│   │   └── queries.py         # Loads .sql files from disk
│   │
│   └── web/                   # Dashboard frontend
│       ├── templates/index.html
│       └── static/
│           ├── css/sentinel.css
│           └── js/sentinel.js
│
├── sql/                       # All SQL code
│   ├── init/                  # Run once at startup (creates schema + seed data)
│   │   ├── 01_create_sentinel_schema.sql   # 6 monitoring tables
│   │   ├── 02_create_sample_schema.sql     # 3 app tables (customers, orders, items)
│   │   ├── 03_create_monitoring_procs.sql  # sp_capture_health_snapshot
│   │   ├── 04_create_remediation_procs.sql # sp_kill_session, sp_cleanup_stale, sp_quarantine
│   │   └── 05_seed_sample_data.sql         # 100 customers, 500 orders, 1500 items
│   └── dmv/                   # DMV query files (read at runtime)
│       ├── active_queries.sql
│       ├── blocking_chains.sql
│       ├── connection_stats.sql
│       ├── cpu_pressure.sql
│       ├── memory_pressure.sql
│       ├── tempdb_usage.sql
│       └── wait_stats.sql
│
├── config/                    # YAML configuration (mounted into container)
│   ├── sentinel.yaml          # DB connection, thresholds, monitor settings
│   ├── jobs.yaml              # Scheduled jobs
│   ├── validation_rules.yaml  # Data quality rules
│   └── chaos_scenarios.yaml   # Chaos scenario definitions
│
├── tests/                     # Test suite
│   ├── conftest.py            # Shared fixtures + mock database
│   ├── unit/                  # Unit tests (no real DB needed)
│   └── integration/           # API tests (uses FastAPI TestClient)
│
├── docker-compose.yml         # Orchestrates all 3 services
├── Dockerfile                 # Builds the Python app image
├── Makefile                   # Convenience commands
├── pyproject.toml             # Python project config
├── .env.example               # Template for secrets
└── .gitignore                 # Keeps secrets out of git
```

**Why this layout?** Each directory maps to one responsibility. If you want to add a new validation rule, you only touch `config/validation_rules.yaml`. If you want to add a new chaos scenario, you only touch `sentinel/chaos/scenarios.py`. This separation makes the codebase easy to navigate and extend.

---

## How Monitoring Works

**File:** `sentinel/monitor/health.py`

Every 10 seconds, the monitor loop (in `sentinel/api/main.py`) does this:

```
1. Call sp_capture_health_snapshot (stored procedure)
   ├── Reads CPU % from sys.dm_os_ring_buffers
   ├── Reads memory from sys.dm_os_sys_memory
   ├── Counts connections from sys.dm_exec_connections
   ├── Counts blocked queries from sys.dm_exec_requests
   ├── Counts long-running queries (>30s)
   ├── Reads TempDB usage from sys.dm_db_file_space_usage
   └── Reads average wait time from sys.dm_os_wait_stats

2. Save snapshot to health_snapshots table

3. Evaluate thresholds
   ├── CPU > 90%?      → Create CRITICAL incident
   ├── CPU > 70%?      → Create WARNING incident
   ├── Memory > 90%?   → Create CRITICAL incident
   ├── Blocking > 5?   → Create CRITICAL incident
   └── etc.

4. If any alerts fire → Create incidents (with deduplication)
5. If auto_remediate is on → Try to fix open incidents
6. Check for stale incidents → Escalate after 5 minutes
```

**Why every 10 seconds?** Fast enough to catch transient issues, slow enough to not overload the database. This interval is configurable in `config/sentinel.yaml`.

**Try it:**
```bash
# Get current health status
curl -s http://localhost:8000/api/health | python3 -m json.tool

# Get health history (last hour)
curl -s http://localhost:8000/api/health/history?hours=1 | python3 -m json.tool

# Manually capture a snapshot
curl -s -X POST http://localhost:8000/api/health/snapshot | python3 -m json.tool
```

---

## How Incidents Work

**File:** `sentinel/monitor/incident_manager.py`

An incident tracks a problem from detection to resolution. It follows a state machine:

```
DETECTED ──→ INVESTIGATING ──→ REMEDIATING ──→ RESOLVED
    │              │                │               │
    │              │                │               └──→ Postmortem generated
    │              │                │
    └──────────────┴────────────────┴──→ ESCALATED (if not fixed in 5 min)
```

### Deduplication

If the monitor detects "high CPU" every 10 seconds, you don't want 100 separate incidents. The `dedup_key` field prevents this:

```python
# First detection: creates incident with dedup_key="health_cpu"
state.incidents.create(
    incident_type="cpu",
    title="Critical: cpu = 100.0",
    dedup_key="health_cpu"
)

# Second detection: sees dedup_key already open → skips creation
# Log: "Dedup: incident already open for key=health_cpu (id=8)"
```

### Auto-Escalation

If an incident stays open for too long (default: 5 minutes), it's automatically escalated. This simulates what happens in real incident management — unresolved issues get bumped up to senior engineers.

### Postmortems

When an incident is resolved, a postmortem is automatically generated with:
- **Summary** — what happened
- **Root cause** — extracted from the incident description
- **Timeline** — when it was detected, acknowledged, and resolved
- **Remediation actions** — what auto-fixes were attempted

**Try it:**
```bash
# List all incidents
curl -s http://localhost:8000/api/incidents | python3 -m json.tool

# List only open incidents
curl -s http://localhost:8000/api/incidents/open | python3 -m json.tool

# Update an incident's status (replace 1 with actual incident ID)
curl -s -X PATCH http://localhost:8000/api/incidents/1 \
  -H 'Content-Type: application/json' \
  -d '{"status": "investigating"}' | python3 -m json.tool

# Resolve an incident
curl -s -X PATCH http://localhost:8000/api/incidents/1 \
  -H 'Content-Type: application/json' \
  -d '{"status": "resolved"}' | python3 -m json.tool

# View the auto-generated postmortem
curl -s http://localhost:8000/api/incidents/1/postmortem | python3 -m json.tool
```

---

## How Data Validation Works

**Files:** `sentinel/validation/rules.py`, `sentinel/validation/engine.py`

Data validation checks your database for quality issues. Think of it as automated unit tests for your data.

### 6 Rule Types

| Rule Type | What It Checks | Example |
|-----------|---------------|---------|
| **null_check** | Column has no NULL values | "Customer email must never be NULL" |
| **range_check** | Values fall within a range | "Order total between $0 and $100,000" |
| **referential** | Foreign keys point to real rows | "Every order references a valid customer" |
| **duplicate** | No unexpected duplicates | "Customer emails should be unique" |
| **freshness** | Data isn't stale | "Table updated within last 24 hours" |
| **custom_sql** | Any SQL query you write | "Orders with items should have positive totals" |

### How Rules Are Defined

Rules live in `config/validation_rules.yaml` — you never need to write Python code to add a new rule:

```yaml
rules:
  - name: "orders_total_positive"
    type: "range_check"
    table: "orders"
    column: "total_amount"
    severity: "warning"
    params:
      min: 0
      max: 100000
    description: "Order total should be between 0 and 100,000"
```

**Why YAML?** It makes validation rules dataset-agnostic. If you swap in a different database (say, a healthcare system instead of an e-commerce one), you just edit the YAML file. No Python changes needed.

### How It Executes

Each rule type generates a different SQL query under the hood:

```
null_check    → SELECT COUNT(*) FROM {table} WHERE {column} IS NULL
range_check   → SELECT COUNT(*) FROM {table} WHERE {column} < {min} OR {column} > {max}
referential   → SELECT t.{col} FROM {table} t LEFT JOIN {ref_table} r ON t.{col} = r.{ref_col} WHERE r.{ref_col} IS NULL
duplicate     → SELECT {col}, COUNT(*) as cnt FROM {table} GROUP BY {col} HAVING COUNT(*) > 1
custom_sql    → (your exact SQL)
```

**Try it:**
```bash
# Run all validation rules
curl -s -X POST http://localhost:8000/api/validation/run | python3 -m json.tool

# Get the scorecard (pass/fail summary)
curl -s http://localhost:8000/api/validation/scorecard | python3 -m json.tool
```

---

## How Chaos Engineering Works

**Files:** `sentinel/chaos/scenarios.py`, `sentinel/chaos/engine.py`

Chaos engineering means **breaking things on purpose** to test your monitoring and recovery. Netflix popularized this with "Chaos Monkey" — a tool that randomly kills production servers to ensure the system recovers gracefully.

### 6 Built-In Scenarios

| Scenario | What It Does | What It Tests |
|----------|-------------|---------------|
| **Long Running Query** | Runs `WAITFOR DELAY '00:00:45'` | Long query detection, timeout handling |
| **Deadlock** | Creates competing transactions | Deadlock detection and victim selection |
| **Data Corruption** | Inserts invalid data (negative totals, duplicates) | Validation engine catches the problems |
| **Orphaned Records** | Creates FK violations (order_item → non-existent order) | Referential integrity validation |
| **Job Failure** | Inserts a fake "failed" job record | Job monitoring and alerting |
| **Connection Flood** | Opens 20 simultaneous connections | Connection count thresholds |

### Cooldowns

Each scenario has a cooldown period to prevent accidental overuse:

```yaml
# config/chaos_scenarios.yaml
scenarios:
  - name: "Data Corruption"
    severity: "high"
    cooldown_seconds: 30    # Can't trigger again for 30 seconds
    enabled: true
```

**Try it:**
```bash
# List all available scenarios
curl -s http://localhost:8000/api/chaos | python3 -m json.tool

# Trigger a specific scenario
curl -s -X POST http://localhost:8000/api/chaos/trigger \
  -H 'Content-Type: application/json' \
  -d '{"scenario": "Data Corruption"}' | python3 -m json.tool

# Trigger a random scenario
curl -s -X POST http://localhost:8000/api/chaos/random | python3 -m json.tool

# Now run validation to see the damage
curl -s -X POST http://localhost:8000/api/validation/run | python3 -m json.tool
```

---

## How Auto-Remediation Works

**Files:** `sentinel/remediation/actions.py`, `sentinel/remediation/engine.py`

When Sentinel detects an incident, it tries to fix it automatically before escalating to a human.

### Pattern Matching

The remediation engine maps incident types to fix actions:

```
Incident Type          → Remediation Action
─────────────────────────────────────────────
blocking_chain         → kill_blocking_session (kills the root blocker)
stale_sessions         → cleanup_stale_sessions (kills idle connections)
job_failure            → restart_failed_job (re-runs the failed job)
data_corruption        → quarantine_bad_data (isolates corrupt rows)
```

### Built-In Actions

| Action | What It Does | SQL Used |
|--------|-------------|----------|
| `kill_blocking_session` | Kills the session causing blocks | `EXEC sp_kill_session @session_id` |
| `cleanup_stale_sessions` | Kills connections idle > 60 minutes | `EXEC sp_cleanup_stale_sessions @idle_minutes=60` |
| `restart_failed_job` | Re-runs a failed scheduled job | Uses the job runner |
| `quarantine_bad_data` | Marks corrupt rows with a flag column | `EXEC sp_quarantine_rows @table, @column, @value` |

### Escalation

If auto-remediation fails (or no pattern matches the incident type), the incident is escalated after the configured timeout (default: 5 minutes). In a real environment, this would page an on-call engineer.

---

## How Jobs Work

**File:** `sentinel/jobs/runner.py`

SQL Server Agent (Microsoft's built-in job scheduler) doesn't run on Linux Docker. So we built a Python-based scheduler that does the same thing.

### How Scheduling Works

Jobs are defined in `config/jobs.yaml` with cron-like syntax:

```yaml
jobs:
  - name: "stale_session_cleanup"
    schedule_cron: "*/5 * * * *"    # Every 5 minutes
    sql_inline: "EXEC sp_cleanup_stale_sessions @idle_minutes = 60"
    enabled: true
    timeout_seconds: 30
```

The runner supports two formats:
- **Standard cron:** `*/5 * * * *` (every 5 minutes), `0 * * * *` (every hour)
- **Simple interval:** `@every 30s`, `@every 5m`, `@every 1h`

### Job History

Every job execution is logged to the `job_runs` table with:
- Start/end timestamps
- Duration in milliseconds
- Rows affected
- Status (success/failed/timeout)
- Error message (if failed)

**Try it:**
```bash
# List all configured jobs
curl -s http://localhost:8000/api/jobs | python3 -m json.tool

# View job run history
curl -s http://localhost:8000/api/jobs/history | python3 -m json.tool

# Manually trigger a job
curl -s -X POST http://localhost:8000/api/jobs/trigger \
  -H 'Content-Type: application/json' \
  -d '{"job_name": "stale_session_cleanup"}' | python3 -m json.tool
```

---

## Using the API

The full API is documented at **http://localhost:8000/docs** (Swagger UI).

### Quick Reference

```bash
# ─── Health ───
GET  /api/health              # Overall system health
GET  /api/health/sql          # SQL Server version and connectivity
GET  /api/health/history      # Snapshot history (?hours=1)
POST /api/health/snapshot     # Capture snapshot now

# ─── Incidents ───
GET  /api/incidents           # List recent (?limit=20)
GET  /api/incidents/open      # List open incidents only
GET  /api/incidents/{id}      # Get single incident
POST /api/incidents           # Create incident manually
PATCH /api/incidents/{id}     # Update status (investigating, resolved, escalated)
POST /api/incidents/{id}/remediate   # Attempt auto-fix

# ─── Postmortems ───
GET  /api/incidents/{id}/postmortem  # Get postmortem for resolved incident
GET  /api/incidents/postmortems/recent  # List recent postmortems

# ─── Jobs ───
GET  /api/jobs                # List configured jobs
GET  /api/jobs/history        # Execution history (?job_name=X&limit=20)
POST /api/jobs/trigger        # Manually trigger a job

# ─── Validation ───
GET  /api/validation/scorecard  # Pass/fail summary
GET  /api/validation/results    # Detailed results (?limit=50)
POST /api/validation/run        # Run all rules now

# ─── Chaos ───
GET  /api/chaos               # List scenarios (with cooldown status)
POST /api/chaos/trigger       # Trigger specific: {"scenario": "Data Corruption"}
POST /api/chaos/random        # Trigger random scenario

# ─── Dashboard ───
GET  /api/dashboard           # Aggregated data for the dashboard UI
```

---

## Using the Dashboard

Open **http://localhost:8000** in your browser. The dashboard auto-refreshes every 5 seconds.

### Dashboard Layout

```
┌──────────────────────────────────────────────────────┐
│  HEALTH CARDS (top row)                              │
│  CPU % │ Memory │ Connections │ Blocking │ Long Qry  │
├──────────────────────┬───────────────────────────────┤
│  OPEN INCIDENTS      │  SCHEDULED JOBS               │
│  (click to expand)   │  (status + last run time)     │
├──────────────────────┼───────────────────────────────┤
│  DATA VALIDATION     │  CHAOS ENGINE                 │
│  (scorecard + rules) │  (trigger buttons)            │
├──────────────────────┴───────────────────────────────┤
│  POSTMORTEMS (resolved incidents with documentation) │
└──────────────────────────────────────────────────────┘
```

### Color Coding

- **Green** = healthy / passed / resolved
- **Yellow** = warning / investigating
- **Red** = critical / failed / detected

---

## Configuration Deep Dive

All behavior is controlled by 4 YAML files in the `config/` directory. You never need to edit Python code to change thresholds, rules, or scenarios.

### config/sentinel.yaml — Core Settings

```yaml
database:
  host: "${DB_HOST:sqlserver}"    # ${VAR:default} syntax — reads env var or uses default
  password: "${SA_PASSWORD}"      # No default — MUST be set in .env

thresholds:
  cpu_percent_warning: 70.0       # Fires "warning" alert
  cpu_percent_critical: 90.0      # Fires "critical" alert + creates incident
  memory_percent_warning: 75.0
  memory_percent_critical: 90.0
  blocking_chain_warning: 2       # 2 blocked queries = warning
  blocking_chain_critical: 5      # 5 blocked queries = critical
  connection_count_warning: 80
  connection_count_critical: 150

monitor:
  poll_interval_seconds: 10       # How often to check health
  auto_remediate: true            # Try to fix problems automatically
  escalation_timeout_seconds: 300 # Escalate if not fixed in 5 minutes
```

**Why environment variable substitution?** So the same YAML config works in development (localhost) and production (real server) without editing the file. Just change the environment variables.

### config/validation_rules.yaml — Data Quality Rules

To add a new rule, just append to the YAML:

```yaml
rules:
  - name: "my_new_rule"
    type: "null_check"          # One of: null_check, range_check, referential, duplicate, freshness, custom_sql
    table: "my_table"
    column: "my_column"
    severity: "critical"        # critical or warning
    description: "Human-readable explanation"
```

### config/jobs.yaml — Scheduled Tasks

```yaml
jobs:
  - name: "my_cleanup_job"
    schedule_cron: "0 */6 * * *"    # Every 6 hours
    sql_inline: "DELETE FROM logs WHERE created_at < DATEADD(DAY, -7, GETUTCDATE())"
    enabled: true
    timeout_seconds: 60
    description: "Purge logs older than 7 days"
```

### config/chaos_scenarios.yaml — Chaos Definitions

```yaml
scenarios:
  - name: "My Custom Chaos"
    severity: "medium"
    cooldown_seconds: 60
    enabled: true
```

> Note: Custom chaos scenarios also need a Python class in `sentinel/chaos/scenarios.py`. The YAML controls metadata (severity, cooldown), the Python class defines what SQL to run.

---

## Running Tests

Tests use **pytest** with an in-memory mock database (no SQL Server needed).

### Setup (one time)

```bash
pip install -e ".[dev]"
```

### Run All Tests

```bash
# With Makefile
make test

# Or directly
pytest tests/ -v --cov=sentinel --cov-report=term-missing
```

### What Gets Tested

| Test File | What It Tests |
|-----------|---------------|
| `test_config.py` | YAML loading, env var substitution, Pydantic validation |
| `test_validation_rules.py` | Each of the 6 rule types with pass/fail cases |
| `test_incident_manager.py` | Incident creation, dedup, status transitions, postmortems |
| `test_chaos_scenarios.py` | Scenario triggering, cooldowns, incident creation |
| `test_health.py` | Health snapshot collection, threshold evaluation |
| `test_jobs.py` | Cron parsing, job execution, history logging |
| `test_health_api.py` | HTTP endpoints via FastAPI TestClient |

### The Mock Database

Tests don't need a real SQL Server. The `MockConnectionManager` in `tests/conftest.py` stores data in-memory Python dicts and pattern-matches on SQL strings to simulate responses. This means tests are fast (< 2 seconds) and run anywhere.

---

## Common Tasks

### Full Demo Walkthrough

```bash
# 1. Start system
docker compose up -d

# 2. Wait for initialization (10-15 seconds)
sleep 15

# 3. Check health
curl -s http://localhost:8000/api/health | python3 -m json.tool

# 4. Inject chaos (corrupt data)
curl -s -X POST http://localhost:8000/api/chaos/trigger \
  -H 'Content-Type: application/json' \
  -d '{"scenario": "Data Corruption"}' | python3 -m json.tool

# 5. Run validation (detects corruption)
curl -s -X POST http://localhost:8000/api/validation/run | python3 -m json.tool

# 6. Check incidents created
curl -s http://localhost:8000/api/incidents/open | python3 -m json.tool

# 7. Resolve an incident (replace 1 with actual ID)
curl -s -X PATCH http://localhost:8000/api/incidents/1 \
  -H 'Content-Type: application/json' \
  -d '{"status": "resolved"}' | python3 -m json.tool

# 8. View the postmortem
curl -s http://localhost:8000/api/incidents/1/postmortem | python3 -m json.tool
```

### View Live Logs

```bash
# Follow sentinel app logs
make logs
# or: docker compose logs -f sentinel
```

### Connect to SQL Server Directly

```bash
# Open a sqlcmd shell inside the container
make shell-db
# or:
docker compose exec sqlserver /opt/mssql-tools18/bin/sqlcmd \
  -S localhost -U sa -P 'YourPassword' -d SentinelDB -C

# Example queries once inside:
SELECT TOP 5 * FROM health_snapshots ORDER BY id DESC;
SELECT * FROM incidents WHERE status = 'detected';
SELECT * FROM validation_results ORDER BY executed_at DESC;
```

### Reset Everything

```bash
# Destroy all data and rebuild from scratch
make reset
# or: docker compose down -v && docker compose up -d --build
```

### Stop the System

```bash
docker compose down    # Stops containers, keeps data
docker compose down -v # Stops containers AND deletes data
```

---

## Troubleshooting

### "Cannot connect to SQL Server"

The sentinel app waits up to 60 seconds for SQL Server to start. If it still can't connect:

```bash
# Check SQL Server is healthy
docker compose ps

# Check SQL Server logs
docker compose logs sqlserver | tail -20

# Verify password is set
cat .env | grep SA_PASSWORD
```

SQL Server requires passwords with: uppercase + lowercase + number + special character, minimum 8 characters.

### "Port 8000 is already in use"

Another service is using that port. Set a different one:

```bash
# In .env, add:
SENTINEL_PORT=8080

# Restart
docker compose down && docker compose up -d
```

### "Tables don't exist" or "Invalid object name"

The init-db container may have failed. Check its logs:

```bash
docker compose logs init-db
```

If you see errors, reset everything:

```bash
docker compose down -v
docker compose up -d --build
```

### Tests fail with "ModuleNotFoundError"

Install the package in development mode first:

```bash
pip install -e ".[dev]"
```

---

## Glossary

| Term | Definition |
|------|-----------|
| **DMV** | Dynamic Management View — built-in SQL Server system views showing real-time metrics |
| **Incident** | A tracked problem, from detection through resolution |
| **Postmortem** | Documentation of a resolved incident (what happened, root cause, timeline) |
| **Dedup** | Deduplication — preventing duplicate incidents for the same ongoing problem |
| **Escalation** | Bumping an unresolved incident to a higher priority (simulates paging an on-call engineer) |
| **Chaos Engineering** | Breaking things on purpose to test monitoring and recovery |
| **Remediation** | The fix applied to resolve an incident |
| **Scorecard** | Summary of validation rule results (pass rate, critical failures) |
| **pyodbc** | Python library for connecting to SQL Server via ODBC |
| **FastAPI** | Modern Python web framework for building REST APIs |
| **Pydantic** | Data validation library — ensures configs and API inputs are well-typed |
| **TempDB** | SQL Server's temporary database — used for sorts, joins, and temp tables |
| **Blocking chain** | When query A holds a lock, blocking query B, which blocks query C |
| **WAITFOR** | T-SQL command that pauses execution — used in chaos scenarios to simulate stuck queries |
| **Ring buffer** | Circular in-memory log SQL Server uses to store recent CPU/scheduler metrics |
| **CTE** | Common Table Expression — a SQL construct used for recursive queries (like walking blocking chains) |
| **sa** | System Administrator — the built-in SQL Server superuser account |
