"""Incident lifecycle management: detection, tracking, resolution, postmortem."""

from __future__ import annotations

import json
import logging
from typing import Any

from sentinel.core.exceptions import DatabaseQueryError
from sentinel.db.connection import ConnectionManager

logger = logging.getLogger(__name__)


class IncidentManager:
    """Manages the full incident lifecycle."""

    STATUSES = ("detected", "investigating", "remediating", "resolved", "escalated")

    def __init__(self, db: ConnectionManager):
        self.db = db

    def create(
        self,
        incident_type: str,
        title: str,
        severity: str = "warning",
        description: str | None = None,
        dedup_key: str | None = None,
        metadata: dict | None = None,
    ) -> dict[str, Any]:
        """Create a new incident (with dedup check)."""
        if dedup_key:
            existing = self._find_open_by_dedup(dedup_key)
            if existing:
                logger.info(
                    "Dedup: incident already open for key=%s (id=%d)", dedup_key, existing["id"]
                )
                return existing

        meta_json = json.dumps(metadata) if metadata else None
        rows = self.db.execute_query(
            "INSERT INTO incidents "
            "(incident_type, severity, title, description, dedup_key, metadata) "
            "OUTPUT INSERTED.* VALUES (?, ?, ?, ?, ?, ?)",
            (incident_type, severity, title, description, dedup_key, meta_json),
        )
        if not rows:
            # Fallback for environments where OUTPUT is not available (e.g., mocks)
            rows = self.db.execute_query("SELECT TOP 1 * FROM incidents ORDER BY id DESC")
        incident = (
            rows[0]
            if rows
            else {
                "id": 0,
                "incident_type": incident_type,
                "severity": severity,
                "status": "detected",
                "title": title,
            }
        )
        logger.info(
            "Incident created: id=%s type=%s severity=%s",
            incident.get("id"),
            incident_type,
            severity,
        )
        return incident

    def update_status(
        self, incident_id: int, new_status: str, resolved_by: str | None = None
    ) -> dict[str, Any]:
        """Transition an incident to a new status."""
        if new_status not in self.STATUSES:
            raise ValueError(f"Invalid status: {new_status}")

        updates = ["status = ?"]
        params: list[Any] = [new_status]

        if new_status == "investigating":
            updates.append("acknowledged_at = SYSUTCDATETIME()")
        elif new_status in ("resolved", "escalated"):
            updates.append("resolved_at = SYSUTCDATETIME()")
            if resolved_by:
                updates.append("resolved_by = ?")
                params.append(resolved_by)

        params.append(incident_id)
        sql = f"UPDATE incidents SET {', '.join(updates)} WHERE id = ?"
        self.db.execute_nonquery(sql, tuple(params))

        if new_status == "resolved":
            self._generate_postmortem(incident_id)

        return self.get(incident_id)

    def get(self, incident_id: int) -> dict[str, Any] | None:
        """Get a single incident by ID."""
        rows = self.db.execute_query("SELECT * FROM incidents WHERE id = ?", (incident_id,))
        return rows[0] if rows else None

    def list_open(self) -> list[dict[str, Any]]:
        """List all non-resolved incidents."""
        return self.db.execute_query(
            "SELECT * FROM incidents "
            "WHERE status NOT IN ('resolved', 'escalated') "
            "ORDER BY detected_at DESC"
        )

    def list_recent(self, limit: int = 20) -> list[dict[str, Any]]:
        """List recent incidents regardless of status."""
        return self.db.execute_query(
            "SELECT TOP (?) * FROM incidents ORDER BY detected_at DESC", (limit,)
        )

    def get_postmortem(self, incident_id: int) -> dict[str, Any] | None:
        """Get the postmortem for a resolved incident."""
        rows = self.db.execute_query(
            "SELECT * FROM postmortems WHERE incident_id = ?", (incident_id,)
        )
        return rows[0] if rows else None

    def list_postmortems(self, limit: int = 10) -> list[dict[str, Any]]:
        """List recent postmortems."""
        return self.db.execute_query(
            "SELECT TOP (?) p.*, i.title AS incident_title, i.incident_type, i.severity "
            "FROM postmortems p JOIN incidents i ON p.incident_id = i.id "
            "ORDER BY p.generated_at DESC",
            (limit,),
        )

    def check_escalations(self, timeout_seconds: int = 300) -> list[dict[str, Any]]:
        """Find incidents that should be escalated (open too long)."""
        rows = self.db.execute_query(
            "SELECT * FROM incidents "
            "WHERE status IN ('detected', 'investigating', 'remediating') "
            "AND DATEDIFF(SECOND, detected_at, SYSUTCDATETIME()) > ? "
            "ORDER BY detected_at",
            (timeout_seconds,),
        )
        escalated = []
        for row in rows:
            self.update_status(row["id"], "escalated")
            escalated.append(row)
            logger.warning(
                "Incident %d escalated: exceeded %ds timeout", row["id"], timeout_seconds
            )
        return escalated

    def _find_open_by_dedup(self, dedup_key: str) -> dict[str, Any] | None:
        rows = self.db.execute_query(
            "SELECT TOP 1 * FROM incidents "
            "WHERE dedup_key = ? AND status NOT IN ('resolved', 'escalated') "
            "ORDER BY id DESC",
            (dedup_key,),
        )
        return rows[0] if rows else None

    def _generate_postmortem(self, incident_id: int) -> None:
        """Auto-generate a postmortem for a resolved incident."""
        incident = self.get(incident_id)
        if not incident:
            return

        # Get remediation log
        remediations = self.db.execute_query(
            "SELECT * FROM remediation_log WHERE incident_id = ? ORDER BY executed_at",
            (incident_id,),
        )

        detected = incident.get("detected_at", "unknown")
        resolved = incident.get("resolved_at", "unknown")
        resolved_by = incident.get("resolved_by", "unknown")

        timeline = [
            {"time": str(detected), "event": f"Incident detected: {incident['title']}"},
        ]
        if incident.get("acknowledged_at"):
            timeline.append({"time": str(incident["acknowledged_at"]), "event": "Acknowledged"})
        for r in remediations:
            status = "succeeded" if r.get("success") else "failed"
            timeline.append(
                {
                    "time": str(r["executed_at"]),
                    "event": f"Remediation '{r['action_name']}' {status}",
                }
            )
        timeline.append({"time": str(resolved), "event": f"Resolved by {resolved_by}"})

        summary = (
            f"**{incident['incident_type']}** incident "
            f"({incident['severity']}) — {incident['title']}. "
            f"Detected at {detected}, resolved at {resolved} "
            f"by {resolved_by}. "
            f"{len(remediations)} remediation action(s) taken."
        )

        try:
            self.db.execute_nonquery(
                "INSERT INTO postmortems "
                "(incident_id, summary, root_cause, timeline, "
                "remediation, lessons_learned) VALUES (?, ?, ?, ?, ?, ?)",
                (
                    incident_id,
                    summary,
                    incident.get("description", "Investigation required"),
                    json.dumps(timeline),
                    json.dumps(
                        [
                            {"action": r["action_name"], "success": r.get("success")}
                            for r in remediations
                        ]
                    ),
                    "Auto-generated postmortem. Review and update root cause and lessons learned.",
                ),
            )
            logger.info("Postmortem generated for incident %d", incident_id)
        except DatabaseQueryError as e:
            logger.error("Failed to generate postmortem for incident %d: %s", incident_id, e)
