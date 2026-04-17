import XCTest
@testable import Core

@MainActor
final class AwakeStoreTests: XCTestCase {
    func test_isAwake_delegatesToSessionStore() async {
        let sessions = SessionStore()
        let awake = AwakeStore()

        XCTAssertFalse(awake.isAwake(in: sessions))

        sessions.apply(sessions: [
            TmuxSession(id: "_muxbar-awake", isAttached: false, windowCount: 1,
                        createdAt: .now, lastActivityAt: .now, workingDirectory: nil)
        ])
        XCTAssertTrue(awake.isAwake(in: sessions))
    }

    func test_setFlags_rejectsInvalid() async {
        let awake = AwakeStore()
        let original = awake.flags

        let empty = CaffeinateFlags(d: false, i: false, m: false, s: false, u: false)
        awake.setFlags(empty)
        XCTAssertEqual(awake.flags, original, "invalid flags should be rejected")
    }
}
