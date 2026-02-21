"""Blocking chain detection via DMV recursive CTE."""

from __future__ import annotations

import logging
from typing import Any

from sentinel.core.exceptions import DatabaseQueryError
from sentinel.db.connection import ConnectionManager
from sentinel.db.queries import load_dmv

logger = logging.getLogger(__name__)


class BlockerDetector:
    """Detects blocking chains in SQL Server using sys.dm_exec_requests."""

    def __init__(self, db: ConnectionManager):
        self.db = db

    def detect(self) -> list[dict[str, Any]]:
        """Run blocking chain detection and return results."""
        try:
            sql = load_dmv("blocking_chains")
            return self.db.execute_query(sql)
        except DatabaseQueryError as e:
            logger.error("Blocking chain detection failed: %s", e)
            return []

    def get_root_blockers(self) -> list[dict[str, Any]]:
        """Get only the root blockers (chain_depth = 0)."""
        chains = self.detect()
        return [c for c in chains if c.get("chain_depth") == 0]

    def get_chain_summary(self) -> dict[str, Any]:
        """Get a summary of current blocking situation."""
        chains = self.detect()
        if not chains:
            return {"blocking": False, "chains": 0, "total_blocked": 0, "max_depth": 0}

        root_blockers = {c["root_blocker_id"] for c in chains}
        max_depth = max(c.get("chain_depth", 0) for c in chains)
        total_blocked = sum(1 for c in chains if c.get("chain_depth", 0) > 0)

        return {
            "blocking": True,
            "chains": len(root_blockers),
            "total_blocked": total_blocked,
            "max_depth": max_depth,
            "root_blockers": list(root_blockers),
            "details": chains,
        }
