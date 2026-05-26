"""
AppMonitor — subscribes to NSWorkspace didActivateApplication and didLaunchApplication
notifications and calls on_app_opened(bundle_id) for each event.

Gracefully degrades if pyobjc is not available.
"""

from __future__ import annotations

import logging
from typing import Callable

try:
    import AppKit
    import Cocoa
    HAS_PYOBJC = True
except ImportError:
    HAS_PYOBJC = False

logger = logging.getLogger(__name__)


class AppMonitor:
    """
    Monitors app activations and launches, calling on_app_opened for each.

    Parameters
    ----------
    on_app_opened:
        Callable invoked with (bundle_id: str) when any app activates or launches.
    """

    def __init__(self, on_app_opened: Callable[[str], None]) -> None:
        self.on_app_opened = on_app_opened
        self._observer = None

    # ------------------------------------------------------------------
    # macOS layer (isolated for mockability)
    # ------------------------------------------------------------------

    def _subscribe_to_workspace_notifications(self) -> None:
        """Subscribe to NSWorkspace notifications. Requires pyobjc."""
        if not HAS_PYOBJC:
            logger.warning(
                "pyobjc not available — AppMonitor running in no-op mode"
            )
            return

        workspace = AppKit.NSWorkspace.sharedWorkspace()
        nc = workspace.notificationCenter()

        class _Observer(Cocoa.NSObject):
            def initWithMonitor_(self, monitor):
                self = Cocoa.NSObject.init(self)
                if self is not None:
                    self._monitor = monitor
                return self

            def appEvent_(self, notification):
                app_info = notification.userInfo()
                app = app_info.get(AppKit.NSWorkspaceApplicationKey)
                if app is not None:
                    bid = app.bundleIdentifier()
                    if bid:
                        self._monitor._handle_app_event(bid)

        observer = _Observer.alloc().initWithMonitor_(self)
        self._observer = observer

        for notif_name in [
            AppKit.NSWorkspaceDidActivateApplicationNotification,
            AppKit.NSWorkspaceDidLaunchApplicationNotification,
        ]:
            nc.addObserver_selector_name_object_(
                observer, "appEvent:", notif_name, None
            )

    def _unsubscribe_from_workspace_notifications(self) -> None:
        """Unsubscribe from all notifications."""
        if not HAS_PYOBJC or self._observer is None:
            return
        workspace = AppKit.NSWorkspace.sharedWorkspace()
        workspace.notificationCenter().removeObserver_(self._observer)
        self._observer = None

    # ------------------------------------------------------------------
    # Internal callback
    # ------------------------------------------------------------------

    def _handle_app_event(self, bundle_id: str) -> None:
        """Called when any app activates or launches."""
        logger.debug("App event: %s", bundle_id)
        self.on_app_opened(bundle_id)

    # ------------------------------------------------------------------
    # Public interface
    # ------------------------------------------------------------------

    def start(self) -> None:
        """Begin monitoring app activations and launches."""
        self._subscribe_to_workspace_notifications()

    def stop(self) -> None:
        """Stop monitoring."""
        self._unsubscribe_from_workspace_notifications()
