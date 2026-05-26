"""
Tests for socket protocol: policy_receiver deserialization and event_emitter serialization.

All tests use in-memory buffers — no real sockets required.
"""

from __future__ import annotations

import io
import json
from datetime import datetime, timezone
import pytest


# ---------------------------------------------------------------------------
# Fixtures
# ---------------------------------------------------------------------------

VALID_TASK_SPEC = {
    "spec_version": "1.0",
    "session_id": "test-session-123",
    "blocked_bundle_ids": ["com.twitter.twitter"],
    "allowed_bundle_ids": [],
    "enforcement_mode": "block_listed",
    "session_duration_seconds": 5400,
    "audit_level": "normal",
}

START_SESSION_MSG = json.dumps({
    "type": "start_session",
    "policy": VALID_TASK_SPEC,
}) + "\n"

STOP_SESSION_MSG = json.dumps({
    "type": "stop_session",
    "session_id": "test-session-123",
}) + "\n"

UNKNOWN_MSG = json.dumps({
    "type": "ping",
}) + "\n"

MALFORMED_MSG = b"this is not valid json\n"


# ---------------------------------------------------------------------------
# Helper: feed messages to PolicyReceiver via in-memory buffer
# ---------------------------------------------------------------------------

def _make_receiver():
    """Import PolicyReceiver and create with mocked socket path."""
    from stira.policy_receiver import PolicyReceiver
    return PolicyReceiver(socket_path="/tmp/test-hermes.sock")


# ---------------------------------------------------------------------------
# PolicyReceiver tests
# ---------------------------------------------------------------------------

class TestPolicyReceiverDeserialization:
    """Test that PolicyReceiver correctly deserialises incoming messages."""

    def test_start_session_dispatches_on_start_session_callback(self):
        """start_session message should call on_start_session with the parsed task_spec dict."""
        from stira.policy_receiver import PolicyReceiver

        received = []
        receiver = PolicyReceiver(socket_path="/tmp/test.sock")
        receiver.on_start_session = lambda spec: received.append(spec)

        msg = json.loads(START_SESSION_MSG.strip())
        receiver._dispatch(msg)

        assert len(received) == 1
        assert received[0]["session_id"] == "test-session-123"
        assert received[0]["spec_version"] == "1.0"
        assert received[0]["blocked_bundle_ids"] == ["com.twitter.twitter"]

    def test_start_session_policy_field_passed_as_task_spec(self):
        """The 'policy' field of start_session should be passed to on_start_session."""
        from stira.policy_receiver import PolicyReceiver

        received = []
        receiver = PolicyReceiver(socket_path="/tmp/test.sock")
        receiver.on_start_session = lambda spec: received.append(spec)

        msg = {"type": "start_session", "policy": VALID_TASK_SPEC}
        receiver._dispatch(msg)

        assert received[0] == VALID_TASK_SPEC

    def test_stop_session_dispatches_on_stop_session_with_session_id(self):
        """stop_session message should call on_stop_session with the session_id string."""
        from stira.policy_receiver import PolicyReceiver

        received = []
        receiver = PolicyReceiver(socket_path="/tmp/test.sock")
        receiver.on_stop_session = lambda sid: received.append(sid)

        msg = json.loads(STOP_SESSION_MSG.strip())
        receiver._dispatch(msg)

        assert len(received) == 1
        assert received[0] == "test-session-123"

    def test_unknown_message_type_calls_on_unknown(self):
        """An unrecognised message type should call on_unknown, not raise."""
        from stira.policy_receiver import PolicyReceiver

        received = []
        receiver = PolicyReceiver(socket_path="/tmp/test.sock")
        receiver.on_unknown = lambda msg: received.append(msg)

        msg = json.loads(UNKNOWN_MSG.strip())
        receiver._dispatch(msg)

        assert len(received) == 1
        assert received[0]["type"] == "ping"

    def test_unknown_message_type_does_not_raise(self):
        """Dispatching an unknown message type must never raise an exception."""
        from stira.policy_receiver import PolicyReceiver

        receiver = PolicyReceiver(socket_path="/tmp/test.sock")
        # no callback set — default should be no-op or callable
        msg = {"type": "completely_unknown"}
        # should not raise
        receiver._dispatch(msg)

    def test_malformed_json_is_handled_gracefully(self):
        """Malformed JSON line should not raise — should be silently skipped."""
        from stira.policy_receiver import PolicyReceiver

        receiver = PolicyReceiver(socket_path="/tmp/test.sock")
        # should not raise
        receiver._handle_raw_line("this is not valid json")

    def test_malformed_json_does_not_call_any_callback(self):
        """Malformed JSON should not trigger any callback."""
        from stira.policy_receiver import PolicyReceiver

        calls = []
        receiver = PolicyReceiver(socket_path="/tmp/test.sock")
        receiver.on_start_session = lambda spec: calls.append(("start", spec))
        receiver.on_stop_session = lambda sid: calls.append(("stop", sid))
        receiver.on_unknown = lambda msg: calls.append(("unknown", msg))

        receiver._handle_raw_line("not json at all {{{{")

        assert calls == []


