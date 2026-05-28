"""
PolicyReceiver — Unix domain socket server that receives newline-delimited JSON messages
from the Stira Swift UI and dispatches them to registered callbacks.

Socket path: ~/Library/Application Support/Stira/hermes.sock
stdlib only.
"""

from __future__ import annotations

import json
import logging
import os
import socket
import threading
from pathlib import Path
from typing import Callable, Optional

logger = logging.getLogger(__name__)

DEFAULT_SOCKET_PATH = os.path.expanduser(
    "~/Library/Application Support/Stira/hermes.sock"
)


class PolicyReceiver:
    """
    Listens on a Unix domain socket and dispatches incoming messages.

    Callbacks:
        on_start_session(task_spec: dict)
        on_stop_session(session_id: str)
        on_apply_exception(bundle_id: str)
        on_unknown(message: dict)
    """

    def __init__(self, socket_path: str = DEFAULT_SOCKET_PATH) -> None:
        self.socket_path = socket_path
        self._server_socket: Optional[socket.socket] = None
        self._thread: Optional[threading.Thread] = None
        self._running = False

        # Default no-op callbacks — callers replace these
        self.on_start_session: Callable[[dict], None] = lambda spec: None
        self.on_stop_session: Callable[[str], None] = lambda sid: None
        self.on_apply_exception: Callable[[str], None] = lambda bundle_id: None
        self.on_unknown: Callable[[dict], None] = lambda msg: None

    # ------------------------------------------------------------------
    # Message handling (public for testability)
    # ------------------------------------------------------------------

    def _handle_raw_line(self, line: str) -> None:
        """Parse a single raw line as JSON and dispatch. Silently ignores bad JSON."""
        line = line.strip()
        if not line:
            return
        try:
            message = json.loads(line)
        except json.JSONDecodeError:
            logger.warning("Malformed JSON line received, ignoring: %r", line)
            return
        self._dispatch(message)

    def _dispatch(self, message: dict) -> None:
        """Dispatch a parsed message dict to the appropriate callback."""
        msg_type = message.get("type")
        if msg_type == "start_session":
            task_spec = message.get("policy", {})
            self.on_start_session(task_spec)
        elif msg_type == "stop_session":
            session_id = message.get("session_id", "")
            self.on_stop_session(session_id)
        elif msg_type == "apply_exception":
            bundle_id = message.get("bundle_id", "")
            self.on_apply_exception(bundle_id)
        else:
            self.on_unknown(message)

    # ------------------------------------------------------------------
    # Socket server
    # ------------------------------------------------------------------

    def _ensure_socket_dir(self) -> None:
        """Create parent directory of socket path if it doesn't exist."""
        parent = Path(self.socket_path).parent
        parent.mkdir(parents=True, exist_ok=True)

    def _serve_connection(self, conn: socket.socket) -> None:
        """Handle a single client connection, reading newline-delimited JSON."""
        try:
            with conn.makefile("r", encoding="utf-8") as f:
                for line in f:
                    self._handle_raw_line(line)
        except Exception as exc:
            logger.warning("Error serving connection: %s", exc)

    def start(self) -> None:
        """Start the socket server in a background thread."""
        self._ensure_socket_dir()

        # Remove stale socket file
        try:
            os.unlink(self.socket_path)
        except FileNotFoundError:
            pass

        self._server_socket = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
        self._server_socket.bind(self.socket_path)
        self._server_socket.listen(1)
        self._running = True

        self._thread = threading.Thread(target=self._accept_loop, daemon=True)
        self._thread.start()
        logger.info("PolicyReceiver listening on %s", self.socket_path)

    def stop(self) -> None:
        """Stop the socket server."""
        self._running = False
        if self._server_socket:
            try:
                self._server_socket.close()
            except Exception:
                pass
        try:
            os.unlink(self.socket_path)
        except FileNotFoundError:
            pass

    def _accept_loop(self) -> None:
        """Accept connections until stopped."""
        while self._running:
            try:
                conn, _ = self._server_socket.accept()
                t = threading.Thread(
                    target=self._serve_connection, args=(conn,), daemon=True
                )
                t.start()
            except OSError:
                break
