"""Built-in remediation actions."""

from __future__ import annotations

import logging
from typing import Any

from sentinel.core.exceptions import DatabaseQueryError
from sentinel.db.connection import ConnectionManager

logger = logging.getLogger(__name__)


def kill_blocking_session(db: ConnectionManager, session_id: int, **kwargs) -> dict[str, Any]:
    """Kill a specific session that's blocking others."""
    try:
        db.execute_proc("sp_kill_session", (session_id,))
        return {"success": True, "detail": f"Killed session {session_id}"}
    except DatabaseQueryError as e:
        return {"success": False, "detail": f"Failed to kill session {session_id}: {e}"}


def cleanup_stale_sessions(
    db: ConnectionManager, idle_minutes: int = 60, **kwargs
) -> dict[str, Any]:
    """Clean up sessions idle for more than N minutes."""
    try:
        rows = db.execute_proc("sp_cleanup_stale_sessions", (idle_minutes,))
        killed = rows[0].get("sessions_killed", 0) if rows else 0
        return {"success": True, "detail": f"Cleaned up {killed} stale sessions"}
    except DatabaseQueryError as e:
        return {"success": False, "detail": f"Stale session cleanup failed: {e}"}


def restart_failed_job(db: ConnectionManager, job_name: str, **kwargs) -> dict[str, Any]:
    """Mark a failed job for re-execution (runner picks it up on next cycle)."""
    try:
        db.execute_nonquery(
            "UPDATE job_runs SET status = 'pending_retry', error_message = "
            "CONCAT(ISNULL(error_message, ''), ' | Remediation: retry scheduled') "
            "WHERE job_name = ? AND status = 'failed' "
            "AND id = (SELECT MAX(id) FROM job_runs WHERE job_name = ? AND status = 'failed')",
            (job_name, job_name),
        )
        return {"success": True, "detail": f"Job '{job_name}' marked for retry"}
    except DatabaseQueryError as e:
        return {"success": False, "detail": f"Failed to restart job '{job_name}': {e}"}


def quarantine_bad_data(
    db: ConnectionManager, table: str, column: str, value: str, **kwargs
) -> dict[str, Any]:
    """Move bad rows to a quarantine table using parameterized column=value match."""
    try:
        rows = db.execute_proc("sp_quarantine_rows", (table, column, value))
        count = rows[0].get("rows_quarantined", 0) if rows else 0
        return {"success": True, "detail": f"Quarantined {count} rows from {table}"}
    except DatabaseQueryError as e:
        return {"success": False, "detail": f"Quarantine failed for {table}: {e}"}


ACTIONS: dict[str, Any] = {
    "kill_blocking_session": kill_blocking_session,
    "cleanup_stale_sessions": cleanup_stale_sessions,
    "restart_failed_job": restart_failed_job,
    "quarantine_bad_data": quarantine_bad_data,
}
