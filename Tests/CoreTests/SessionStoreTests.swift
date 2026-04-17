import XCTest
@testable import Core

@MainActor
final class SessionStoreTests: XCTestCase {
    func test_userVisibleSessions_filtersInternal() async {
        let store = SessionStore()
        store.apply(sessions: [
            TmuxSession(id: "dev", isAttached: false, windowCount: 1, createdAt: .now, lastActivityAt: .now, workingDirectory: nil),
            TmuxSession(id: "_muxbar-ctl", isAttached: false, windowCount: 1, createdAt: .now, lastActivityAt: .now, workingDirectory: nil),
            TmuxSession(id: "_muxbar-awake", isAttached: false, windowCount: 1, createdAt: .now, lastActivityAt: .now, workingDirectory: nil),
        ])

        XCTAssertEqual(store.userVisibleSessions.map(\.id), ["dev"])
    }

    func test_awakeSessionExists_detectsAwakeSession() async {
        let store = SessionStore()
        XCTAssertFalse(store.awakeSessionExists)

        store.apply(sessions: [
            TmuxSession(id: "_muxbar-awake", isAttached: false, windowCount: 1, createdAt: .now, lastActivityAt: .now, workingDirectory: nil),
        ])
        XCTAssertTrue(store.awakeSessionExists)
    }
}
