"""
StiraPolicy — Python dataclass representation of the Stira policy schema.

Mirrors docs/schema/stira-policy.schema.json exactly.
stdlib only — no third-party dependencies.
"""

from __future__ import annotations

from dataclasses import dataclass
from datetime import datetime
from typing import List, Literal


# ---------------------------------------------------------------------------
# Leaf types
# ---------------------------------------------------------------------------

AppMode = Literal["block_listed", "allow_listed"]
UrlAction = Literal["block", "allow"]
NotificationMode = Literal["suppress_all", "allow_all", "allow_calendar", "allow_calls_only"]
EscapeHatchMode = Literal["soft", "standard", "strict", "nuclear"]
ExceptionScope = Literal["scoped", "global"]
TargetType = Literal["app", "url"]


@dataclass(frozen=True)
class AppRule:
    bundle_id: str
    display_name: str

    @classmethod
    def from_dict(cls, d: dict) -> "AppRule":
        return cls(
            bundle_id=d["bundle_id"],
            display_name=d["display_name"],
        )

    def to_dict(self) -> dict:
        return {
            "bundle_id": self.bundle_id,
            "display_name": self.display_name,
        }


@dataclass(frozen=True)
class UrlException:
    pattern: str
    reason: str

    @classmethod
    def from_dict(cls, d: dict) -> "UrlException":
        return cls(
            pattern=d["pattern"],
            reason=d["reason"],
        )

    def to_dict(self) -> dict:
        return {
            "pattern": self.pattern,
            "reason": self.reason,
        }


@dataclass(frozen=True)
class UrlRule:
    pattern: str
    action: UrlAction
    exceptions: tuple[UrlException, ...]
    reason: str

    @classmethod
    def from_dict(cls, d: dict) -> "UrlRule":
        return cls(
            pattern=d["pattern"],
            action=d["action"],
            exceptions=tuple(UrlException.from_dict(e) for e in d["exceptions"]),
            reason=d["reason"],
        )

    def to_dict(self) -> dict:
        return {
            "pattern": self.pattern,
            "action": self.action,
            "exceptions": [e.to_dict() for e in self.exceptions],
            "reason": self.reason,
        }


@dataclass(frozen=True)
class ScopedException:
    exception_id: str
    target_type: TargetType
    target: str
    granted_at: str  # ISO 8601 string
    expires_at: str  # ISO 8601 string
    reason: str

    @classmethod
    def from_dict(cls, d: dict) -> "ScopedException":
        return cls(
            exception_id=d["exception_id"],
            target_type=d["target_type"],
            target=d["target"],
            granted_at=d["granted_at"],
            expires_at=d["expires_at"],
            reason=d["reason"],
        )

    def to_dict(self) -> dict:
        return {
            "exception_id": self.exception_id,
            "target_type": self.target_type,
            "target": self.target,
            "granted_at": self.granted_at,
            "expires_at": self.expires_at,
            "reason": self.reason,
        }


# ---------------------------------------------------------------------------
# Nested config objects
# ---------------------------------------------------------------------------

@dataclass(frozen=True)
class IntentInfo:
    raw: str
    normalised: str
    confidence: float  # 0.0–1.0

    @classmethod
    def from_dict(cls, d: dict) -> "IntentInfo":
        return cls(
            raw=d["raw"],
            normalised=d["normalised"],
            confidence=float(d["confidence"]),
        )

    def to_dict(self) -> dict:
        return {
            "raw": self.raw,
            "normalised": self.normalised,
            "confidence": self.confidence,
        }


@dataclass(frozen=True)
class SessionInfo:
    duration_minutes: int  # 0 = indefinite
    hard_stop: bool

    @classmethod
    def from_dict(cls, d: dict) -> "SessionInfo":
        return cls(
            duration_minutes=int(d["duration_minutes"]),
            hard_stop=bool(d["hard_stop"]),
        )

    def to_dict(self) -> dict:
        return {
            "duration_minutes": self.duration_minutes,
            "hard_stop": self.hard_stop,
        }


