"""pyodbc connection manager for SQL Server."""

from __future__ import annotations

import logging
from contextlib import contextmanager
from typing import Any

import pyodbc

from sentinel.config.models import DatabaseConfig
from sentinel.core.exceptions import DatabaseConnectionError, DatabaseQueryError

logger = logging.getLogger(__name__)


class ConnectionManager:
    """Manages pyodbc connections to SQL Server."""

    def __init__(self, config: DatabaseConfig):
        self.config = config
        self._conn_str = self._build_connection_string()

    def _build_connection_string(self) -> str:
        parts = [
            f"DRIVER={{{self.config.driver}}}",
            f"SERVER={self.config.host},{self.config.port}",
            f"DATABASE={self.config.name}",
            f"UID={self.config.user}",
            f"PWD={self.config.password}",
            f"Connect Timeout={self.config.connect_timeout}",
        ]
        if self.config.trust_cert:
            parts.append("TrustServerCertificate=yes")
        return ";".join(parts)

    def get_connection(self) -> pyodbc.Connection:
        """Create and return a new database connection."""
        try:
            conn = pyodbc.connect(self._conn_str, timeout=self.config.connect_timeout)
            conn.timeout = self.config.query_timeout
            return conn
        except pyodbc.OperationalError as e:
            raise DatabaseConnectionError(f"Cannot connect to SQL Server: {e}") from e
        except pyodbc.Error as e:
            raise DatabaseConnectionError(f"Connection error: {e}") from e

    @contextmanager
    def cursor(self):
        """Context manager yielding a cursor that auto-commits and closes."""
        conn = self.get_connection()
        try:
            cur = conn.cursor()
            yield cur
            conn.commit()
        except pyodbc.OperationalError as e:
            conn.rollback()
            raise DatabaseQueryError(f"Query failed: {e}") from e
        except pyodbc.Error as e:
            conn.rollback()
            raise DatabaseQueryError(str(e)) from e
        finally:
            conn.close()

    def execute_query(self, sql: str, params: tuple = ()) -> list[dict[str, Any]]:
        """Execute a SELECT query and return rows as list of dicts."""
        with self.cursor() as cur:
            cur.execute(sql, params)
            columns = [desc[0] for desc in cur.description] if cur.description else []
            return [dict(zip(columns, row)) for row in cur.fetchall()]

    def execute_nonquery(self, sql: str, params: tuple = ()) -> int:
        """Execute an INSERT/UPDATE/DELETE and return rows affected."""
        with self.cursor() as cur:
            cur.execute(sql, params)
            return cur.rowcount

    def execute_proc(self, proc_name: str, params: tuple = ()) -> list[dict[str, Any]]:
        """Execute a stored procedure and return results."""
        import re

        if not re.match(r"^[\w.]+$", proc_name):
            raise ValueError(f"Invalid procedure name: {proc_name}")
        placeholders = ", ".join(["?"] * len(params))
        sql = f"EXEC {proc_name} {placeholders}" if params else f"EXEC {proc_name}"
        return self.execute_query(sql, params)

    def test_connection(self) -> bool:
        """Test if the database is reachable."""
        try:
            rows = self.execute_query("SELECT 1 AS ok")
            return len(rows) > 0 and rows[0].get("ok") == 1
        except (DatabaseConnectionError, DatabaseQueryError, pyodbc.Error) as e:
            logger.error("Connection test failed: %s", e)
            return False
