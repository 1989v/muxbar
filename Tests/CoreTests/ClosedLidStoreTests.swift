import XCTest
@testable import Core

// 테스트 전용: @MainActor 컨텍스트에서만 접근하므로 race-free 가정.
final class FakeSessionProvider: SessionProvider, @unchecked Sendable {
    var createdSessions: [(name: String, command: String?)] = []
    var killedSessions: [String] = []
    var shouldFailCreate = false
    var shouldFailKill = false

    var events: AsyncStream<SessionProviderEvent> { AsyncStream { _ in } }
    var paneOutput: AsyncStream<PaneOutputChunk> { AsyncStream { _ in } }

    func listSessions() async throws -> [TmuxSession] { [] }
    func capturePane(target: String, lines: Int) async throws -> String { "" }
    func listCaffeinateSessions() async throws -> [String] { [] }

    func createSession(name: String, command: String?) async throws {
        if shouldFailCreate { throw NSError(domain: "fake", code: 1) }
        createdSessions.append((name, command))
    }

    func kill(sessionName: String) async throws {
        if shouldFailKill { throw NSError(domain: "fake", code: 1) }
        killedSessions.append(sessionName)
    }
}

// 테스트 전용: @MainActor 컨텍스트에서만 접근하므로 race-free 가정.
final class FakePowerController: ClosedLidStore.PowerController, @unchecked Sendable {
    var disableCalls = 0
    var enableCalls = 0
    var shouldThrowOnDisable: Error?
    var shouldThrowOnEnable: Error?

    func disableSystemSleep() async throws {
        disableCalls += 1
        if let e = shouldThrowOnDisable { throw e }
    }
    func enableSystemSleep() async throws {
        enableCalls += 1
        if let e = shouldThrowOnEnable { throw e }
    }
}

@MainActor
final class ClosedLidStoreTests: XCTestCase {
    func test_initialState_isOff() {
        let store = ClosedLidStore(power: FakePowerController())
        XCTAssertEqual(store.state, .off)
    }

    func test_turnOn_callsPowerControlAndCreatesCaffeineSession() async throws {
        let power = FakePowerController()
        let provider = FakeSessionProvider()
        let store = ClosedLidStore(power: power)

        await store.turnOn(duration: nil, sessionProvider: provider)

        XCTAssertEqual(power.disableCalls, 1)
        XCTAssertEqual(provider.createdSessions.count, 1)
        XCTAssertEqual(provider.createdSessions[0].name, "_muxbar-closed-lid")
        XCTAssertEqual(provider.createdSessions[0].command, "caffeinate -is")
        XCTAssertEqual(store.state, .on(expiresAt: nil))
    }

    func test_turnOn_powerCancelled_stateRemainsOff() async {
        let power = FakePowerController()
        power.shouldThrowOnDisable = PowerControl.Error.userCancelled
        let provider = FakeSessionProvider()
        let store = ClosedLidStore(power: power)

        await store.turnOn(duration: nil, sessionProvider: provider)

        XCTAssertEqual(store.state, .off)
        XCTAssertEqual(provider.createdSessions.count, 0)
    }

    func test_forceOff_callsEnableAndKillsSession() async {
        let power = FakePowerController()
        let provider = FakeSessionProvider()
        let store = ClosedLidStore(power: power)
        await store.turnOn(duration: nil, sessionProvider: provider)

        await store.forceOff(sessionProvider: provider)

        XCTAssertEqual(power.enableCalls, 1)
        XCTAssertEqual(provider.killedSessions, ["_muxbar-closed-lid"])
        XCTAssertEqual(store.state, .off)
    }

    func test_forceOff_idempotent_whenAlreadyOff() async {
        let power = FakePowerController()
        let provider = FakeSessionProvider()
        let store = ClosedLidStore(power: power)

        await store.forceOff(sessionProvider: provider)
        await store.forceOff(sessionProvider: provider)

        XCTAssertEqual(power.enableCalls, 0)
        XCTAssertEqual(provider.killedSessions.count, 0)
    }

    func test_turnOn_withDuration_setsExpiresAt() async {
        let power = FakePowerController()
        let provider = FakeSessionProvider()
        let store = ClosedLidStore(power: power)
        let before = Date()

        await store.turnOn(duration: .seconds(3600), sessionProvider: provider)

        guard case .on(let expiresAt) = store.state, let expiresAt else {
            return XCTFail("expected .on(expiresAt:)")
        }
        XCTAssertGreaterThanOrEqual(expiresAt.timeIntervalSince(before), 3590)
        XCTAssertLessThanOrEqual(expiresAt.timeIntervalSince(before), 3610)
    }

    func test_turnOn_sessionCreateFails_stateStillOn() async {
        let power = FakePowerController()
        let provider = FakeSessionProvider()
        provider.shouldFailCreate = true
        let store = ClosedLidStore(power: power)

        await store.turnOn(duration: nil, sessionProvider: provider)

        XCTAssertEqual(power.disableCalls, 1)
        XCTAssertEqual(provider.createdSessions.count, 0)
        XCTAssertEqual(store.state, .on(expiresAt: nil))
    }

    func test_forceOff_killFails_stateStillOff() async {
        let power = FakePowerController()
        let provider = FakeSessionProvider()
        let store = ClosedLidStore(power: power)
        await store.turnOn(duration: nil, sessionProvider: provider)

        provider.shouldFailKill = true
        await store.forceOff(sessionProvider: provider)

        XCTAssertEqual(power.enableCalls, 1)
        XCTAssertEqual(store.state, .off)
    }

    func test_forceOff_userCancelled_stateStaysOn() async {
        let power = FakePowerController()
        let provider = FakeSessionProvider()
        let store = ClosedLidStore(power: power)
        await store.turnOn(duration: nil, sessionProvider: provider)

        power.shouldThrowOnEnable = PowerControl.Error.userCancelled
        await store.forceOff(sessionProvider: provider)

        XCTAssertEqual(power.enableCalls, 1)
        XCTAssertEqual(store.state, .on(expiresAt: nil))  // CRITICAL #1 검증
        XCTAssertEqual(provider.killedSessions.count, 0)  // kill 도 진행 안 됨
    }

    func test_turnOn_withShortDuration_autoForceOffAfterExpiry() async throws {
        let power = FakePowerController()
        let provider = FakeSessionProvider()
        let store = ClosedLidStore(power: power)

        await store.turnOn(duration: .milliseconds(100), sessionProvider: provider)
        XCTAssertTrue(store.state.isOn)

        try await Task.sleep(nanoseconds: 250_000_000)

        XCTAssertEqual(store.state, .off)
        XCTAssertEqual(power.enableCalls, 1)
    }

    func test_forceOff_cancelsPendingTimer() async throws {
        let power = FakePowerController()
        let provider = FakeSessionProvider()
        let store = ClosedLidStore(power: power)

        await store.turnOn(duration: .milliseconds(500), sessionProvider: provider)
        await store.forceOff(sessionProvider: provider)

        try await Task.sleep(nanoseconds: 700_000_000)

        XCTAssertEqual(power.enableCalls, 1)  // timer 가 또 forceOff 호출하면 안 됨
    }
}
