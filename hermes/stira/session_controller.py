"""
SessionController — orchestrates the three enforcement skills for a single session.

Receives a HermesTaskSpec dict, validates it, starts the skills,
and streams events back via the EventEmitter.
"""

from __future__ import annotations

import logging
from typing import Optional

from stira.event_emitter import EventEmitter
from stira.skills.app_suppressor import AppSuppressor
from stira.skills.focus_killer import FocusKiller
from stira.skills.app_monitor import AppMonitor

logger = logging.getLogger(__name__)

SUPPORTED_SPEC_VERSION = "1.0"


class SessionController:
    """
    Manages a single focus session lifecycle.

    Parameters
    ----------
    task_spec:
        HermesTaskSpec dict — must have spec_version == "1.0".
    emitter:
        EventEmitter used to stream events back to the Stira UI.
    """

    def __init__(self, task_spec: dict, emitter: EventEmitter) -> None:
        spec_version = task_spec.get("spec_version")
        if spec_version != SUPPORTED_SPEC_VERSION:
            raise ValueError(
                f"Unsupported spec_version: {spec_version!r}. "
                f"Expected {SUPPORTED_SPEC_VERSION!r}."
            )

        self._task_spec = task_spec
        self._emitter = emitter

        self._suppressor: Optional[AppSuppressor] = None
        self._killer: Optional[FocusKiller] = None
        self._monitor: Optional[AppMonitor] = None

    # ------------------------------------------------------------------
    # Properties
    # ------------------------------------------------------------------

    @property
    def session_id(self) -> str:
        return self._task_spec["session_id"]

    @property
    def blocked_bundle_ids(self) -> list:
        return list(self._task_spec.get("blocked_bundle_ids", []))

    @property
    def enforcement_mode(self) -> str:
        return self._task_spec["enforcement_mode"]

    # ------------------------------------------------------------------
    # Lifecycle
    # ------------------------------------------------------------------

    def start(self) -> None:
        """Initialise and start all three enforcement skills, then emit session_started."""
        logger.info("Starting session %s", self.session_id)

        # FocusKiller is stateless — instantiated once
        self._killer = FocusKiller()

        def on_app_blocked(bundle_id: str) -> None:
            self._emitter.emit_app_blocked(self.session_id, bundle_id)
            # Kill focus on the blocked app
            pid = self._get_pid_for_bundle(bundle_id)
            if pid is not None:
                self._killer.kill_focus(pid)
                self._emitter.emit_focus_killed(self.session_id, bundle_id)

        def on_app_opened(bundle_id: str) -> None:
            self._emitter.emit_app_opened(self.session_id, bundle_id)

        self._suppressor = AppSuppressor(
            blocked_bundle_ids=self.blocked_bundle_ids,
            on_blocked=on_app_blocked,
        )
        self._monitor = AppMonitor(on_app_opened=on_app_opened)

        self._suppressor.start()
        self._monitor.start()

        self._emitter.emit_session_started(self.session_id)
        logger.info("Session %s started", self.session_id)

    def stop(self) -> None:
        """Gracefully stop all skills and emit session_ended."""
        logger.info("Stopping session %s", self.session_id)

        if self._suppressor is not None:
            try:
                self._suppressor.stop()
            except Exception as exc:
                logger.warning("Error stopping AppSuppressor: %s", exc)

        if self._monitor is not None:
            try:
                self._monitor.stop()
            except Exception as exc:
                logger.warning("Error stopping AppMonitor: %s", exc)

        self._emitter.emit_session_ended(self.session_id)
        logger.info("Session %s ended", self.session_id)

    # ------------------------------------------------------------------
    # Helpers
    # ------------------------------------------------------------------

    def _get_pid_for_bundle(self, bundle_id: str) -> Optional[int]:
        """
        Look up the PID of a running app by bundle ID.
        Returns None if pyobjc is unavailable or app not found.
        """
        try:
            import AppKit
            workspace = AppKit.NSWorkspace.sharedWorkspace()
            for app in workspace.runningApplications():
                if app.bundleIdentifier() == bundle_id:
                    return app.processIdentifier()
        except ImportError:
            pass
        except Exception as exc:
            logger.warning("Error looking up PID for %s: %s", bundle_id, exc)
        return None
