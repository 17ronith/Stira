import XCTest
@testable import StiraCore

@MainActor
final class EscapeHatchControllerTests: XCTestCase {

    private let sampleApps = [
        AppRule(bundleId: "com.example.blocked", displayName: "Blocked App"),
        AppRule(bundleId: "com.discord.app", displayName: "Discord"),
    ]

    func testBeginEscapeHatchEntersAppPicker() {
        let c = EscapeHatchController()
        c.beginEscapeHatch(blockedApps: sampleApps)
        XCTAssertEqual(c.state, .appPicker)
        XCTAssertEqual(c.blockedApps.count, 2)
        XCTAssertNil(c.currentTarget)
    }

    func testSelectAppTransitionsToCountdown() {
        let c = EscapeHatchController()
        c.beginEscapeHatch(blockedApps: sampleApps)
        c.selectApp(bundleId: "com.discord.app", displayName: "Discord")
        XCTAssertEqual(c.state, .countdown(remaining: 30))
        XCTAssertEqual(c.currentTarget, "com.discord.app")
        XCTAssertEqual(c.currentTargetDisplayName, "Discord")
    }

    func testSelectCustomAppTransitionsToCountdown() {
        let c = EscapeHatchController()
        c.beginEscapeHatch(blockedApps: sampleApps)
        c.selectCustomApp(name: "WhatsApp")
        XCTAssertEqual(c.state, .countdown(remaining: 30))
        XCTAssertNil(c.currentTarget, "Custom apps have no bundle ID")
        XCTAssertEqual(c.currentTargetDisplayName, "WhatsApp")
    }

    func testResetFromIdleSetsIdle() {
        let c = EscapeHatchController()
        c.reset()
        XCTAssertEqual(c.state, .idle)
        XCTAssertEqual(c.reason, "")
        XCTAssertNil(c.currentTarget)
        XCTAssertNil(c.currentTargetDisplayName)
        XCTAssertTrue(c.blockedApps.isEmpty)
    }

    func testResetFromCountdownStopsTimer() async throws {
        let c = EscapeHatchController()
        c.beginEscapeHatch(blockedApps: sampleApps)
        c.selectApp(bundleId: "com.example.blocked", displayName: "Blocked App")
        XCTAssertEqual(c.state, .countdown(remaining: 30))

        c.reset()

        XCTAssertEqual(c.state, .idle)
        XCTAssertNil(c.currentTarget)
        XCTAssertEqual(c.reason, "")

        try await Task.sleep(nanoseconds: 1_100_000_000)
        XCTAssertEqual(c.state, .idle, "Timer must not fire after reset()")
    }

    func testResetFromReasonEntryClears() {
        let c = EscapeHatchController()
        c.beginEscapeHatch(blockedApps: sampleApps)
        c.selectApp(bundleId: "com.discord.app", displayName: "Discord")
        c.reason = "some long reason text here for the test"
        c.state = .reasonEntry

        c.reset()

        XCTAssertEqual(c.state, .idle)
        XCTAssertEqual(c.reason, "")
        XCTAssertNil(c.currentTarget)
    }

    func testResetFromGrantedClears() {
        let c = EscapeHatchController()
        c.state = .granted
        c.reason = "a sufficiently long reason string"
        c.currentTarget = "com.spotify.client"
        c.currentTargetDisplayName = "Spotify"

        c.reset()

        XCTAssertEqual(c.state, .idle)
        XCTAssertEqual(c.reason, "")
        XCTAssertNil(c.currentTarget)
        XCTAssertNil(c.currentTargetDisplayName)
    }
}
