"""Job management API routes."""

from __future__ import annotations

from fastapi import APIRouter, Depends, HTTPException, Query

from sentinel.api.dependencies import AppState, get_state
from sentinel.api.schemas import JobInfoResponse, JobRunResponse, JobTrigger

router = APIRouter(prefix="/api/jobs", tags=["jobs"])


@router.get("", response_model=list[JobInfoResponse])
def list_jobs(state: AppState = Depends(get_state)):
    """List all configured jobs with schedule info."""
    return state.jobs.get_all_jobs()


@router.get("/history", response_model=list[dict])
def job_history(
    job_name: str | None = None,
    limit: int = Query(default=20, ge=1, le=100),
    state: AppState = Depends(get_state),
):
    """Get job run history."""
    return state.jobs.get_history(job_name=job_name, limit=limit)


@router.post("/trigger", response_model=JobRunResponse)
def trigger_job(body: JobTrigger, state: AppState = Depends(get_state)):
    """Manually trigger a job by name."""
    result = state.jobs.run_job(body.job_name)
    if "error" in result:
        raise HTTPException(status_code=404, detail=result["error"])
    return result