# ---------------------------------------------------------------------------
# EventEmitter tests
# ---------------------------------------------------------------------------

class TestEventEmitterSerialization:
    """Test that EventEmitter serialises events correctly into newline-delimited JSON."""

    def _make_emitter_with_buffer(self):
        from stira.event_emitter import EventEmitter
        buf = io.StringIO()
        emitter = EventEmitter(writer=buf)
        return emitter, buf

    def _read_event(self, buf: io.StringIO) -> dict:
        """Read the single event written to the buffer."""
        buf.seek(0)
        line = buf.readline().strip()
        assert line, "No event was written to the buffer"
        return json.loads(line)

    def test_session_started_has_required_fields(self):
        """emit_session_started should write type, session_id, timestamp."""
        emitter, buf = self._make_emitter_with_buffer()
        emitter.emit_session_started("sess-1")

        event = self._read_event(buf)
        assert event["type"] == "session_started"
        assert event["session_id"] == "sess-1"
        assert "timestamp" in event

    def test_session_started_type_is_correct_string(self):
        """emit_session_started type field must be exactly 'session_started'."""
        emitter, buf = self._make_emitter_with_buffer()
        emitter.emit_session_started("sess-x")
        event = self._read_event(buf)
        assert event["type"] == "session_started"

    def test_app_blocked_has_bundle_id_field(self):
        """emit_app_blocked should write bundle_id field."""
        emitter, buf = self._make_emitter_with_buffer()
        emitter.emit_app_blocked("sess-1", "com.twitter.twitter")

        event = self._read_event(buf)
        assert event["type"] == "app_blocked"
        assert event["bundle_id"] == "com.twitter.twitter"
        assert event["session_id"] == "sess-1"

    def test_app_blocked_type_is_correct_string(self):
        """emit_app_blocked type field must be exactly 'app_blocked'."""
        emitter, buf = self._make_emitter_with_buffer()
        emitter.emit_app_blocked("sess-1", "com.example.app")
        event = self._read_event(buf)
        assert event["type"] == "app_blocked"

    def test_focus_killed_has_bundle_id_field(self):
        """emit_focus_killed should write bundle_id field."""
        emitter, buf = self._make_emitter_with_buffer()
        emitter.emit_focus_killed("sess-1", "com.facebook.facebook")

        event = self._read_event(buf)
        assert event["type"] == "focus_killed"
        assert event["bundle_id"] == "com.facebook.facebook"
        assert event["session_id"] == "sess-1"

    def test_focus_killed_type_is_correct_string(self):
        """emit_focus_killed type field must be exactly 'focus_killed'."""
        emitter, buf = self._make_emitter_with_buffer()
        emitter.emit_focus_killed("sess-1", "com.example.app")
        event = self._read_event(buf)
        assert event["type"] == "focus_killed"

    def test_app_opened_has_bundle_id_field(self):
        """emit_app_opened should write bundle_id field."""
        emitter, buf = self._make_emitter_with_buffer()
        emitter.emit_app_opened("sess-2", "com.apple.finder")

        event = self._read_event(buf)
        assert event["type"] == "app_opened"
        assert event["bundle_id"] == "com.apple.finder"
        assert event["session_id"] == "sess-2"

    def test_app_opened_type_is_correct_string(self):
        """emit_app_opened type field must be exactly 'app_opened'."""
        emitter, buf = self._make_emitter_with_buffer()
        emitter.emit_app_opened("sess-1", "com.example.app")
        event = self._read_event(buf)
        assert event["type"] == "app_opened"

    def test_session_ended_has_required_fields(self):
        """emit_session_ended should write type, session_id, timestamp."""
        emitter, buf = self._make_emitter_with_buffer()
        emitter.emit_session_ended("sess-3")

        event = self._read_event(buf)
        assert event["type"] == "session_ended"
        assert event["session_id"] == "sess-3"
        assert "timestamp" in event

    def test_session_ended_type_is_correct_string(self):
        """emit_session_ended type field must be exactly 'session_ended'."""
        emitter, buf = self._make_emitter_with_buffer()
        emitter.emit_session_ended("sess-x")
        event = self._read_event(buf)
        assert event["type"] == "session_ended"

    def test_error_has_message_field(self):
        """emit_error should write message field."""
        emitter, buf = self._make_emitter_with_buffer()
        emitter.emit_error("sess-4", "Something went wrong")

        event = self._read_event(buf)
        assert event["type"] == "error"
        assert event["message"] == "Something went wrong"
        assert event["session_id"] == "sess-4"

    def test_error_type_is_correct_string(self):
        """emit_error type field must be exactly 'error'."""
        emitter, buf = self._make_emitter_with_buffer()
        emitter.emit_error("sess-1", "err")
        event = self._read_event(buf)
        assert event["type"] == "error"

    def test_all_events_have_iso8601_timestamps(self):
        """Every event emitted must carry a valid ISO 8601 UTC timestamp."""
        from stira.event_emitter import EventEmitter

        emitters_and_calls = [
            ("emit_session_started", ["sess-1"]),
            ("emit_app_blocked", ["sess-1", "com.example"]),
            ("emit_focus_killed", ["sess-1", "com.example"]),
            ("emit_app_opened", ["sess-1", "com.example"]),
            ("emit_session_ended", ["sess-1"]),
            ("emit_error", ["sess-1", "err"]),
        ]

        for method_name, args in emitters_and_calls:
            buf = io.StringIO()
            emitter = EventEmitter(writer=buf)
            getattr(emitter, method_name)(*args)

            buf.seek(0)
            event = json.loads(buf.readline().strip())
            ts = event.get("timestamp")
            assert ts is not None, f"{method_name} missing timestamp"

            # Should parse as a valid datetime with timezone info
            parsed = datetime.fromisoformat(ts)
            assert parsed.tzinfo is not None, f"{method_name} timestamp has no timezone: {ts}"

    def test_events_are_newline_delimited(self):
        """Each emitted event must be terminated with a newline character."""
        from stira.event_emitter import EventEmitter
        buf = io.StringIO()
        emitter = EventEmitter(writer=buf)
        emitter.emit_session_started("sess-1")

        buf.seek(0)
        raw = buf.read()
        assert raw.endswith("\n"), f"Event not newline-terminated: {repr(raw)}"

    def test_multiple_events_each_on_own_line(self):
        """Two events emitted should result in two separate lines."""
        from stira.event_emitter import EventEmitter
        buf = io.StringIO()
        emitter = EventEmitter(writer=buf)
        emitter.emit_session_started("sess-1")
        emitter.emit_session_ended("sess-1")

        buf.seek(0)
        lines = [l.strip() for l in buf.readlines() if l.strip()]
        assert len(lines) == 2
        events = [json.loads(l) for l in lines]
        assert events[0]["type"] == "session_started"
        assert events[1]["type"] == "session_ended"
