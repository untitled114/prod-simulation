"""YAML config loader with environment variable substitution."""

from __future__ import annotations

import os
import re
from pathlib import Path

import yaml

from sentinel.config.models import SentinelConfig

_ENV_PATTERN = re.compile(r"\$\{(\w+)(?::([^}]*))?\}")

CONFIG_DIR = Path(__file__).resolve().parent.parent.parent / "config"


def _substitute_env_vars(value: str) -> str:
    """Replace ${VAR} or ${VAR:default} with environment variable values."""

    def replacer(match: re.Match) -> str:
        var_name = match.group(1)
        default = match.group(2)
        return os.environ.get(var_name, default if default is not None else match.group(0))

    return _ENV_PATTERN.sub(replacer, value)


def _walk_and_substitute(obj):
    """Recursively substitute env vars in all string values."""
    if isinstance(obj, str):
        return _substitute_env_vars(obj)
    if isinstance(obj, dict):
        return {k: _walk_and_substitute(v) for k, v in obj.items()}
    if isinstance(obj, list):
        return [_walk_and_substitute(item) for item in obj]
    return obj


def load_yaml(path: Path) -> dict:
    """Load a YAML file with env var substitution."""
    with open(path) as f:
        raw = yaml.safe_load(f) or {}
    return _walk_and_substitute(raw)


def load_config() -> SentinelConfig:
    """Load and merge all config files into a SentinelConfig."""
    merged: dict = {}

    sentinel_yaml = CONFIG_DIR / "sentinel.yaml"
    if sentinel_yaml.exists():
        merged.update(load_yaml(sentinel_yaml))

    jobs_yaml = CONFIG_DIR / "jobs.yaml"
    if jobs_yaml.exists():
        jobs_data = load_yaml(jobs_yaml)
        merged["jobs"] = jobs_data.get("jobs", [])

    rules_yaml = CONFIG_DIR / "validation_rules.yaml"
    if rules_yaml.exists():
        rules_data = load_yaml(rules_yaml)
        merged["validation_rules"] = rules_data.get("rules", [])

    chaos_yaml = CONFIG_DIR / "chaos_scenarios.yaml"
    if chaos_yaml.exists():
        chaos_data = load_yaml(chaos_yaml)
        merged["chaos_scenarios"] = chaos_data.get("scenarios", [])

    return SentinelConfig(**merged)