@dataclass(frozen=True)
class AppsConfig:
    mode: AppMode
    blocked: tuple[AppRule, ...]
    allowed: tuple[AppRule, ...]

    @classmethod
    def from_dict(cls, d: dict) -> "AppsConfig":
        return cls(
            mode=d["mode"],
            blocked=tuple(AppRule.from_dict(r) for r in d["blocked"]),
            allowed=tuple(AppRule.from_dict(r) for r in d["allowed"]),
        )

    def to_dict(self) -> dict:
        return {
            "mode": self.mode,
            "blocked": [r.to_dict() for r in self.blocked],
            "allowed": [r.to_dict() for r in self.allowed],
        }


@dataclass(frozen=True)
class UrlsConfig:
    rules: tuple[UrlRule, ...]

    @classmethod
    def from_dict(cls, d: dict) -> "UrlsConfig":
        return cls(
            rules=tuple(UrlRule.from_dict(r) for r in d["rules"]),
        )

    def to_dict(self) -> dict:
        return {
            "rules": [r.to_dict() for r in self.rules],
        }


@dataclass(frozen=True)
class NotificationsConfig:
    mode: NotificationMode

    @classmethod
    def from_dict(cls, d: dict) -> "NotificationsConfig":
        return cls(mode=d["mode"])

    def to_dict(self) -> dict:
        return {"mode": self.mode}


@dataclass(frozen=True)
class EscapeHatchConfig:
    mode: EscapeHatchMode
    delay_seconds: int
    require_reason: bool
    min_reason_chars: int
    exception_scope: ExceptionScope
    active_exceptions: tuple[ScopedException, ...]

    @classmethod
    def from_dict(cls, d: dict) -> "EscapeHatchConfig":
        return cls(
            mode=d["mode"],
            delay_seconds=int(d["delay_seconds"]),
            require_reason=bool(d["require_reason"]),
            min_reason_chars=int(d["min_reason_chars"]),
            exception_scope=d["exception_scope"],
            active_exceptions=tuple(
                ScopedException.from_dict(e) for e in d["active_exceptions"]
            ),
        )

    def to_dict(self) -> dict:
        return {
            "mode": self.mode,
            "delay_seconds": self.delay_seconds,
            "require_reason": self.require_reason,
            "min_reason_chars": self.min_reason_chars,
            "exception_scope": self.exception_scope,
            "active_exceptions": [e.to_dict() for e in self.active_exceptions],
        }


# ---------------------------------------------------------------------------
# Top-level policy object
# ---------------------------------------------------------------------------

@dataclass(frozen=True)
class StiraPolicy:
    schema_version: str  # const "1.0"
    session_id: str
    intent: IntentInfo
    session: SessionInfo
    apps: AppsConfig
    urls: UrlsConfig
    notifications: NotificationsConfig
    escape_hatch: EscapeHatchConfig

    @classmethod
    def from_dict(cls, d: dict) -> "StiraPolicy":
        return cls(
            schema_version=d["schema_version"],
            session_id=d["session_id"],
            intent=IntentInfo.from_dict(d["intent"]),
            session=SessionInfo.from_dict(d["session"]),
            apps=AppsConfig.from_dict(d["apps"]),
            urls=UrlsConfig.from_dict(d["urls"]),
            notifications=NotificationsConfig.from_dict(d["notifications"]),
            escape_hatch=EscapeHatchConfig.from_dict(d["escape_hatch"]),
        )

    def to_dict(self) -> dict:
        return {
            "schema_version": self.schema_version,
            "session_id": self.session_id,
            "intent": self.intent.to_dict(),
            "session": self.session.to_dict(),
            "apps": self.apps.to_dict(),
            "urls": self.urls.to_dict(),
            "notifications": self.notifications.to_dict(),
            "escape_hatch": self.escape_hatch.to_dict(),
        }
