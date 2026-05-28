import XCTest
@testable import StiraCore

final class PolicyDurationTests: XCTestCase {
    func testWithDurationOverridesLLMValue() {
        let policy = StiraPolicy.example  // has durationMinutes: 90
        let updated = policy.withDuration(minutes: 45)
        XCTAssertEqual(updated.session.durationMinutes, 45)
        XCTAssertEqual(updated.sessionId, policy.sessionId, "sessionId must not change")
        XCTAssertEqual(updated.apps, policy.apps, "apps must not change")
    }

    func testWithDurationPreservesHardStop() {
        let policy = StiraPolicy.example
        let updated = policy.withDuration(minutes: 30)
        XCTAssertEqual(updated.session.hardStop, policy.session.hardStop)
    }
}
