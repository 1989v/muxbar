import XCTest
@testable import Core

final class FakeSessionProvider: SessionProvider {
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

final class FakePowerController: ClosedLidStore.PowerController {
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
}
