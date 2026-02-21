"""Chaos engineering API routes."""

from __future__ import annotations

from fastapi import APIRouter, Depends, HTTPException

from sentinel.api.dependencies import AppState, get_state
from sentinel.api.schemas import ChaosResponse, ChaosScenarioResponse, ChaosTrigger

router = APIRouter(prefix="/api/chaos", tags=["chaos"])


@router.get("", response_model=list[ChaosScenarioResponse])
def list_scenarios(state: AppState = Depends(get_state)):
    """List all available chaos scenarios."""
    return state.chaos.list_scenarios()


@router.post("/trigger", response_model=ChaosResponse)
def trigger_scenario(body: ChaosTrigger, state: AppState = Depends(get_state)):
    """Trigger a specific chaos scenario."""
    result = state.chaos.trigger(body.scenario)
    if "error" in result and "Unknown scenario" in result["error"]:
        raise HTTPException(status_code=404, detail=result["error"])
    if "error" in result and "cooldown" in result["error"]:
        raise HTTPException(status_code=429, detail=result["error"])
    return result


@router.post("/random", response_model=ChaosResponse)
def trigger_random(state: AppState = Depends(get_state)):
    """Trigger a random chaos scenario."""
    return state.chaos.trigger_random()
