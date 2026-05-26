"""
FocusKiller — switches focus away from a given PID to Finder or the
front-most non-blocked app.

Gracefully degrades if pyobjc is not available.
"""

from __future__ import annotations

import logging

try:
    import AppKit
    HAS_PYOBJC = True
except ImportError:
    HAS_PYOBJC = False

logger = logging.getLogger(__name__)

FINDER_BUNDLE_ID = "com.apple.finder"


class FocusKiller:
    """
    Kills focus on a given PID by activating Finder (or another safe app).
    """

    def __init__(self) -> None:
        pass

    # ------------------------------------------------------------------
    # macOS layer (isolated for mockability)
    # ------------------------------------------------------------------

    def _activate_finder(self) -> None:
        """Bring Finder to front using NSWorkspace."""
        if not HAS_PYOBJC:
            return
        workspace = AppKit.NSWorkspace.sharedWorkspace()
        running_apps = workspace.runningApplications()
        for app in running_apps:
            if app.bundleIdentifier() == FINDER_BUNDLE_ID:
                app.activateWithOptions_(AppKit.NSApplicationActivateIgnoringOtherApps)
                return
        # Fallback: launch Finder if not running
        workspace.launchApplication_("Finder")

    def _get_front_app_pid(self) -> int | None:
        """Return PID of frontmost application, or None."""
        if not HAS_PYOBJC:
            return None
        workspace = AppKit.NSWorkspace.sharedWorkspace()
        front_app = workspace.frontmostApplication()
        if front_app is not None:
            return front_app.processIdentifier()
        return None

    # ------------------------------------------------------------------
    # Public interface
    # ------------------------------------------------------------------

    def kill_focus(self, pid: int) -> None:
        """
        Switch focus away from the given PID.

        Activates Finder. If pyobjc is not available, logs a warning and no-ops.
        """
        if not HAS_PYOBJC:
            logger.warning(
                "pyobjc not available — FocusKiller.kill_focus() is a no-op (pid=%d)", pid
            )
            return
        logger.info("Killing focus on pid=%d", pid)
        self._activate_finder()
