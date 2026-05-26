import pytest
from unittest.mock import patch, MagicMock
from src.intent_engine import parse_intent, IntentError
from src.stira_policy import StiraPolicy
import json

MOCK_REPORT_POLICY = {
    "schema_version": "1.0",
    "session_id": "a1b2c3d4-e5f6-7890-abcd-ef1234567890",
    "intent": {"raw": "finish my report", "normalised": "finish my report", "confidence": 0.95},
    "session": {"duration_minutes": 90, "hard_stop": False},
    "apps": {
        "mode": "block_listed",
        "blocked": [{"bundle_id": "com.twitter.twitter", "display_name": "Twitter"}],
        "allowed": []
    },
    "urls": {"rules": [{"pattern": "twitter.com", "action": "block", "exceptions": [], "reason": "distraction"}]},
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

def make_mock_response(policy_dict):
    mock_resp = MagicMock()
    mock_resp.status_code = 200
    mock_resp.json.return_value = {"response": json.dumps(policy_dict)}
    return mock_resp

@patch("src.intent_engine.requests.post")
def test_returns_stira_policy(mock_post):
    mock_post.return_value = make_mock_response(MOCK_REPORT_POLICY)
    result = parse_intent("finish my report")
    assert isinstance(result, StiraPolicy)

@patch("src.intent_engine.requests.post")
def test_raw_intent_preserved(mock_post):
    mock_post.return_value = make_mock_response(MOCK_REPORT_POLICY)
    result = parse_intent("finish my report")
    assert result.intent.raw == "finish my report"

@patch("src.intent_engine.requests.post")
def test_confidence_in_range(mock_post):
    mock_post.return_value = make_mock_response(MOCK_REPORT_POLICY)
    result = parse_intent("finish my report")
    assert 0.0 <= result.intent.confidence <= 1.0

@patch("src.intent_engine.requests.post")
def test_api_failure_raises_intent_error(mock_post):
    mock_post.side_effect = Exception("connection refused")
    with pytest.raises(IntentError) as exc:
        parse_intent("finish my report")
    assert exc.value.code == "api_failure"

@patch("src.intent_engine.requests.post")
def test_invalid_json_raises_intent_error(mock_post):
    mock_resp = MagicMock()
    mock_resp.status_code = 200
    mock_resp.json.return_value = {"response": "not json at all"}
    mock_post.return_value = mock_resp
    with pytest.raises(IntentError) as exc:
        parse_intent("finish my report")
    assert exc.value.code == "parse_failure"

@patch("src.intent_engine.requests.post")
def test_prompt_contains_raw_intent(mock_post):
    mock_post.return_value = make_mock_response(MOCK_REPORT_POLICY)
    parse_intent("write my dissertation chapter")
    call_args = mock_post.call_args
    payload = call_args.kwargs.get("json") or call_args.args[1]
    assert "write my dissertation chapter" in payload["prompt"]

@patch("src.intent_engine.requests.post")
def test_format_parameter_is_schema_dict(mock_post):
    mock_post.return_value = make_mock_response(MOCK_REPORT_POLICY)
    parse_intent("finish my report")
    call_args = mock_post.call_args
    payload = call_args.kwargs.get("json") or call_args.args[1]
    assert "format" in payload
    assert isinstance(payload["format"], dict)
    assert payload["format"].get("type") == "object"

@patch("src.intent_engine.requests.post")
def test_model_is_qwen3_8b(mock_post):
    mock_post.return_value = make_mock_response(MOCK_REPORT_POLICY)
    parse_intent("finish my report")
    call_args = mock_post.call_args
    payload = call_args.kwargs.get("json") or call_args.args[1]
    assert payload["model"] == "qwen3:8b"

@patch("src.intent_engine.requests.post")
def test_stream_is_false(mock_post):
    mock_post.return_value = make_mock_response(MOCK_REPORT_POLICY)
    parse_intent("finish my report")
    call_args = mock_post.call_args
    payload = call_args.kwargs.get("json") or call_args.args[1]
    assert payload["stream"] is False

@patch("src.intent_engine.requests.post")
def test_schema_violation_raises_intent_error(mock_post):
    bad_policy = {**MOCK_REPORT_POLICY, "apps": {"mode": "invalid_mode", "blocked": [], "allowed": []}}
    mock_post.return_value = make_mock_response(bad_policy)
    with pytest.raises(IntentError) as exc:
        parse_intent("finish my report")
    assert exc.value.code == "schema_violation"
