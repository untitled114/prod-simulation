"""Healthcare monitor — pharmacy claims, adherence, and formulary metrics."""

from __future__ import annotations

import logging
from typing import Any

from sentinel.config.models import ThresholdConfig
from sentinel.core.exceptions import DatabaseQueryError
from sentinel.db.connection import ConnectionManager

logger = logging.getLogger(__name__)


class HealthcareMonitor:
    """Monitors healthcare-specific metrics: claims, adherence, generic rates."""

    def __init__(self, db: ConnectionManager, thresholds: ThresholdConfig):
        self.db = db
        self.thresholds = thresholds
        self._latest_metrics: dict[str, Any] | None = None

    def collect_metrics(self) -> dict[str, Any]:
        """Collect healthcare metrics from pharmacy_claims and patient_adherence."""
        metrics: dict[str, Any] = {}

        # Pharmacy claims metrics
        try:
            rows = self.db.execute_query(
                "SELECT "
                "  COUNT(*) AS claims_today, "
                "  SUM(CASE WHEN claim_status = 'rejected' THEN 1 ELSE 0 END) "
                "    AS rejected_count, "
                "  CASE WHEN COUNT(*) > 0 "
                "    THEN ROUND(100.0 * SUM(CASE WHEN claim_status = 'rejected' "
                "      THEN 1 ELSE 0 END) / COUNT(*), 1) "
                "    ELSE 0 END AS rejection_rate, "
                "  SUM(CASE WHEN m.drug_class = 'generic' THEN 1 ELSE 0 END) "
                "    AS generic_count, "
                "  CASE WHEN COUNT(*) > 0 "
                "    THEN ROUND(100.0 * SUM(CASE WHEN m.drug_class = 'generic' "
                "      THEN 1 ELSE 0 END) / COUNT(*), 1) "
                "    ELSE 0 END AS generic_rate "
                "FROM pharmacy_claims pc "
                "LEFT JOIN medications m ON pc.medication_id = m.id "
                "WHERE pc.service_date = CAST(GETDATE() AS DATE)"
            )
            if rows:
                metrics.update(rows[0])
        except DatabaseQueryError as e:
            logger.warning("Failed to collect claim metrics: %s", e)
            metrics.update(
                {
                    "claims_today": 0,
                    "rejected_count": 0,
                    "rejection_rate": 0.0,
                    "generic_count": 0,
                    "generic_rate": 0.0,
                }
            )

        # Patient adherence metrics
        try:
            rows = self.db.execute_query(
                "SELECT "
                "  ROUND(AVG(pdc_ratio), 3) AS avg_pdc, "
                "  SUM(CASE WHEN pdc_ratio < 0.80 THEN 1 ELSE 0 END) "
                "    AS non_adherent_count, "
                "  COUNT(*) AS total_patients "
                "FROM patient_adherence"
            )
            if rows:
                metrics.update(rows[0])
        except DatabaseQueryError as e:
            logger.warning("Failed to collect adherence metrics: %s", e)
            metrics.update({"avg_pdc": 0.0, "non_adherent_count": 0, "total_patients": 0})

        self._latest_metrics = metrics
        return metrics

    def evaluate_thresholds(self, metrics: dict[str, Any]) -> list[dict[str, Any]]:
        """Evaluate healthcare metrics against configured thresholds."""
        alerts: list[dict[str, Any]] = []
        t = self.thresholds

        # Claim rejection rate
        rejection_rate = metrics.get("rejection_rate") or 0.0
        if rejection_rate >= t.claim_rejection_rate_critical:
            alerts.append(
                {
                    "metric": "claim_rejection_rate",
                    "level": "critical",
                    "value": rejection_rate,
                    "threshold": t.claim_rejection_rate_critical,
                }
            )
        elif rejection_rate >= t.claim_rejection_rate_warning:
            alerts.append(
                {
                    "metric": "claim_rejection_rate",
                    "level": "warning",
                    "value": rejection_rate,
                    "threshold": t.claim_rejection_rate_warning,
                }
            )

        # Generic dispensing rate (alert if BELOW threshold — low is bad)
        generic_rate = metrics.get("generic_rate") or 0.0
        claims_today = metrics.get("claims_today") or 0
        if claims_today > 0 and generic_rate < t.generic_dispensing_rate_warning:
            alerts.append(
                {
                    "metric": "generic_dispensing_rate",
                    "level": "warning",
                    "value": generic_rate,
                    "threshold": t.generic_dispensing_rate_warning,
                }
            )

        # PDC adherence (alert if below CMS Star threshold)
        avg_pdc = metrics.get("avg_pdc") or 0.0
        total_patients = metrics.get("total_patients") or 0
        if total_patients > 0 and avg_pdc < t.pdc_adherence_warning:
            alerts.append(
                {
                    "metric": "pdc_adherence",
                    "level": "warning",
                    "value": avg_pdc,
                    "threshold": t.pdc_adherence_warning,
                }
            )

        return alerts

    def get_latest_metrics(self) -> dict[str, Any] | None:
        """Return cached metrics from last collect_metrics() call."""
        return self._latest_metrics
