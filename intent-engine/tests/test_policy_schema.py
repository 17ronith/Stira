import json
import pytest
from pathlib import Path
import jsonschema

SCHEMA_PATH = Path(__file__).parent.parent.parent / "docs" / "schema" / "stira-policy.schema.json"

VALID_POLICY = {
    "schema_version": "1.0",
    "session_id": "a1b2c3d4-e5f6-7890-abcd-ef1234567890",
    "intent": {
        "raw": "I need to finish my quarterly report",
        "normalised": "i need to finish my quarterly report",
        "confidence": 0.96
    },
    "session": {"duration_minutes": 90, "hard_stop": False},
    "apps": {
        "mode": "block_listed",
        "blocked": [{"bundle_id": "com.twitter.twitter", "display_name": "Twitter"}],
        "allowed": []
    },
    "urls": {
        "rules": [
            {"pattern": "twitter.com", "action": "block", "exceptions": [], "reason": "social media"}
        ]
    },
    "notifications": {"mode": "suppress_all"},
    "escape_hatch": {
        "mode": "standard",
        "delay_seconds": 30,
        "require_reason": True,
        "min_reason_chars": 20,
        "exception_scope": "scoped",
        "active_exceptions": []
    }
}

YOUTUBE_LECTURE_POLICY = {
    "schema_version": "1.0",
    "session_id": "b2c3d4e5-f6a7-8901-bcde-f12345678901",
    "intent": {
        "raw": "Watching lecture videos on distributed systems",
        "normalised": "watching lecture videos on distributed systems",
        "confidence": 0.89
    },
    "session": {"duration_minutes": 120, "hard_stop": False},
    "apps": {
        "mode": "block_listed",
        "blocked": [{"bundle_id": "com.tinyspeck.slackmacgap", "display_name": "Slack"}],
        "allowed": []
    },
    "urls": {
        "rules": [
            {
                "pattern": "youtube.com",
                "action": "block",
                "exceptions": [
                    {"pattern": "youtube.com/watch", "reason": "lecture videos"},
                    {"pattern": "youtube.com/playlist", "reason": "lecture playlists"}
                ],
                "reason": "youtube feed is distracting but watch/playlist needed for lectures"
            }
        ]
    },
    "notifications": {"mode": "allow_calendar"},
    "escape_hatch": {
        "mode": "standard",
        "delay_seconds": 30,
        "require_reason": True,
        "min_reason_chars": 20,
        "exception_scope": "scoped",
        "active_exceptions": []
    }
}

ALLOW_LISTED_POLICY = {
    "schema_version": "1.0",
    "session_id": "c3d4e5f6-a7b8-9012-cdef-123456789012",
    "intent": {
        "raw": "Deep work: coding on my side project, no interruptions",
        "normalised": "deep work: coding on my side project, no interruptions",
        "confidence": 0.98
    },
    "session": {"duration_minutes": 180, "hard_stop": False},
    "apps": {
        "mode": "allow_listed",
        "blocked": [],
        "allowed": [
            {"bundle_id": "com.microsoft.VSCode", "display_name": "VS Code"},
            {"bundle_id": "com.apple.Terminal", "display_name": "Terminal"}
        ]
    },
    "urls": {
        "rules": [
            {"pattern": "twitter.com", "action": "block", "exceptions": [], "reason": "social media"}
        ]
    },
    "notifications": {"mode": "suppress_all"},
    "escape_hatch": {
        "mode": "standard",
        "delay_seconds": 60,
        "require_reason": True,
        "min_reason_chars": 20,
        "exception_scope": "scoped",
        "active_exceptions": []
    }
}

def load_schema():
    with open(SCHEMA_PATH) as f:
        return json.load(f)

def test_schema_file_exists():
    assert SCHEMA_PATH.exists(), f"Schema not found at {SCHEMA_PATH}"

def test_valid_policy_passes():
    schema = load_schema()
    jsonschema.validate(VALID_POLICY, schema)

def test_youtube_lecture_policy_passes():
    schema = load_schema()
    jsonschema.validate(YOUTUBE_LECTURE_POLICY, schema)

def test_allow_listed_policy_passes():
    schema = load_schema()
    jsonschema.validate(ALLOW_LISTED_POLICY, schema)

def test_missing_required_field_fails():
    schema = load_schema()
    bad = {**VALID_POLICY}
    del bad["apps"]
    with pytest.raises(jsonschema.ValidationError):
        jsonschema.validate(bad, schema)

def test_invalid_app_mode_fails():
    schema = load_schema()
    bad = {**VALID_POLICY, "apps": {"mode": "whitelist", "blocked": [], "allowed": []}}
    with pytest.raises(jsonschema.ValidationError):
        jsonschema.validate(bad, schema)

def test_invalid_url_action_fails():
    schema = load_schema()
    bad_rule = {"pattern": "twitter.com", "action": "ignore", "exceptions": [], "reason": "x"}
    bad = {**VALID_POLICY, "urls": {"rules": [bad_rule]}}
    with pytest.raises(jsonschema.ValidationError):
        jsonschema.validate(bad, schema)

def test_confidence_out_of_range_fails():
    schema = load_schema()
    bad = {**VALID_POLICY, "intent": {**VALID_POLICY["intent"], "confidence": 1.5}}
    with pytest.raises(jsonschema.ValidationError):
        jsonschema.validate(bad, schema)

def test_invalid_escape_hatch_mode_fails():
    schema = load_schema()
    bad = {**VALID_POLICY, "escape_hatch": {**VALID_POLICY["escape_hatch"], "mode": "immediate"}}
    with pytest.raises(jsonschema.ValidationError):
        jsonschema.validate(bad, schema)

def test_scoped_exception_structure():
    schema = load_schema()
    policy_with_exception = {
        **VALID_POLICY,
        "escape_hatch": {
            **VALID_POLICY["escape_hatch"],
            "active_exceptions": [{
                "exception_id": "exc-001",
                "target_type": "app",
                "target": "com.twitter.twitter",
                "granted_at": "2026-05-26T10:00:00Z",
                "expires_at": "2026-05-26T10:30:00Z",
                "reason": "checking a specific notification from my manager"
            }]
        }
    }
    jsonschema.validate(policy_with_exception, schema)
