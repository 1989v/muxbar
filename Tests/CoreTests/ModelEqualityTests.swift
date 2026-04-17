import XCTest
@testable import Core

final class ModelEqualityTests: XCTestCase {
    func test_tmuxSession_equality_byAllFields() {
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        let a = TmuxSession(
            id: "dev",
            isAttached: true,
            windowCount: 3,
            createdAt: now,
            lastActivityAt: now,
            workingDirectory: "/Users/kgd/msa"
        )
        let b = TmuxSession(
            id: "dev",
            isAttached: true,
            windowCount: 3,
            createdAt: now,
            lastActivityAt: now,
            workingDirectory: "/Users/kgd/msa"
        )
        XCTAssertEqual(a, b)
    }

    func test_tmuxSession_isInternal_prefixUnderscoreMuxbar() {
        let internalSession = TmuxSession(
            id: "_muxbar-ctl", isAttached: false, windowCount: 1,
            createdAt: .now, lastActivityAt: .now, workingDirectory: nil
        )
        XCTAssertTrue(internalSession.isInternal)

        let userSession = TmuxSession(
            id: "dev", isAttached: false, windowCount: 1,
            createdAt: .now, lastActivityAt: .now, workingDirectory: nil
        )
        XCTAssertFalse(userSession.isInternal)
    }
}
