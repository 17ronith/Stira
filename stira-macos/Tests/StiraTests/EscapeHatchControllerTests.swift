import XCTest
@testable import StiraCore

@MainActor
final class EscapeHatchControllerTests: XCTestCase {

    func testResetFromIdleSetsIdle() {
        let c = EscapeHatchController()
        c.reset()
        XCTAssertEqual(c.state, .idle)
        XCTAssertEqual(c.reason, "")
        XCTAssertNil(c.currentTarget)
    }

    func testResetFromCountdownStopsTimer() async throws {
        let c = EscapeHatchController()
        c.beginEscapeHatch(target: "com.example.blocked")
        XCTAssertEqual(c.state, .countdown(remaining: 30))

        c.reset()

        XCTAssertEqual(c.state, .idle)
        XCTAssertNil(c.currentTarget)
        XCTAssertEqual(c.reason, "")

        // Confirm the timer does NOT decrement state after 1.1 seconds
        try await Task.sleep(nanoseconds: 1_100_000_000)
        XCTAssertEqual(c.state, .idle, "Timer must not fire after reset()")
    }

    func testResetFromReasonEntryClears() {
        let c = EscapeHatchController()
        c.beginEscapeHatch(target: "com.discord.app")
        c.reason = "some long reason text here for the test"
        // Bypass the 30s countdown — force to reasonEntry directly
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

        c.reset()

        XCTAssertEqual(c.state, .idle)
        XCTAssertEqual(c.reason, "")
        XCTAssertNil(c.currentTarget)
    }
}
