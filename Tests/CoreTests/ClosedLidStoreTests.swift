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
    var lastAllowPrompt: Bool?
    var shouldThrowOnDisable: Error?
    var shouldThrowOnEnable: Error?
    /// allowPrompt=false 일 때만 던질 에러. nil 이면 shouldThrowOnEnable 사용.
    var shouldThrowOnEnableSilent: Error?
    /// isSystemSleepDisabled() 반환값. reconcile 게이트 테스트용.
    var systemSleepDisabled = false

    func disableSystemSleep() async throws {
        disableCalls += 1
        if let e = shouldThrowOnDisable { throw e }
    }
    func enableSystemSleep(allowPrompt: Bool) async throws {
        enableCalls += 1
        lastAllowPrompt = allowPrompt
        if !allowPrompt, let e = shouldThrowOnEnableSilent { throw e }
        if let e = shouldThrowOnEnable { throw e }
    }
    func isSystemSleepDisabled() async -> Bool { systemSleepDisabled }
}

final class FakePowerSourceMonitor: PowerSourceMonitor, @unchecked Sendable {
    var startedHandler: (@MainActor () -> Void)?
    var stopped = false

    @MainActor
    func onACDisconnect(_ handler: @escaping @MainActor () -> Void) {
        startedHandler = handler
    }
    @MainActor
    func stop() { stopped = true; startedHandler = nil }

    @MainActor
    func fire() { startedHandler?() }
}

final class FakeLidStateMonitor: LidStateMonitor, @unchecked Sendable {
    var startedHandler: (@MainActor () -> Void)?
    var stopped = false

    @MainActor
    func onLidOpen(_ handler: @escaping @MainActor () -> Void) {
        startedHandler = handler
    }
    @MainActor
    func stop() { stopped = true; startedHandler = nil }

    @MainActor
    func fire() { startedHandler?() }
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

    func test_forceOff_manual_userCancelled_stateStaysOn() async {
        let power = FakePowerController()
        let provider = FakeSessionProvider()
        let store = ClosedLidStore(power: power)
        await store.turnOn(duration: nil, sessionProvider: provider)

        power.shouldThrowOnEnable = PowerControl.Error.userCancelled
        await store.forceOff(sessionProvider: provider, trigger: .manual)

        XCTAssertEqual(power.enableCalls, 1)
        XCTAssertEqual(power.lastAllowPrompt, true)  // manual → prompt 허용
        XCTAssertEqual(store.state, .on(expiresAt: nil))  // manual cancel: state 유지
        XCTAssertEqual(provider.killedSessions.count, 0)  // kill 도 진행 안 됨
    }

    /// auto trigger (timer/AC/lid) 에서 NOPASSWD 미설정 → .passwordRequired 던져도
    /// state 는 .off 로 정리되고 caffeinate kill + onPmsetRestoreNeeded 콜백 발화.
    func test_forceOff_auto_passwordRequired_stateGoesOffAndFiresCallback() async {
        let power = FakePowerController()
        let provider = FakeSessionProvider()
        let store = ClosedLidStore(power: power)
        await store.turnOn(duration: nil, sessionProvider: provider)

        var callbackFired = false
        store.onPmsetRestoreNeeded = { callbackFired = true }
        power.shouldThrowOnEnableSilent = PowerControl.Error.passwordRequired

        await store.forceOff(sessionProvider: provider, trigger: .auto)

        XCTAssertEqual(power.enableCalls, 1)
        XCTAssertEqual(power.lastAllowPrompt, false)  // auto → silent only
        XCTAssertEqual(store.state, .off)
        XCTAssertEqual(provider.killedSessions, ["_muxbar-closed-lid"])
        XCTAssertTrue(callbackFired)
    }

    // MARK: - alsoStopKeepAwakeOnEnd 콜백

