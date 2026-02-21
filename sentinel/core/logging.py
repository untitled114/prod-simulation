"""Structured JSON logging for production observability."""

from __future__ import annotations

import json
import logging
import os
import sys
from datetime import datetime, timezone


class JsonFormatter(logging.Formatter):
    """Formats log records as single-line JSON for log aggregators (ELK, Splunk, Datadog)."""

    def format(self, record: logging.LogRecord) -> str:
        log_entry = {
            "timestamp": datetime.fromtimestamp(record.created, tz=timezone.utc).isoformat(),
            "level": record.levelname,
            "logger": record.name,
            "message": record.getMessage(),
            "module": record.module,
            "function": record.funcName,
            "line": record.lineno,
        }
        if record.exc_info and record.exc_info[0] is not None:
            log_entry["exception"] = self.formatException(record.exc_info)
        return json.dumps(log_entry, default=str)


def setup_logging(
    level: str | None = None,
    json_output: bool | None = None,
) -> None:
    """Configure root logger with JSON or text format.

    Args:
        level: Log level name (DEBUG, INFO, WARNING, ERROR). Defaults to SENTINEL_LOG_LEVEL env var.
        json_output: If True, use JSON format. If None, reads SENTINEL_LOG_FORMAT env var
                     (``json`` or ``text``). Defaults to text.
    """
    if level is None:
        level = os.environ.get("SENTINEL_LOG_LEVEL", "INFO")
    if json_output is None:
        json_output = os.environ.get("SENTINEL_LOG_FORMAT", "text").lower() == "json"

    log_level = getattr(logging, level.upper(), logging.INFO)

    root = logging.getLogger()
    root.setLevel(log_level)

    # Remove existing handlers to avoid duplicates
    root.handlers.clear()

    handler = logging.StreamHandler(sys.stdout)
    handler.setLevel(log_level)

    if json_output:
        handler.setFormatter(JsonFormatter())
    else:
        handler.setFormatter(logging.Formatter("%(asctime)s [%(levelname)s] %(name)s: %(message)s"))

    root.addHandler(handler)
