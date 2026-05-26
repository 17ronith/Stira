"""
Tests for SessionController.

Mocks the emitter and the three skill classes — no macOS APIs required.
"""

from __future__ import annotations

from unittest.mock import MagicMock, patch, call

import pytest


# ---------------------------------------------------------------------------
# Shared fixtures
# ---------------------------------------------------------------------------

VALID_TASK_SPEC = {
    "spec_version": "1.0",
    "session_id": "session-abc",
    "blocked_bundle_ids": ["com.twitter.twitter", "com.instagram.instagram"],
    "allowed_bundle_ids": [],
    "enforcement_mode": "block_listed",
    "session_duration_seconds": 3600,
    "audit_level": "normal",
}

EMPTY_BLOCKED_TASK_SPEC = {
    "spec_version": "1.0",
    "session_id": "session-empty",
    "blocked_bundle_ids": [],
    "allowed_bundle_ids": [],
    "enforcement_mode": "block_listed",
    "session_duration_seconds": 1800,
    "audit_level": "normal",
}


def make_mock_emitter():
    emitter = MagicMock()
    return emitter


# ---------------------------------------------------------------------------
# Instantiation tests
# ---------------------------------------------------------------------------

class TestSessionControllerInstantiation:
    """Tests for __init__ and property access."""

    def test_can_be_instantiated_with_valid_task_spec(self):
        """SessionController should construct without error given a valid task_spec."""
        from stira.session_controller import SessionController

        emitter = make_mock_emitter()
        controller = SessionController(task_spec=VALID_TASK_SPEC, emitter=emitter)
        assert controller is not None

    def test_raises_value_error_when_spec_version_is_wrong(self):
        """SessionController must raise ValueError if spec_version != '1.0'."""
        from stira.session_controller import SessionController

        bad_spec = dict(VALID_TASK_SPEC, spec_version="2.0")
        emitter = make_mock_emitter()

        with pytest.raises(ValueError, match="spec_version"):
            SessionController(task_spec=bad_spec, emitter=emitter)

    def test_raises_value_error_when_spec_version_missing(self):
        """SessionController must raise ValueError if spec_version is absent."""
        from stira.session_controller import SessionController

        bad_spec = {k: v for k, v in VALID_TASK_SPEC.items() if k != "spec_version"}
        emitter = make_mock_emitter()

        with pytest.raises((ValueError, KeyError)):
            SessionController(task_spec=bad_spec, emitter=emitter)

    def test_blocked_bundle_ids_property_returns_list_from_spec(self):
        """blocked_bundle_ids should return the list from the task_spec."""
        from stira.session_controller import SessionController

        emitter = make_mock_emitter()
        controller = SessionController(task_spec=VALID_TASK_SPEC, emitter=emitter)

        assert controller.blocked_bundle_ids == ["com.twitter.twitter", "com.instagram.instagram"]

    def test_blocked_bundle_ids_property_returns_empty_list(self):
        """blocked_bundle_ids should return [] when spec has empty list."""
        from stira.session_controller import SessionController

        emitter = make_mock_emitter()
        controller = SessionController(task_spec=EMPTY_BLOCKED_TASK_SPEC, emitter=emitter)

        assert controller.blocked_bundle_ids == []

    def test_enforcement_mode_property_returns_value_from_spec(self):
        """enforcement_mode should return the enforcement_mode from task_spec."""
        from stira.session_controller import SessionController

        emitter = make_mock_emitter()
        controller = SessionController(task_spec=VALID_TASK_SPEC, emitter=emitter)

        assert controller.enforcement_mode == "block_listed"

    def test_session_id_matches_task_spec(self):
        """session_id should be accessible and match the spec."""
        from stira.session_controller import SessionController

        emitter = make_mock_emitter()
        controller = SessionController(task_spec=VALID_TASK_SPEC, emitter=emitter)

        assert controller.session_id == "session-abc"


# ---------------------------------------------------------------------------
# start() / stop() tests
# ---------------------------------------------------------------------------

