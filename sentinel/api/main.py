"""FastAPI application with lifespan — starts monitor loop + job runner."""

from __future__ import annotations

import asyncio
import logging
import os
from contextlib import asynccontextmanager

from fastapi import FastAPI
from fastapi.responses import FileResponse
from fastapi.staticfiles import StaticFiles

from sentinel.api.dependencies import get_state
from sentinel.api.routes import chaos, dashboard, governance, health, incidents, jobs, validation
from sentinel.core.logging import setup_logging

setup_logging()
logger = logging.getLogger(__name__)


async def _monitor_loop(state) -> None:
    """Background health monitoring + auto-remediation loop."""
    logger.info("Monitor loop started (interval=%ds)", state.config.monitor.poll_interval_seconds)
    while True:
        try:
            snapshot = state.health.collect_snapshot()
            alerts = snapshot.get("alerts", [])

            # Create incidents for critical alerts
            for alert in alerts:
                if alert["level"] == "critical":
                    state.incidents.create(
                        incident_type=alert["metric"],
                        title=(
                            f"Critical: {alert['metric']}"
                            f" = {alert['value']}"
                            f" (threshold: {alert['threshold']})"
                        ),
                        severity="critical",
                        dedup_key=f"health_{alert['metric']}",
                    )

            # Healthcare metrics check
            try:
                hc_metrics = state.healthcare.collect_metrics()
                hc_alerts = state.healthcare.evaluate_thresholds(hc_metrics)
                for alert in hc_alerts:
                    if alert["level"] == "critical":
                        state.incidents.create(
                            incident_type=alert["metric"],
                            title=(
                                f"Critical: {alert['metric']}"
                                f" = {alert['value']}"
                                f" (threshold: {alert['threshold']})"
                            ),
                            severity="critical",
                            dedup_key=f"healthcare_{alert['metric']}",
                        )
            except Exception:
                logger.warning("Healthcare metrics collection failed", exc_info=True)

            # Auto-remediate if enabled
            if state.config.monitor.auto_remediate:
                state.remediation.remediate_open_incidents()

            # Check for stale incidents to escalate
            state.incidents.check_escalations(state.config.monitor.escalation_timeout_seconds)

        except Exception:
            logger.critical("Monitor loop error", exc_info=True)

        await asyncio.sleep(state.config.monitor.poll_interval_seconds)


@asynccontextmanager
async def lifespan(app: FastAPI):
    """Start background tasks on startup, clean up on shutdown."""
    state = get_state()

    # Wait for SQL Server to be ready
    logger.info("Waiting for SQL Server...")
    for attempt in range(30):
        if state.db.test_connection():
            logger.info("SQL Server connected.")
            break
        logger.info("SQL Server not ready (attempt %d/30)...", attempt + 1)
        await asyncio.sleep(2)
    else:
        logger.error("Could not connect to SQL Server after 30 attempts")

    # Start background tasks
    monitor_task = asyncio.create_task(_monitor_loop(state))
    job_task = asyncio.create_task(state.jobs.run_loop())
    logger.info("Background tasks started.")

    yield

    # Shutdown
    state.jobs.stop()
    monitor_task.cancel()
    job_task.cancel()
    logger.info("Sentinel shutdown complete.")


app = FastAPI(
    title="SQL Server Sentinel",
    description="Production SQL Server monitoring, chaos engineering, and incident response",
    version="1.0.0",
    lifespan=lifespan,
)

# Register routes
app.include_router(health.router)
app.include_router(incidents.router)
app.include_router(jobs.router)
app.include_router(validation.router)
app.include_router(chaos.router)
app.include_router(dashboard.router)
app.include_router(governance.router)

# Static files
WEB_DIR = os.path.join(os.path.dirname(__file__), "..", "web")
STATIC_DIR = os.path.join(WEB_DIR, "static")
TEMPLATE_DIR = os.path.join(WEB_DIR, "templates")

if os.path.isdir(STATIC_DIR):
    app.mount("/static", StaticFiles(directory=STATIC_DIR), name="static")


@app.get("/", include_in_schema=False)
def serve_dashboard():
    """Serve the dashboard HTML."""
    index_path = os.path.join(TEMPLATE_DIR, "index.html")
    if os.path.exists(index_path):
        return FileResponse(index_path)
    return {"message": "SQL Server Sentinel API", "docs": "/docs"}
