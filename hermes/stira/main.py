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

try:
    import AppKit
    HAS_APPKIT = True
except ImportError:
    HAS_APPKIT = False

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

    # _state holds mutable references shared across connection and callback closures
    _state: dict = {"controller": None}

    def on_start_session(task_spec: dict, emitter: EventEmitter) -> None:
        active_controller = _state["controller"]
        if active_controller is not None:
            logger.warning("New session requested while session active — stopping old session")
            try:
                active_controller.stop()
            except Exception as exc:
                logger.warning("Error stopping old session: %s", exc)

        try:
            controller = SessionController(task_spec=task_spec, emitter=emitter)
            controller.start()
            _state["controller"] = controller
        except Exception as exc:
            logger.error("Failed to start session: %s", exc)
            emitter.emit_error(
                session_id=task_spec.get("session_id", "unknown"),
                message=str(exc),
            )

    def on_stop_session(session_id: str) -> None:
        ctrl = _state["controller"]
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
        _state["controller"] = None

    def on_unknown(message: dict) -> None:
        logger.warning("Unknown message type received: %r", message.get("type"))

    def on_apply_exception(bundle_id: str) -> None:
        ctrl = _state["controller"]
        if ctrl is not None:
            ctrl.apply_exception(bundle_id)
        else:
            logger.warning("apply_exception received but no active session")

    receiver = PolicyReceiver(socket_path=args.socket_path)
    receiver.on_start_session = on_start_session
    receiver.on_stop_session = on_stop_session
    receiver.on_unknown = on_unknown
    receiver.on_apply_exception = on_apply_exception

    # Override _serve_connection to wire a per-connection EventEmitter before
    # dispatching any messages.  The write end of the socket is opened as a
    # separate text file so JSON events are written back to the same client.
    # The emitter is created fresh per connection and passed directly into
    # on_start_session — no shared global state.
    _original_dispatch = receiver._dispatch

    def _serve_connection_with_emitter(conn) -> None:
        """Wrap the default serve loop, binding a fresh EventEmitter to this conn."""
        conn_writer = conn.makefile("w", encoding="utf-8")
        conn_emitter = EventEmitter(writer=conn_writer)

        def _dispatch_with_emitter(message: dict) -> None:
            msg_type = message.get("type")
            if msg_type == "start_session":
                task_spec = message.get("policy", {})
                on_start_session(task_spec, conn_emitter)
            else:
                _original_dispatch(message)

        receiver._dispatch = _dispatch_with_emitter
        try:
            # Read lines from the connection and dispatch each one
            with conn.makefile("r", encoding="utf-8") as f:
                for line in f:
                    receiver._handle_raw_line(line)
        except Exception as exc:
            logger.warning("Error serving connection: %s", exc)
        finally:
            receiver._dispatch = _original_dispatch
            try:
                conn_writer.close()
            except Exception:
                pass
            try:
                conn.close()
            except Exception:
                pass

    receiver._serve_connection = _serve_connection_with_emitter

    def _shutdown(reason: str) -> None:
        logger.info("%s — shutting down", reason)
        ctrl = _state.get("controller")
        if ctrl is not None:
            try:
                ctrl.stop()
            except Exception as exc:
                logger.warning("Error stopping session during shutdown: %s", exc)
        receiver.stop()
        # os._exit avoids raising SystemExit into Objective-C's NSRunLoop,
        # which would cause OC_PythonException crashes in PyObjC.
        os._exit(0)

    signal.signal(signal.SIGTERM, lambda s, f: _shutdown("SIGTERM received"))
    # SIGINT is sent to the whole process group when the user hits Ctrl+C in
    # the terminal running swift run. Without this handler, NSRunLoop swallows
    # the signal and Hermes keeps blocking apps as an orphan.
    signal.signal(signal.SIGINT, lambda s, f: _shutdown("SIGINT received"))

    # Watchdog: if Stira exits without sending a signal (crash, force-quit, etc.),
    # the parent PID changes to launchd. Detect this and exit cleanly so the
    # AppSuppressor doesn't keep blocking apps as an orphan process.
    _original_ppid = os.getppid()

    def _parent_watchdog() -> None:
        import time
        while True:
            time.sleep(2)
            if os.getppid() != _original_ppid:
                logger.info("Parent process died (ppid %d → %d) — exiting", _original_ppid, os.getppid())
                os._exit(0)

    import threading
    threading.Thread(target=_parent_watchdog, daemon=True, name="parent-watchdog").start()

    # Start the socket server (blocks in accept loop on background thread)
    receiver.start()

    logger.info("Hermes ready. Waiting for connections on %s", args.socket_path)

    # Block main thread so NSWorkspace notifications (app_suppressor, app_monitor) fire.
    # SIGTERM/SIGINT handlers and the parent watchdog handle all exit paths.
    # Fall back to signal.pause() when pyobjc is not available (CI / non-macOS).
    if HAS_APPKIT:
        AppKit.NSRunLoop.currentRunLoop().run()
    else:
        signal.pause()


if __name__ == "__main__":
    main()
