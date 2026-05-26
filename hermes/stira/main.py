"""
main.py — Hermes entry point.

Usage:
    python -m stira.main [--socket-path PATH]

Logs to ~/Library/Application Support/Stira/hermes.log
Handles SIGTERM cleanly.
"""

from __future__ import annotations

import argparse
import logging
import os
import signal
import sys
from pathlib import Path

DEFAULT_SOCKET_PATH = os.path.expanduser(
    "~/Library/Application Support/Stira/hermes.sock"
)
DEFAULT_LOG_PATH = os.path.expanduser(
    "~/Library/Application Support/Stira/hermes.log"
)

# ---------------------------------------------------------------------------
# Logging setup
# ---------------------------------------------------------------------------

def _setup_logging(log_path: str) -> None:
    Path(log_path).parent.mkdir(parents=True, exist_ok=True)
    handlers = [
        logging.FileHandler(log_path, encoding="utf-8"),
        logging.StreamHandler(sys.stderr),
    ]
    logging.basicConfig(
        level=logging.INFO,
        format="%(asctime)s %(levelname)s %(name)s: %(message)s",
        handlers=handlers,
    )


# ---------------------------------------------------------------------------
# Entry point
# ---------------------------------------------------------------------------

def main() -> None:
    parser = argparse.ArgumentParser(description="Stira Hermes enforcement agent")
    parser.add_argument(
        "--socket-path",
        default=DEFAULT_SOCKET_PATH,
        help="Path to Unix domain socket",
    )
    parser.add_argument(
        "--log-path",
        default=DEFAULT_LOG_PATH,
        help="Path to log file",
    )
    args = parser.parse_args()

    _setup_logging(args.log_path)
    logger = logging.getLogger(__name__)
    logger.info("Hermes starting (socket=%s)", args.socket_path)

    from stira.event_emitter import EventEmitter
    from stira.policy_receiver import PolicyReceiver
    from stira.session_controller import SessionController

    active_controller: SessionController | None = None
    active_conn_writer = None

    # We use a list so the inner callbacks can rebind via reference
    _state: dict = {"controller": None}

    def _make_emitter_for_conn(conn_writer) -> EventEmitter:
        return EventEmitter(writer=conn_writer)

    # For simplicity at MVP, we emit events to stderr (same as logs) when no
    # active connection writer is tracked. The full bidirectional connection
    # is handled by the PolicyReceiver's connection loop.
    import io
    fallback_writer = sys.stderr

    emitter = EventEmitter(writer=fallback_writer)

    def on_start_session(task_spec: dict) -> None:
        nonlocal active_controller
        if active_controller is not None:
            logger.warning("New session requested while session active — stopping old session")
            try:
                active_controller.stop()
            except Exception as exc:
                logger.warning("Error stopping old session: %s", exc)

        try:
            controller = SessionController(task_spec=task_spec, emitter=emitter)
            controller.start()
            active_controller = controller
            _state["controller"] = controller
        except Exception as exc:
            logger.error("Failed to start session: %s", exc)
            emitter.emit_error(
                session_id=task_spec.get("session_id", "unknown"),
                message=str(exc),
            )

    def on_stop_session(session_id: str) -> None:
        nonlocal active_controller
        ctrl = active_controller
        if ctrl is None:
            logger.warning("stop_session received but no active session")
            return
        if ctrl.session_id != session_id:
            logger.warning(
                "stop_session session_id mismatch: expected %s, got %s",
                ctrl.session_id, session_id,
            )
        try:
            ctrl.stop()
        except Exception as exc:
            logger.error("Error stopping session: %s", exc)
        active_controller = None
        _state["controller"] = None

    def on_unknown(message: dict) -> None:
        logger.warning("Unknown message type received: %r", message.get("type"))

    receiver = PolicyReceiver(socket_path=args.socket_path)
    receiver.on_start_session = on_start_session
    receiver.on_stop_session = on_stop_session
    receiver.on_unknown = on_unknown

    # SIGTERM handler for clean shutdown
    def _handle_sigterm(signum, frame):
        logger.info("SIGTERM received — shutting down")
        ctrl = _state.get("controller")
        if ctrl is not None:
            try:
                ctrl.stop()
            except Exception as exc:
                logger.warning("Error stopping session on SIGTERM: %s", exc)
        receiver.stop()
        sys.exit(0)

    signal.signal(signal.SIGTERM, _handle_sigterm)

    # Start the socket server (blocks in accept loop on background thread)
    receiver.start()

    logger.info("Hermes ready. Waiting for connections on %s", args.socket_path)

    # Block main thread — SIGTERM or KeyboardInterrupt will exit
    try:
        signal.pause()
    except KeyboardInterrupt:
        logger.info("KeyboardInterrupt — shutting down")
        ctrl = _state.get("controller")
        if ctrl is not None:
            try:
                ctrl.stop()
            except Exception:
                pass
        receiver.stop()


if __name__ == "__main__":
    main()
