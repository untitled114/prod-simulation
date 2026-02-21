"""Dashboard aggregation endpoint."""

from __future__ import annotations

from fastapi import APIRouter, Depends

from sentinel.api.dependencies import AppState, get_state
from sentinel.api.schemas import DashboardResponse

router = APIRouter(prefix="/api/dashboard", tags=["dashboard"])


@router.get("", response_model=DashboardResponse)
def get_dashboard(state: AppState = Depends(get_state)):
    """Aggregated dashboard data — one call for the entire UI."""
    latest_health = state.health.get_latest() or {}

    # Get incidents (open first, then recent)
    open_incidents = state.incidents.list_open()
    recent_incidents = state.incidents.list_recent(limit=10)

    # Jobs
    jobs = state.jobs.get_all_jobs()
    recent_runs = state.jobs.get_history(limit=10)

    # Validation scorecard
    scorecard = state.validation.get_scorecard()

    # Chaos scenarios
    scenarios = state.chaos.list_scenarios()

    # Postmortems
    postmortems = state.incidents.list_postmortems(limit=5)

    # Healthcare metrics
    healthcare_metrics = {}
    if hasattr(state, "healthcare"):
        healthcare_metrics = state.healthcare.get_latest_metrics() or {}

    return {
        "health": latest_health,
        "open_incidents": open_incidents,
        "recent_incidents": recent_incidents,
        "jobs": jobs,
        "recent_job_runs": recent_runs,
        "validation": scorecard,
        "chaos_scenarios": scenarios,
        "postmortems": postmortems,
        "healthcare": healthcare_metrics,
    }
