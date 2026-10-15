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

@MainActor
final class KeepAwakeClosedLidSeparationTests: XCTestCase {
    func test_closedLidOnly_isNotKeepAwake() {
        let sessions = SessionStore()
        sessions.apply(caffeinateStatus: CaffeinateStatus(tmuxSessions: [ClosedLidStore.sessionName]))

        XCTAssertFalse(AwakeStore().isAwake(in: sessions))
        XCTAssertEqual(AwakeStore().source(in: sessions), .none)
    }

    func test_toggleOff_keepsClosedLidSession() async {
        let sessions = SessionStore()
        sessions.apply(caffeinateStatus: CaffeinateStatus(
            tmuxSessions: [AwakeStore.awakeSessionName, ClosedLidStore.sessionName]
        ))
        let provider = FakeSessionProvider()

        await AwakeStore().toggle(in: sessions, via: provider)

        XCTAssertEqual(provider.killedSessions, [AwakeStore.awakeSessionName])
        XCTAssertTrue(provider.createdSessions.isEmpty)
    }

    func test_toggleWhileOnlyClosedLid_turnsKeepAwakeOn() async {
        let sessions = SessionStore()
        sessions.apply(caffeinateStatus: CaffeinateStatus(tmuxSessions: [ClosedLidStore.sessionName]))
        let provider = FakeSessionProvider()

        await AwakeStore().toggle(in: sessions, via: provider)

        XCTAssertTrue(provider.killedSessions.isEmpty)
        XCTAssertEqual(provider.createdSessions.map(\.name), [AwakeStore.awakeSessionName])
    }

    func test_caffeinatePids_parsedFromAssertions() {
        let text = """
           pid 54760(caffeinate): [0x1] 568:33:44 PreventUserIdleSystemSleep named: "caffeinate command-line tool"
           pid 54760(caffeinate): [0x2] 568:33:44 PreventSystemSleep named: "caffeinate command-line tool"
           pid 126(powerd): [0x3] 00:42:58 PreventUserIdleSystemSleep named: "Powerd"
           pid 72425(caffeinate): [0x4] 00:01:08 PreventUserIdleSystemSleep named: "caffeinate command-line tool"
        """
        XCTAssertEqual(SystemCaffeinateDetector.caffeinatePids(fromAssertions: text), [54760, 72425])
    }

    /// tmux 안의 caffeinate(Closed-lid 포함)는 바깥 것으로 세지 않는다.
    func test_tmuxChildren_areNotExternal() {
        let ps = """
          17465     1 /opt/homebrew/bin/tmux
          54760 17465 caffeinate
          72000     1 /Applications/Some App.app/Contents/MacOS/Some App
          72425 72000 caffeinate
        """
        XCTAssertEqual(SystemCaffeinateDetector.excludingTmuxChildren([54760, 72425, 99999], psOutput: ps), [72425])
    }
}