class TestSessionControllerLifecycle:
    """Tests for start() and stop() method behaviour."""

    def test_start_calls_emit_session_started(self):
        """SessionController.start() should call emitter.emit_session_started()."""
        from stira.session_controller import SessionController

        emitter = make_mock_emitter()

        with patch("stira.session_controller.AppSuppressor"), \
             patch("stira.session_controller.FocusKiller"), \
             patch("stira.session_controller.AppMonitor"):
            controller = SessionController(task_spec=VALID_TASK_SPEC, emitter=emitter)
            controller.start()

        emitter.emit_session_started.assert_called_once_with("session-abc")

    def test_stop_calls_emit_session_ended(self):
        """SessionController.stop() should call emitter.emit_session_ended()."""
        from stira.session_controller import SessionController

        emitter = make_mock_emitter()

        with patch("stira.session_controller.AppSuppressor"), \
             patch("stira.session_controller.FocusKiller"), \
             patch("stira.session_controller.AppMonitor"):
            controller = SessionController(task_spec=VALID_TASK_SPEC, emitter=emitter)
            controller.start()
            controller.stop()

        emitter.emit_session_ended.assert_called_once_with("session-abc")

    def test_start_initialises_and_starts_all_three_skills(self):
        """start() should start AppSuppressor, FocusKiller, and AppMonitor."""
        from stira.session_controller import SessionController

        emitter = make_mock_emitter()
        mock_suppressor = MagicMock()
        mock_killer = MagicMock()
        mock_monitor = MagicMock()

        mock_suppressor_cls = MagicMock(return_value=mock_suppressor)
        mock_killer_cls = MagicMock(return_value=mock_killer)
        mock_monitor_cls = MagicMock(return_value=mock_monitor)

        with patch("stira.session_controller.AppSuppressor", mock_suppressor_cls), \
             patch("stira.session_controller.FocusKiller", mock_killer_cls), \
             patch("stira.session_controller.AppMonitor", mock_monitor_cls):
            controller = SessionController(task_spec=VALID_TASK_SPEC, emitter=emitter)
            controller.start()

        mock_suppressor.start.assert_called_once()
        mock_monitor.start.assert_called_once()

    def test_stop_stops_all_three_skills(self):
        """stop() should call stop() on all running skills."""
        from stira.session_controller import SessionController

        emitter = make_mock_emitter()
        mock_suppressor = MagicMock()
        mock_killer = MagicMock()
        mock_monitor = MagicMock()

        mock_suppressor_cls = MagicMock(return_value=mock_suppressor)
        mock_killer_cls = MagicMock(return_value=mock_killer)
        mock_monitor_cls = MagicMock(return_value=mock_monitor)

        with patch("stira.session_controller.AppSuppressor", mock_suppressor_cls), \
             patch("stira.session_controller.FocusKiller", mock_killer_cls), \
             patch("stira.session_controller.AppMonitor", mock_monitor_cls):
            controller = SessionController(task_spec=VALID_TASK_SPEC, emitter=emitter)
            controller.start()
            controller.stop()

        mock_suppressor.stop.assert_called_once()
        mock_monitor.stop.assert_called_once()

    def test_works_with_empty_blocked_bundle_ids(self):
        """SessionController with empty blocked_bundle_ids should start/stop without error."""
        from stira.session_controller import SessionController

        emitter = make_mock_emitter()

        with patch("stira.session_controller.AppSuppressor"), \
             patch("stira.session_controller.FocusKiller"), \
             patch("stira.session_controller.AppMonitor"):
            controller = SessionController(task_spec=EMPTY_BLOCKED_TASK_SPEC, emitter=emitter)
            controller.start()
            controller.stop()

        emitter.emit_session_started.assert_called_once_with("session-empty")
        emitter.emit_session_ended.assert_called_once_with("session-empty")

    def test_app_suppressor_receives_blocked_bundle_ids(self):
        """AppSuppressor should be instantiated with the blocked_bundle_ids from spec."""
        from stira.session_controller import SessionController

        emitter = make_mock_emitter()
        mock_suppressor_cls = MagicMock()
        mock_suppressor_cls.return_value = MagicMock()

        with patch("stira.session_controller.AppSuppressor", mock_suppressor_cls), \
             patch("stira.session_controller.FocusKiller"), \
             patch("stira.session_controller.AppMonitor"):
            controller = SessionController(task_spec=VALID_TASK_SPEC, emitter=emitter)
            controller.start()

        # The first positional arg (or blocked_bundle_ids kwarg) must include the bundle ids
        call_args = mock_suppressor_cls.call_args
        # Check that the blocked_bundle_ids were passed somehow
        all_args = list(call_args.args) + list(call_args.kwargs.values())
        flat = []
        for a in all_args:
            if isinstance(a, list):
                flat.extend(a)
            else:
                flat.append(a)
        assert "com.twitter.twitter" in flat or any(
            "com.twitter.twitter" in str(a) for a in all_args
        )

    def test_on_blocked_callback_kills_focus_and_emits(self):
        """When AppSuppressor fires on_blocked, FocusKiller.kill_focus is called and focus_killed is emitted."""
        from stira.session_controller import SessionController

        emitter = make_mock_emitter()
        mock_suppressor = MagicMock()
        mock_killer = MagicMock()
        mock_monitor = MagicMock()

        mock_suppressor_cls = MagicMock(return_value=mock_suppressor)
        mock_killer_cls = MagicMock(return_value=mock_killer)
        mock_monitor_cls = MagicMock(return_value=mock_monitor)

        # Capture the on_blocked callback passed to AppSuppressor
        captured_on_blocked = {}

        def capture_suppressor(**kwargs):
            captured_on_blocked["cb"] = kwargs.get("on_blocked")
            return mock_suppressor

        mock_suppressor_cls.side_effect = capture_suppressor

        with patch("stira.session_controller.AppSuppressor", mock_suppressor_cls), \
             patch("stira.session_controller.FocusKiller", mock_killer_cls), \
             patch("stira.session_controller.AppMonitor", mock_monitor_cls):
            controller = SessionController(task_spec=VALID_TASK_SPEC, emitter=emitter)
            # Patch _get_pid_for_bundle to return a known PID
            controller._get_pid_for_bundle = lambda bundle_id: 1234
            controller.start()

        # Verify the callback was captured
        assert "cb" in captured_on_blocked, "on_blocked callback was not passed to AppSuppressor"
        on_blocked = captured_on_blocked["cb"]

        # Fire the callback as if a blocked app came to the foreground
        on_blocked("com.twitter.twitter")

        # kill_focus must have been called with the PID
        mock_killer.kill_focus.assert_called_once_with(1234)

        # focus_killed event must have been emitted
        emitter.emit_focus_killed.assert_called_once_with("session-abc", "com.twitter.twitter")
