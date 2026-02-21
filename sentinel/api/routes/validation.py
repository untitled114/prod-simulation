"""Data validation API routes."""

from __future__ import annotations

from fastapi import APIRouter, Depends, Query

from sentinel.api.dependencies import AppState, get_state
from sentinel.api.schemas import Scorecard, ValidationRunResponse

router = APIRouter(prefix="/api/validation", tags=["validation"])


@router.get("/scorecard", response_model=Scorecard)
def get_scorecard(state: AppState = Depends(get_state)):
    """Get the latest validation scorecard."""
    return state.validation.get_scorecard()


@router.get("/results", response_model=list[dict])
def get_results(limit: int = Query(default=50, ge=1, le=500), state: AppState = Depends(get_state)):
    """Get recent validation results."""
    return state.validation.get_recent_results(limit=limit)


@router.post("/run", response_model=ValidationRunResponse)
def run_validation(state: AppState = Depends(get_state)):
    """Trigger a full validation run."""
    results = state.validation.run_all()
    passed = sum(1 for r in results if r.get("passed"))
    return {
        "total": len(results),
        "passed": passed,
        "failed": len(results) - passed,
        "results": results,
    }
