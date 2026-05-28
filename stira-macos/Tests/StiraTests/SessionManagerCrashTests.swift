import XCTest
@testable import StiraCore

@MainActor
final class SessionManagerCrashTests: XCTestCase {

    func testHandleHermesCrashFromActiveResetsToIdle() {
        let sm = SessionManager()
        sm.state = .active
        sm.sessionStartTime = Date()

        sm.handleHermesCrash(exitCode: 1)

        XCTAssertEqual(sm.state, .idle)
        XCTAssertNil(sm.sessionStartTime)
        XCTAssertNotNil(sm.errorMessage)
        XCTAssertTrue(sm.errorMessage?.contains("exit 1") == true,
                      "Error message must include exit code")
    }

    func testHandleHermesCrashFromEscapeHatchResetsEscapeHatch() {
        let sm = SessionManager()
        sm.state = .escapeHatch
        sm.sessionStartTime = Date()
        sm.escapeHatchController.beginEscapeHatch(blockedApps: [
            AppRule(bundleId: "com.discord.app", displayName: "Discord")
        ])
        sm.escapeHatchController.selectApp(bundleId: "com.discord.app", displayName: "Discord")

        sm.handleHermesCrash(exitCode: 137)

        XCTAssertEqual(sm.state, .idle)
        XCTAssertEqual(sm.escapeHatchController.state, .idle,
                       "EscapeHatch must be reset when Hermes crashes during escapeHatch")
        XCTAssertNil(sm.sessionStartTime)
    }

    func testHandleHermesCrashFromEndingIsIgnored() {
        // .ending means endSession() is already running — don't double-reset
        let sm = SessionManager()
        sm.state = .ending
        sm.errorMessage = nil

        sm.handleHermesCrash(exitCode: 0)

        XCTAssertEqual(sm.state, .ending, "Guard must not change state from .ending")
        XCTAssertNil(sm.errorMessage)
    }

    func testHandleHermesCrashFromIdleIsIgnored() {
        let sm = SessionManager()
        sm.state = .idle
        sm.errorMessage = nil

        sm.handleHermesCrash(exitCode: 1)

        XCTAssertEqual(sm.state, .idle, "Guard must not change state from .idle")
        XCTAssertNil(sm.errorMessage)
    }

    func testHandleHermesCrashFromStartingIsIgnored() {
        // .starting means startup failed — connectWithRetry handles it, not crash handler
        let sm = SessionManager()
        sm.state = .starting
        sm.errorMessage = nil

        sm.handleHermesCrash(exitCode: 1)

        XCTAssertEqual(sm.state, .starting, "Guard must not change state from .starting")
        XCTAssertNil(sm.errorMessage)
    }

    func testHandleHermesCrashCancelsTimeoutTask() {
        let sm = SessionManager()
        sm.state = .active
        let task = Task<Void, Never> {
            try? await Task.sleep(nanoseconds: 60_000_000_000) // 60s
        }
        sm.sessionTimeoutTask = task

        sm.handleHermesCrash(exitCode: 1)

        XCTAssertTrue(task.isCancelled, "Timeout task must be cancelled on crash")
        XCTAssertNil(sm.sessionTimeoutTask, "sessionTimeoutTask must be nil after crash")
    }
}
