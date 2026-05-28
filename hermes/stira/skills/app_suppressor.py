"""
AppSuppressor — subscribes to NSWorkspace.didActivateApplicationNotification and
calls on_blocked(bundle_id) + triggers focus kill when a blocked app activates.

Gracefully degrades if pyobjc is not available.
"""

from __future__ import annotations

import logging
import threading
from typing import Callable, List

try:
    import AppKit
    import Cocoa
    import objc
    HAS_PYOBJC = True

    class _AppSuppressorObserver(Cocoa.NSObject):
        def initWithSuppressor_(self, suppressor):
            self = objc.super(_AppSuppressorObserver, self).init()
            if self is not None:
                self._suppressor = suppressor
            return self

        def appDidActivate_(self, notification):
            try:
                app_info = notification.userInfo()
                app = app_info.get(AppKit.NSWorkspaceApplicationKey)
                if app is not None:
                    bid = app.bundleIdentifier()
                    with self._suppressor._lock:
                        blocked = bid is not None and bid in self._suppressor.blocked_bundle_ids
                    if blocked:
                        self._suppressor._handle_blocked_activation(bid)
            except Exception as exc:
                import logging as _logging
                _logging.getLogger(__name__).warning("appDidActivate_ error: %s", exc)

except ImportError:
    HAS_PYOBJC = False

logger = logging.getLogger(__name__)


class AppSuppressor:
    """
    Watches for activation of blocked apps and calls on_blocked.

    Parameters
    ----------
    blocked_bundle_ids:
        List of bundle IDs to suppress (e.g. ["com.twitter.twitter"]).
    on_blocked:
        Callable invoked with (bundle_id: str) when a blocked app activates.
    """

    def __init__(
        self,
        blocked_bundle_ids: List[str],
        on_blocked: Callable[[str], None],
    ) -> None:
        self.blocked_bundle_ids = list(blocked_bundle_ids)
        self.on_blocked = on_blocked
        self._observer = None
        self._lock = threading.Lock()

    # ------------------------------------------------------------------
    # macOS layer (isolated for mockability)
    # ------------------------------------------------------------------

    def _subscribe_to_workspace_notifications(self) -> None:
        """Subscribe to NSWorkspace activation notifications. Requires pyobjc."""
        if not HAS_PYOBJC:
            logger.warning(
                "pyobjc not available — AppSuppressor running in no-op mode"
            )
            return

        workspace = AppKit.NSWorkspace.sharedWorkspace()
        notification_center = workspace.notificationCenter()

        notification_center.addObserver_selector_name_object_(
            self._objc_observer(),
            "appDidActivate:",
            AppKit.NSWorkspaceDidActivateApplicationNotification,
            None,
        )

    def _unsubscribe_from_workspace_notifications(self) -> None:
        """Unsubscribe from NSWorkspace notifications."""
        if not HAS_PYOBJC or self._observer is None:
            return
        workspace = AppKit.NSWorkspace.sharedWorkspace()
        workspace.notificationCenter().removeObserver_(self._observer)

    def _objc_observer(self):
        """Return an Objective-C observer object. Requires pyobjc."""
        observer = _AppSuppressorObserver.alloc().initWithSuppressor_(self)
        self._observer = observer
        return observer

    # ------------------------------------------------------------------
    # Internal callback
    # ------------------------------------------------------------------

    def _handle_blocked_activation(self, bundle_id: str) -> None:
        """Called when a blocked app activates."""
        logger.info("Blocked app activated: %s", bundle_id)
        self.on_blocked(bundle_id)

    # ------------------------------------------------------------------
    # Public interface
    # ------------------------------------------------------------------

    def start(self) -> None:
        """Begin monitoring for blocked app activations."""
        self._subscribe_to_workspace_notifications()

    def stop(self) -> None:
        """Stop monitoring."""
        self._unsubscribe_from_workspace_notifications()

    def unblock(self, bundle_id: str) -> None:
        """Remove bundle_id from the blocked set so it is no longer suppressed."""
        with self._lock:
            self.blocked_bundle_ids = [b for b in self.blocked_bundle_ids if b != bundle_id]
        logger.info("Unblocked app: %s", bundle_id)