    /// turnOn 시점에 alsoStopKeepAwakeOnEnd=true 로 켠 뒤, manual forceOff 가
    /// 정상적으로 .off 로 갈 때 onEndShouldStopKeepAwake 콜백이 한 번 발화.
    func test_manualForceOff_alsoStopKeepAwake_firesCallback() async {
        let power = FakePowerController()
        let provider = FakeSessionProvider()
        let store = ClosedLidStore(power: power)

        var callbackFires = 0
        store.onEndShouldStopKeepAwake = { callbackFires += 1 }

        await store.turnOn(duration: nil, alsoStopKeepAwakeOnEnd: true, sessionProvider: provider)
        await store.forceOff(sessionProvider: provider, trigger: .manual)

        XCTAssertEqual(store.state, .off)
        XCTAssertEqual(callbackFires, 1)
    }

    /// alsoStopKeepAwakeOnEnd=false 로 시작했으면 종료 시 콜백 발화하면 안 됨.
    func test_manualForceOff_withoutAlsoStop_doesNotFireCallback() async {
        let power = FakePowerController()
        let provider = FakeSessionProvider()
        let store = ClosedLidStore(power: power)

        var callbackFired = false
        store.onEndShouldStopKeepAwake = { callbackFired = true }

        await store.turnOn(duration: nil, alsoStopKeepAwakeOnEnd: false, sessionProvider: provider)
        await store.forceOff(sessionProvider: provider, trigger: .manual)

        XCTAssertEqual(store.state, .off)
        XCTAssertFalse(callbackFired)
    }

    /// 타이머 만료 (auto trigger) 경로에서도 alsoStopKeepAwakeOnEnd=true 면 콜백 발화.
    func test_timerExpiry_alsoStopKeepAwake_firesCallback() async throws {
        let power = FakePowerController()
        let provider = FakeSessionProvider()
        let store = ClosedLidStore(power: power)

        var callbackFires = 0
        store.onEndShouldStopKeepAwake = { callbackFires += 1 }

        await store.turnOn(duration: .milliseconds(100), alsoStopKeepAwakeOnEnd: true, sessionProvider: provider)
        try await Task.sleep(nanoseconds: 250_000_000)

        XCTAssertEqual(store.state, .off)
        XCTAssertEqual(callbackFires, 1)
    }

    /// manual cancel 로 OFF 안 됐을 때는(state 가 .on 유지) 콜백 발화하면 안 됨.
    func test_manualForceOff_userCancelled_doesNotFireCallback() async {
        let power = FakePowerController()
        let provider = FakeSessionProvider()
        let store = ClosedLidStore(power: power)

        var callbackFired = false
        store.onEndShouldStopKeepAwake = { callbackFired = true }

        await store.turnOn(duration: nil, alsoStopKeepAwakeOnEnd: true, sessionProvider: provider)
        power.shouldThrowOnEnable = PowerControl.Error.userCancelled
        await store.forceOff(sessionProvider: provider, trigger: .manual)

        XCTAssertEqual(store.state, .on(expiresAt: nil))  // cancel → ON 유지
        XCTAssertFalse(callbackFired)  // OFF 안 됐으니 콜백도 X
    }

