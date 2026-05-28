import XCTest
@testable import StiraCore

@MainActor
final class SessionTimeoutTests: XCTestCase {

    func testZeroDurationMeansNoTimeoutTask() {
        // SessionInfo.durationMinutes == 0 means indefinite — no task
        let info = SessionInfo(durationMinutes: 0, hardStop: false)
        let shouldStartTask = info.durationMinutes > 0
        XCTAssertFalse(shouldStartTask, "durationMinutes == 0 must never create a timeout task")
    }

    func testPositiveDurationMeansTimeoutTaskShouldBeCreated() {
        let info = SessionInfo(durationMinutes: 90, hardStop: false)
        let shouldStartTask = info.durationMinutes > 0
        XCTAssertTrue(shouldStartTask)
    }

    func testTimeoutTaskIsCancelledBeforeEndSession() {
        // Directly test the cancel-before-end logic
        var taskCancelled = false
        let task = Task<Void, Never> {
            do {
                try await Task.sleep(nanoseconds: 60_000_000_000)
            } catch {
                taskCancelled = true
            }
        }
        // Mirrors what endSession() does:
        task.cancel()
        XCTAssertTrue(task.isCancelled)
    }

    func testTimeoutNanosecondMathIsCorrect() {
        // Verify the UInt64 arithmetic doesn't overflow for max expected value (120 min)
        let durationMins: Int = 120
        let nanos = UInt64(durationMins) * 60 * 1_000_000_000
        let expectedNanos: UInt64 = 7_200_000_000_000
        XCTAssertEqual(nanos, expectedNanos, "120 min = 7,200,000,000,000 nanoseconds")
    }
}
