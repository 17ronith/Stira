// StiraPolicy.swift
// Mirror of docs/schema/stira-policy.schema.json
// All types are Codable, Equatable, and use snake_case JSON keys.

import Foundation

// MARK: - Enums

enum AppMode: String, Codable, Equatable {
    case blockListed = "block_listed"
    case allowListed = "allow_listed"

    init(from decoder: Decoder) throws {
        let raw = try decoder.singleValueContainer().decode(String.self)
        self = AppMode(rawValue: raw) ?? .blockListed
    }
}

enum UrlAction: String, Codable, Equatable {
    case block = "block"
    case allow = "allow"

    init(from decoder: Decoder) throws {
        let raw = try decoder.singleValueContainer().decode(String.self).trimmingCharacters(in: .whitespaces).lowercased()
        switch raw {
        case "block": self = .block
        case "allow": self = .allow
        default: self = .block
        }
    }
}

enum NotificationMode: String, Codable, Equatable {
    case suppressAll = "suppress_all"
    case allowAll = "allow_all"
    case allowCalendar = "allow_calendar"
    case allowCallsOnly = "allow_calls_only"

    init(from decoder: Decoder) throws {
        let raw = try decoder.singleValueContainer().decode(String.self)
        self = NotificationMode(rawValue: raw) ?? .suppressAll
    }
}

enum EscapeHatchMode: String, Codable, Equatable {
    case soft = "soft"
    case standard = "standard"
    case strict = "strict"
    case nuclear = "nuclear"

    init(from decoder: Decoder) throws {
        let raw = try decoder.singleValueContainer().decode(String.self)
        self = EscapeHatchMode(rawValue: raw) ?? .standard
    }
}

enum ExceptionScope: String, Codable, Equatable {
    case scoped = "scoped"
    case global = "global"

    init(from decoder: Decoder) throws {
        let raw = try decoder.singleValueContainer().decode(String.self)
        self = ExceptionScope(rawValue: raw) ?? .scoped
    }
}

enum TargetType: String, Codable, Equatable {
    case app = "app"
    case url = "url"

    init(from decoder: Decoder) throws {
        let raw = try decoder.singleValueContainer().decode(String.self)
        self = TargetType(rawValue: raw) ?? .app
    }
}

// MARK: - Nested Types

struct AppRule: Codable, Equatable {
    let bundleId: String
    let displayName: String

    enum CodingKeys: String, CodingKey {
        case bundleId = "bundle_id"
        case displayName = "display_name"
    }

    init(bundleId: String, displayName: String) {
        self.bundleId = bundleId
        self.displayName = displayName
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        bundleId = try c.decode(String.self, forKey: .bundleId)
        displayName = (try? c.decode(String.self, forKey: .displayName)) ?? ""
    }
}

struct UrlException: Codable, Equatable {
    let pattern: String
    let reason: String
}

struct UrlRule: Codable, Equatable {
    let pattern: String
    let action: UrlAction
    let exceptions: [UrlException]
    let reason: String

    init(pattern: String, action: UrlAction, exceptions: [UrlException], reason: String) {
        self.pattern = pattern; self.action = action; self.exceptions = exceptions; self.reason = reason
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        pattern = try c.decode(String.self, forKey: .pattern)
        action = try c.decode(UrlAction.self, forKey: .action)
        reason = (try? c.decode(String.self, forKey: .reason)) ?? ""
        exceptions = (try? c.decode([UrlException].self, forKey: .exceptions)) ?? []
    }

    private enum CodingKeys: String, CodingKey {
        case pattern, action, exceptions, reason
    }
}

struct ScopedException: Codable, Equatable {
    let exceptionId: String
    let targetType: TargetType
    let target: String
    let grantedAt: String   // ISO 8601
    let expiresAt: String   // ISO 8601
    let reason: String

    enum CodingKeys: String, CodingKey {
        case exceptionId = "exception_id"
        case targetType = "target_type"
        case target
        case grantedAt = "granted_at"
        case expiresAt = "expires_at"
        case reason
    }
}

// MARK: - Config Objects

struct IntentInfo: Codable, Equatable {
    let raw: String
    let normalised: String
    let confidence: Double
}

struct SessionInfo: Codable, Equatable {
    let durationMinutes: Int   // 0 = indefinite
    let hardStop: Bool

