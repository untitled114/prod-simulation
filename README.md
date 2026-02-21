# SQL Server Sentinel

[![CI](https://github.com/untitled114/sql-server-sentinel/actions/workflows/ci.yml/badge.svg)](https://github.com/untitled114/sql-server-sentinel/actions/workflows/ci.yml)

Production SQL Server monitoring, chaos engineering, and incident response system with a healthcare data domain (pharmacy claims, patient adherence, HIPAA-compliant governance).

Built to demonstrate SQL Server production support skills: DMV monitoring, healthcare ETL pipelines, data governance, performance optimization, data validation, blocking chain detection, auto-remediation, and incident postmortem generation.

```
┌─────────────────────────────────────────────────────────────────┐
│                     War Room Dashboard                         │
│  ┌─────────┐ ┌─────────┐ ┌─────────┐ ┌─────────┐ ┌─────────┐ │
│  │  CPU %   │ │ Memory  │ │  Conns  │ │Blocking │ │Long Qry │ │
│  └─────────┘ └─────────┘ └─────────┘ └─────────┘ └─────────┘ │
│  ┌──────────────────────┐ ┌──────────────────────┐             │
│  │   Open Incidents     │ │   Scheduled Jobs     │             │
│  │   ├ Blocking chain   │ │   ├ health_snapshot  │             │
│  │   └ High CPU         │ │   ├ session_cleanup  │             │
│  └──────────────────────┘ │   └ validation_run   │             │
│  ┌──────────────────────┐ └──────────────────────┘             │
│  │  Data Validation 90% │ ┌──────────────────────┐             │
│  │  ├ ✓ email not null  │ │   Chaos Engine       │             │
│  │  ├ ✓ FK integrity    │ │   ├ Long Query       │             │
│  │  └ ✗ range check     │ │   ├ Deadlock         │             │
│  └──────────────────────┘ │   └ Data Corruption  │             │
│  ┌─────────────────────────────────────────────────┐           │
│  │   Recent Postmortems                            │           │
│  └─────────────────────────────────────────────────┘           │
└─────────────────────────────────────────────────────────────────┘
```

## Quick Start

```bash
# Clone and start everything
git clone https://github.com/untitled114/sql-server-sentinel.git && cd sql-server-sentinel
cp .env.example .env        # Edit SA_PASSWORD before production use
docker compose up -d         # or: docker-compose up -d

# Open dashboard
open http://localhost:8000

# API docs (Swagger)
open http://localhost:8000/docs
```

One command. SQL Server starts, schema initializes, seed data loads, and Sentinel begins monitoring.

> **Port conflict?** Set `SENTINEL_PORT=8080` in `.env` to use a different host port.

## Architecture

Three-layer system:

| Layer | Purpose | Key Files |
|-------|---------|-----------|
| **Chaos Engine** | Simulates production problems | `sentinel/chaos/` |
| **Sentinel Monitor** | Watches DMVs, validates data, manages incidents | `sentinel/monitor/`, `sentinel/validation/` |
| **War Room Dashboard** | Real-time visibility + chaos controls | `sentinel/web/`, `sentinel/api/` |

### Tech Stack

- **SQL Server 2022** Developer Edition (Docker)
- **Python 3.12** with pyodbc, FastAPI, Pydantic v2
- **T-SQL** stored procedures + DMV queries
- **Vanilla HTML/CSS/JS** dark theme dashboard

## Features

### Health Monitoring
- Real-time DMV polling (CPU, memory, connections, blocking, tempdb)
- Configurable warning/critical thresholds
- Health snapshot history with trend data

### Blocking Chain Detection
- Recursive CTE walks `sys.dm_exec_requests` to map full blocking trees
- Identifies root blockers with session details and SQL text
- Auto-kills stale blocking sessions

### Data Validation Engine
- 6 rule types: null_check, range_check, referential, duplicate, freshness, custom_sql
- 24 validation rules (10 operational + 14 healthcare-specific)
- Config-driven via YAML — scorecard with pass/fail percentages and violation details

### Incident Lifecycle
- Full state machine: DETECTED → INVESTIGATING → REMEDIATING → RESOLVED / ESCALATED
- Deduplication by key to prevent alert storms
- Auto-escalation after configurable timeout
- Postmortem auto-generation on resolution

### Chaos Engineering (9 Scenarios)

| Scenario | What it does | Severity |
|----------|-------------|----------|
| Long Running Query | 45-second blocking WAITFOR | Medium |
| Deadlock | Competing transaction setup | High |
| Data Corruption | Injects invalid/NULL values | High |
| Orphaned Records | Breaks FK referential integrity | Medium |
| Job Failure | Simulates disk I/O timeout | Low |
| Connection Flood | Opens 20 concurrent connections | High |
| Claim Volume Spike | Bulk inserts ~200 pharmacy claims (mixed statuses) | High |
| PHI Exposure | 100 suspicious PHI access records (HIPAA audit event) | High |
| Formulary Change | Moves generics to tier 3 + prior auth required | Medium |

### Auto-Remediation
- Pattern-matches incidents to remediation actions
- Built-in actions: kill_blocking_session, cleanup_stale, restart_job, quarantine_data
- Escalates to manual if auto-fix fails

### Job Scheduler
- Python-based scheduler (SQL Agent doesn't run on Linux Docker)
- Cron-like scheduling with run history tracking
- Manual trigger via API

## Healthcare Data Domain

### Schema Design

**OLTP (3NF)** — 8 tables for pharmacy claims processing:

| Table | Purpose | Key Fields |
|-------|---------|-----------|
| `providers` | Physicians/prescribers | NPI, DEA number, specialty |
| `patients` | Health plan members | member_id, PHI fields (HIPAA) |
| `medications` | Drug master | NDC code, formulary tier, DEA schedule |
| `pharmacies` | Dispensing locations | NCPDP ID, chain, pharmacy type |
| `prescriptions` | Rx orders | ICD-10 diagnosis, DAW code, refills |
| `pharmacy_claims` | Claims (partitioned) | Monthly range partitioning, computed total_cost |
| `drug_interactions` | Interaction alerts | Severity levels, clinical effects |
| `prior_authorizations` | PA workflow | Status: pending → approved/denied |

**Star Schema** — dimensional model for analytics:

| Table | Type | Notes |
|-------|------|-------|
| `fact_pharmacy_claims` | Fact | Nonclustered columnstore index for analytic queries |
| `dim_patient` | SCD Type 2 | Tracks historical changes via HASHBYTES row_hash |
| `dim_medication` | Dimension | NDC, drug class, formulary tier |
| `dim_pharmacy` | Dimension | NCPDP, chain, pharmacy type |
| `dim_provider` | Dimension | NPI, specialty |
| `dim_date` | Dimension | Calendar + CVS fiscal calendar |
| `patient_adherence` | Aggregate | PDC ratio (CMS Star Rating metric) |

### ETL Pipelines

| Job | Schedule | Pattern | What It Does |
|-----|----------|---------|-------------|
| `sp_etl_claim_ingestion` | Every 15 min | Staging → Validate → Load | Multi-source claim ingestion with reject handling + lineage |
| `sp_etl_dim_patient_scd2` | 3 AM UTC | SCD Type 2 MERGE | HASHBYTES change detection, age band calculation |
| `sp_etl_patient_adherence` | 4 AM Mon | PDC Calculation | Proportion of Days Covered — CMS Star Rating metric |
| `sp_etl_pharmacy_fill_summary` | 1 AM UTC | MERGE Upsert | Daily pharmacy rollups with generic fill rate |
| `sp_etl_daily_order_summary` | 1 AM UTC | Extract + Aggregate | Rolls up orders into daily revenue metrics |
| `sp_etl_customer_health` | 2 AM UTC | MERGE (SCD Type 1) | Computes customer health scores (RFM-based) |
| `sp_etl_incident_metrics` | Hourly | Idempotent Rollup | Aggregates incident data for SLA reporting |

### Performance Optimization

- **Table partitioning:** `pharmacy_claims` partitioned by month (24 partitions, 2025-2026)
- **Columnstore index:** Nonclustered columnstore on `fact_pharmacy_claims` for analytic queries
- **Indexed view:** `vw_claims_by_drug_class` with SCHEMABINDING + clustered index
- **Statistics maintenance:** `sp_maintenance_update_statistics` with configurable sample percent
- **Partition monitoring:** `sp_maintenance_partition_info` shows row counts and space per partition

### Healthcare Monitoring

- Real-time pharmacy claims metrics (claims today, rejection rate, generic dispensing rate)
- Patient adherence tracking (PDC ratio vs CMS Star thresholds)
- Configurable healthcare-specific thresholds (rejection rate, generic rate, PDC)
- Auto-creates critical incidents when healthcare thresholds are breached
- Dashboard panel with 4 healthcare metric cards

### Data Governance

- **Data catalog** — Auto-scans INFORMATION_SCHEMA to register all tables and columns
- **PHI/PII classification** — Regex-based detection of protected health information (name, DOB, SSN, phone, email, address, member_id)
- **PHI masked export** — `POST /api/governance/mask-export` returns patient data with all PHI fields masked (SHA-256 hashed IDs, redacted addresses, partial names)
- **Masking rules** — Per-column masking policy (full_mask, partial_mask, hash)
- **ETL lineage** — Tracks pipeline executions: source → target, rows read/written/rejected
- **HIPAA audit trail** — `phi_access_log` for compliance reporting

### Healthcare Validation Rules (14)

| Category | Rules | Examples |
|----------|-------|---------|
| HIPAA/PHI | 3 | member_id not null, DOB not null, member_id unique |
| Format | 2 | NDC 11 digits, NPI 10 digits |
| Referential | 3 | prescription→patient, prescription→provider, claim→patient |
| Business | 3 | quantity 1-1000, days_supply 1-365, cost $0-$100K |
| Freshness | 1 | Claims within 48 hours |
| Quality | 2 | PDC ratio 0-1.0, controlled substance DEA required |

## API Endpoints

| Method | Endpoint | Description |
|--------|----------|-------------|
| GET | `/api/health` | System health status |
| GET | `/api/health/sql` | SQL Server connectivity |
| POST | `/api/health/snapshot` | Capture health snapshot |
| GET | `/api/incidents` | List recent incidents |
| POST | `/api/incidents` | Create incident |
| PATCH | `/api/incidents/{id}` | Update incident status |
| POST | `/api/incidents/{id}/remediate` | Auto-remediate |
| GET | `/api/jobs` | List scheduled jobs |
| POST | `/api/jobs/trigger` | Manual job trigger |
| GET | `/api/validation/scorecard` | Validation scorecard |
| POST | `/api/validation/run` | Run all validation rules |
| GET | `/api/chaos` | List chaos scenarios |
| POST | `/api/chaos/trigger` | Trigger specific scenario |
| POST | `/api/chaos/random` | Trigger random scenario |
| GET | `/api/incidents/metrics/sla` | SLA compliance metrics |
| GET | `/api/dashboard` | Aggregated dashboard data |
| GET | `/api/governance/catalog` | Browse data catalog |
| GET | `/api/governance/catalog/phi` | List PHI-classified columns |
| POST | `/api/governance/catalog/scan` | Trigger schema scan |
| POST | `/api/governance/mask-export` | Export patients with PHI masked |
| GET | `/api/governance/lineage` | View ETL lineage records |

## Configuration

All behavior is config-driven via YAML:

```
config/
├── sentinel.yaml          # DB connection, thresholds, monitor settings
├── jobs.yaml              # Scheduled job definitions (13 jobs)
├── validation_rules.yaml  # Data quality rules (24 rules)
└── chaos_scenarios.yaml   # Chaos scenario definitions
```

### Adding Validation Rules

```yaml
# config/validation_rules.yaml
rules:
  - name: "my_custom_check"
    type: "custom_sql"
    severity: "critical"
    params:
      sql: "SELECT COUNT(*) AS violation_count FROM my_table WHERE status = 'invalid'"
    description: "No rows should have invalid status"
```

### Adjusting Thresholds

```yaml
# config/sentinel.yaml
thresholds:
  cpu_percent_critical: 85.0
  blocking_chain_warning: 3
  connection_count_critical: 200
```

## Development

```bash
# Install dev dependencies
pip install -e ".[dev]"

# Run tests (149 tests, 82% coverage)
make test

# Format + lint
make fmt
make lint

# Reset everything (destroys data)
make reset
```

## Project Structure

```
sentinel/
├── api/           # FastAPI routes + Pydantic schemas
├── chaos/         # Chaos engine + 6 scenarios
├── config/        # Pydantic models + YAML loader
├── db/            # Connection manager + SQL loader
├── governance/    # Data catalog, PHI classification, lineage
├── jobs/          # Cron-based job scheduler
├── monitor/       # Health collector, blocker detector, incident manager
├── remediation/   # Auto-fix actions + engine
├── validation/    # 6 rule types + validation engine
└── web/           # Dark theme dashboard (HTML/CSS/JS)

sql/
├── init/          # Schema creation, ETL procs, seed data, masking procs (13 scripts)
└── dmv/           # DMV query files

config/            # YAML configuration files
tests/             # Unit + integration + stress tests
docs/              # Runbook, beginner's guide
```

### SLA Compliance

- **SLA targets:** Critical < 60 min resolution, Warning < 4 hrs
- **Metrics endpoint:** `GET /api/incidents/metrics/sla?hours=24`
- **Auto-remediation rate tracking:** What percentage resolved without human intervention
- **Breach alerting:** Count of incidents exceeding SLA targets

## Documentation

| Document | Purpose |
|----------|---------|
| [Beginner's Guide](docs/BEGINNERS_GUIDE.md) | Step-by-step walkthrough for new engineers |
| [On-Call Runbook](docs/RUNBOOK.md) | Incident response procedures, escalation matrix, SLA targets |

## Demo Walkthrough

1. **Start the system:** `docker compose up -d`
2. **Open dashboard:** http://localhost:8000 — health metrics appear
3. **Inject chaos:** Click "Random" in the Chaos Engine panel
4. **Watch detection:** Incident appears in the Open Incidents panel
5. **Auto-remediation:** Sentinel pattern-matches and auto-fixes
6. **Postmortem:** After resolution, postmortem appears in the bottom panel
7. **Run validation:** Click "Run Now" — scorecard shows data quality (24 rules)
8. **Check SLA metrics:** `curl http://localhost:8000/api/incidents/metrics/sla`
9. **Browse data catalog:** `curl http://localhost:8000/api/governance/catalog/phi`
10. **Explore API:** http://localhost:8000/docs — full Swagger UI