    /// 자동 expiration timer 가 발화하는 forceOffViaTrigger 경로에서도 동일하게
    /// password 없이 .off 로 가는지 검증.
    func test_timerExpiry_passwordRequired_stateGoesOff() async throws {
        let power = FakePowerController()
        let provider = FakeSessionProvider()
        let store = ClosedLidStore(power: power)
        power.shouldThrowOnEnableSilent = PowerControl.Error.passwordRequired
        var callbackFired = false
        store.onPmsetRestoreNeeded = { callbackFired = true }

        await store.turnOn(duration: .milliseconds(100), sessionProvider: provider)
        XCTAssertTrue(store.state.isOn)

        try await Task.sleep(nanoseconds: 250_000_000)

        XCTAssertEqual(store.state, .off)
        XCTAssertEqual(power.lastAllowPrompt, false)
        XCTAssertTrue(callbackFired)
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

    func test_turnOn_subscribesACAndLidMonitors() async {
        let power = FakePowerController()
        let provider = FakeSessionProvider()
        let acMon = FakePowerSourceMonitor()
        let lidMon = FakeLidStateMonitor()
        let store = ClosedLidStore(power: power, acMonitor: acMon, lidMonitor: lidMon)

        await store.turnOn(duration: nil, sessionProvider: provider)

        XCTAssertNotNil(acMon.startedHandler)
        XCTAssertNotNil(lidMon.startedHandler)
    }

    func test_acDisconnect_triggersForceOff() async throws {
        let power = FakePowerController()
        let provider = FakeSessionProvider()
        let acMon = FakePowerSourceMonitor()
        let lidMon = FakeLidStateMonitor()
        let store = ClosedLidStore(power: power, acMonitor: acMon, lidMonitor: lidMon)

        await store.turnOn(duration: nil, sessionProvider: provider)
        acMon.fire()
        try await Task.sleep(nanoseconds: 100_000_000)

        XCTAssertEqual(store.state, .off)
    }

    func test_lidOpen_triggersForceOff() async throws {
        let power = FakePowerController()
        let provider = FakeSessionProvider()
        let acMon = FakePowerSourceMonitor()
        let lidMon = FakeLidStateMonitor()
        let store = ClosedLidStore(power: power, acMonitor: acMon, lidMonitor: lidMon)

        await store.turnOn(duration: nil, sessionProvider: provider)
        lidMon.fire()
        try await Task.sleep(nanoseconds: 100_000_000)

        XCTAssertEqual(store.state, .off)
    }

    func test_forceOff_manual_userCancelled_acMonitorRemainsArmed() async throws {
        let power = FakePowerController()
        let provider = FakeSessionProvider()
        let acMon = FakePowerSourceMonitor()
        let lidMon = FakeLidStateMonitor()
        let store = ClosedLidStore(power: power, acMonitor: acMon, lidMonitor: lidMon)
        await store.turnOn(duration: nil, sessionProvider: provider)

        power.shouldThrowOnEnable = PowerControl.Error.userCancelled
        await store.forceOff(sessionProvider: provider, trigger: .manual)

        // monitor 재무장 확인 — handler 다시 등록됨
        XCTAssertNotNil(acMon.startedHandler)
        XCTAssertNotNil(lidMon.startedHandler)
        // state 는 ON 유지
        XCTAssertEqual(store.state, .on(expiresAt: nil))

        // 재무장된 AC monitor 가 fire 하면 다시 forceOff 시도 (이번엔 power.shouldThrowOnEnable 그대로
        // userCancelled 라 또 cancel — 무한 루프 같지만 forceOff 가 내부 guard 로 멈춤)
        // → 검증은 monitor 재무장만으로 충분.
    }

    // MARK: - sleepDisabledByUs 마커 & launch reconcile (stranded disablesleep self-heal)

    private func makeIsolatedPrefs() -> ClosedLidPreferences {
        let d = UserDefaults(suiteName: "test.closedlid.\(UUID().uuidString)")!
        return ClosedLidPreferences(defaults: d)
    }

    func test_turnOn_setsSleepDisabledMarker() async {
        let power = FakePowerController()
        let prefs = makeIsolatedPrefs()
        let store = ClosedLidStore(power: power, preferences: prefs)

        await store.turnOn(duration: nil, sessionProvider: FakeSessionProvider())

        XCTAssertTrue(prefs.sleepDisabledByUs)
    }

    func test_turnOn_disableFails_doesNotSetMarker() async {
        let power = FakePowerController()
        power.shouldThrowOnDisable = PowerControl.Error.userCancelled
        let prefs = makeIsolatedPrefs()
        let store = ClosedLidStore(power: power, preferences: prefs)

        await store.turnOn(duration: nil, sessionProvider: FakeSessionProvider())

        XCTAssertFalse(prefs.sleepDisabledByUs)
    }

    func test_forceOff_success_clearsMarker() async {
        let power = FakePowerController()
        let prefs = makeIsolatedPrefs()
        let provider = FakeSessionProvider()
        let store = ClosedLidStore(power: power, preferences: prefs)
        await store.turnOn(duration: nil, sessionProvider: provider)
        XCTAssertTrue(prefs.sleepDisabledByUs)

        await store.forceOff(sessionProvider: provider, trigger: .manual)

        XCTAssertFalse(prefs.sleepDisabledByUs)
    }

    /// auto trigger 에서 NOPASSWD 미설정으로 복원 실패하면 마커는 true 로 유지돼야 함 — 다음 실행 self-heal 근거.
    func test_forceOff_auto_passwordRequired_keepsMarker() async {
        let power = FakePowerController()
        power.shouldThrowOnEnableSilent = PowerControl.Error.passwordRequired
        let prefs = makeIsolatedPrefs()
        let provider = FakeSessionProvider()
        let store = ClosedLidStore(power: power, preferences: prefs)
        await store.turnOn(duration: nil, sessionProvider: provider)

        await store.forceOff(sessionProvider: provider, trigger: .auto)

        XCTAssertEqual(store.state, .off)
        XCTAssertTrue(prefs.sleepDisabledByUs)  // pmset stranded → 마커 유지
    }

    /// 마커 true + 실제 SleepDisabled==1 → reconcile 이 prompt 허용 복원 호출 후 마커 해제.
    func test_reconcile_strandedDisabled_restoresAndClearsMarker() async {
        let power = FakePowerController()
        power.systemSleepDisabled = true
        let prefs = makeIsolatedPrefs()
        prefs.sleepDisabledByUs = true
        let store = ClosedLidStore(power: power, preferences: prefs)

        await store.reconcileStrandedSleepOnLaunch()

        XCTAssertEqual(power.enableCalls, 1)
        XCTAssertEqual(power.lastAllowPrompt, true)  // launch → prompt 허용
        XCTAssertFalse(prefs.sleepDisabledByUs)
    }

    /// 마커 false 면 reconcile 이 아무것도 안 함(불필요한 prompt 방지).
    func test_reconcile_noMarker_noOp() async {
        let power = FakePowerController()
        power.systemSleepDisabled = true  // 시스템은 disabled 라도
        let prefs = makeIsolatedPrefs()   // 마커가 false 면
        let store = ClosedLidStore(power: power, preferences: prefs)

        await store.reconcileStrandedSleepOnLaunch()

        XCTAssertEqual(power.enableCalls, 0)
    }

    /// 마커 true 인데 사용자가 이미 수동 복원(SleepDisabled==0) → prompt 없이 마커만 정리.
    func test_reconcile_markerStaleButAlreadyEnabled_clearsMarkerNoPrompt() async {
        let power = FakePowerController()
        power.systemSleepDisabled = false
        let prefs = makeIsolatedPrefs()
        prefs.sleepDisabledByUs = true
        let store = ClosedLidStore(power: power, preferences: prefs)

        await store.reconcileStrandedSleepOnLaunch()

        XCTAssertEqual(power.enableCalls, 0)        // 불필요한 password prompt 없음
        XCTAssertFalse(prefs.sleepDisabledByUs)     // 마커는 정리
    }

    /// reconcile 복원이 실패하면 마커 유지 + onPmsetRestoreNeeded 발화.
    func test_reconcile_restoreFails_keepsMarkerAndFiresCallback() async {
        let power = FakePowerController()
        power.systemSleepDisabled = true
        power.shouldThrowOnEnable = PowerControl.Error.userCancelled
        let prefs = makeIsolatedPrefs()
        prefs.sleepDisabledByUs = true
        let store = ClosedLidStore(power: power, preferences: prefs)
        var fired = false
        store.onPmsetRestoreNeeded = { fired = true }

        await store.reconcileStrandedSleepOnLaunch()

        XCTAssertTrue(prefs.sleepDisabledByUs)
        XCTAssertTrue(fired)
    }

    func test_forceOff_stopsBothMonitors() async {
        let power = FakePowerController()
        let provider = FakeSessionProvider()
        let acMon = FakePowerSourceMonitor()
        let lidMon = FakeLidStateMonitor()
        let store = ClosedLidStore(power: power, acMonitor: acMon, lidMonitor: lidMon)

        await store.turnOn(duration: nil, sessionProvider: provider)
        await store.forceOff(sessionProvider: provider)

        XCTAssertTrue(acMon.stopped)
        XCTAssertTrue(lidMon.stopped)
    }
}