    enum CodingKeys: String, CodingKey {
        case durationMinutes = "duration_minutes"
        case hardStop = "hard_stop"
    }
}

struct AppsConfig: Codable, Equatable {
    let mode: AppMode
    let blocked: [AppRule]
    let allowed: [AppRule]
}

struct UrlsConfig: Codable, Equatable {
    let rules: [UrlRule]
}

struct NotificationsConfig: Codable, Equatable {
    let mode: NotificationMode
}

struct EscapeHatchConfig: Codable, Equatable {
    let mode: EscapeHatchMode
    let delaySeconds: Int
    let requireReason: Bool
    let minReasonChars: Int
    let exceptionScope: ExceptionScope
    let activeExceptions: [ScopedException]

    enum CodingKeys: String, CodingKey {
        case mode
        case delaySeconds = "delay_seconds"
        case requireReason = "require_reason"
        case minReasonChars = "min_reason_chars"
        case exceptionScope = "exception_scope"
        case activeExceptions = "active_exceptions"
    }
}

// MARK: - Top-Level Policy

struct StiraPolicy: Encodable, Equatable {
    let schemaVersion: String   // const "1.0"
    let sessionId: String
    let intent: IntentInfo
    let session: SessionInfo
    let apps: AppsConfig
    let urls: UrlsConfig
    let notifications: NotificationsConfig
    let escapeHatch: EscapeHatchConfig

    enum CodingKeys: String, CodingKey {
        case schemaVersion = "schema_version"
        case sessionId = "session_id"
        case intent
        case session
        case apps
        case urls
        case notifications
        case escapeHatch = "escape_hatch"
    }

}

// MARK: - Example

extension StiraPolicy {
    /// Example policy matching the VALID_POLICY fixture in test_policy_schema.py
    static let example = StiraPolicy(
        schemaVersion: "1.0",
        sessionId: "a1b2c3d4-e5f6-7890-abcd-ef1234567890",
        intent: IntentInfo(
            raw: "I need to finish my quarterly report",
            normalised: "i need to finish my quarterly report",
            confidence: 0.96
        ),
        session: SessionInfo(durationMinutes: 90, hardStop: false),
        apps: AppsConfig(
            mode: .blockListed,
            blocked: [AppRule(bundleId: "com.twitter.twitter", displayName: "Twitter")],
            allowed: []
        ),
        urls: UrlsConfig(
            rules: [
                UrlRule(
                    pattern: "twitter.com",
                    action: .block,
                    exceptions: [],
                    reason: "social media"
                )
            ]
        ),
        notifications: NotificationsConfig(mode: .suppressAll),
        escapeHatch: EscapeHatchConfig(
            mode: .standard,
            delaySeconds: 30,
            requireReason: true,
            minReasonChars: 20,
            exceptionScope: .scoped,
            activeExceptions: []
        )
    )
}

// The model sometimes omits notifications/escape_hatch when it runs out of token budget.
// Provide safe defaults so sessions still start rather than failing with a decode error.
extension StiraPolicy: Decodable {
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        schemaVersion = (try? c.decode(String.self, forKey: .schemaVersion)) ?? "1.0"
        sessionId = try c.decode(String.self, forKey: .sessionId)
        intent = try c.decode(IntentInfo.self, forKey: .intent)
        session = try c.decode(SessionInfo.self, forKey: .session)
        apps = try c.decode(AppsConfig.self, forKey: .apps)
        urls = (try? c.decode(UrlsConfig.self, forKey: .urls)) ?? UrlsConfig(rules: [])
        notifications = (try? c.decode(NotificationsConfig.self, forKey: .notifications))
            ?? NotificationsConfig(mode: .suppressAll)
        escapeHatch = (try? c.decode(EscapeHatchConfig.self, forKey: .escapeHatch))
            ?? EscapeHatchConfig(mode: .standard, delaySeconds: 30, requireReason: true,
                                 minReasonChars: 20, exceptionScope: .scoped, activeExceptions: [])
    }
}

extension StiraPolicy {
    func withDuration(minutes: Int) -> StiraPolicy {
        StiraPolicy(
            schemaVersion: schemaVersion,
            sessionId: sessionId,
            intent: intent,
            session: SessionInfo(durationMinutes: minutes, hardStop: session.hardStop),
            apps: apps,
            urls: urls,
            notifications: notifications,
            escapeHatch: escapeHatch
        )
    }
}
