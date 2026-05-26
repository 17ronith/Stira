"""
EventEmitter — writes newline-delimited JSON HermesEvent objects to a writer.

stdlib only. The writer can be any file-like object (socket file, StringIO, etc.).
Each event includes: type, session_id, timestamp (ISO 8601 UTC), plus type-specific fields.
"""

from __future__ import annotations

import json
import logging
import threading
from datetime import datetime, timezone
from typing import IO

logger = logging.getLogger(__name__)


def _now_iso() -> str:
    """Return current UTC time as ISO 8601 string with timezone marker."""
    return datetime.now(tz=timezone.utc).isoformat()


class EventEmitter:
    """Writes HermesEvent JSON lines to an underlying writer."""

    def __init__(self, writer: IO[str]) -> None:
        self._writer = writer
        self._lock = threading.Lock()

    def _emit(self, event: dict) -> None:
        """Serialise event to JSON and write with a trailing newline."""
        line = json.dumps(event) + "\n"
        with self._lock:
            try:
                self._writer.write(line)
                if hasattr(self._writer, "flush"):
                    self._writer.flush()
            except (BrokenPipeError, OSError) as e:
                logging.warning("EventEmitter: write failed: %s", e)

    def emit_session_started(self, session_id: str) -> None:
        self._emit({
            "type": "session_started",
            "session_id": session_id,
            "timestamp": _now_iso(),
        })

    def emit_app_blocked(self, session_id: str, bundle_id: str) -> None:
        self._emit({
            "type": "app_blocked",
            "session_id": session_id,
            "bundle_id": bundle_id,
            "timestamp": _now_iso(),
        })

    def emit_focus_killed(self, session_id: str, bundle_id: str) -> None:
        self._emit({
            "type": "focus_killed",
            "session_id": session_id,
            "bundle_id": bundle_id,
            "timestamp": _now_iso(),
        })

    def emit_app_opened(self, session_id: str, bundle_id: str) -> None:
        self._emit({
            "type": "app_opened",
            "session_id": session_id,
            "bundle_id": bundle_id,
            "timestamp": _now_iso(),
        })

    def emit_session_ended(self, session_id: str) -> None:
        self._emit({
            "type": "session_ended",
            "session_id": session_id,
            "timestamp": _now_iso(),
        })

    def emit_error(self, session_id: str, message: str) -> None:
        self._emit({
            "type": "error",
            "session_id": session_id,
            "message": message,
            "timestamp": _now_iso(),
        })
