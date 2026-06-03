import Foundation
import MuxLogging

@MainActor
public final class ClosedLidStore: ObservableObject {
    public static let sessionName = "_muxbar-closed-lid"

    public enum State: Equatable {
        case off
        case on(expiresAt: Date?)  // nil = infinite

        public var isOn: Bool { self != .off }
    }

    public protocol PowerController: Sendable {
        func disableSystemSleep() async throws
        func enableSystemSleep(allowPrompt: Bool) async throws
        /// 현재 시스템 슬립이 꺼져있는지(`pmset SleepDisabled==1`). launch reconcile 게이트용.
        func isSystemSleepDisabled() async -> Bool
    }

    /// forceOff 호출 컨텍스트. password dialog 노출 여부와 cancel 처리 분기에 사용.
    public enum Trigger {
        /// 사용자가 직접 OFF 토글 — dialog OK, cancel 시 state .on 유지.
        case manual
        /// timer 만료 / AC 분리 / lid open — silent only, 실패해도 state .off 로 정리.
        case auto
    }

    @Published public private(set) var state: State = .off
    @Published public private(set) var isToggling: Bool = false

    /// auto trigger 에서 pmset 복원 실패(NOPASSWD 미설정) 시 호출. UI 측 notification 발송용.
    public var onPmsetRestoreNeeded: (@MainActor () -> Void)?

    /// closed-lid 종료 시점에 Keep Awake 도 같이 OFF 시켜야 할 때 호출.
    /// turnOn 시점에 사용자가 체크한 의도가 발화 조건 — trigger 종류(manual/timer/AC/lid)와 무관.
    public var onEndShouldStopKeepAwake: (@MainActor () -> Void)?

    private let power: any PowerController
    private let preferences: ClosedLidPreferences
    private let logger = MuxLogging.logger("Core.ClosedLidStore")
    private var expirationTask: Task<Void, Never>?
    private let acMonitor: PowerSourceMonitor
    private let lidMonitor: LidStateMonitor
    private weak var lastSessionProvider: AnyObject?
    /// 이번 turnOn 세션이 끝날 때 Keep Awake 도 같이 OFF 시킬지. turnOn 시점 결정값.
    private var alsoStopKeepAwakeOnEnd: Bool = false

    public init(
        power: any PowerController,
        preferences: ClosedLidPreferences = ClosedLidPreferences(),
        acMonitor: PowerSourceMonitor = IOKitPowerSourceMonitor(),
        lidMonitor: LidStateMonitor = IOKitLidStateMonitor()
    ) {
        self.power = power
        self.preferences = preferences
        self.acMonitor = acMonitor
        self.lidMonitor = lidMonitor
    }

    public func turnOn(
        duration: Duration?,
        alsoStopKeepAwakeOnEnd: Bool = false,
        sessionProvider: any SessionProvider
    ) async {
        guard !state.isOn, !isToggling else { return }
        isToggling = true
        defer { isToggling = false }

        // 복원 책임 마커를 pmset 호출 *전에* optimistic 으로 ON — disableSystemSleep 성공 후
        // 마커 write 전 크래시 윈도우를 닫는다. false-positive(적용 안 됐는데 마커 true)는
        // reconcile 이 실제 pmset 값으로 게이트하므로 무해(prompt 없이 마커만 정리).
        preferences.sleepDisabledByUs = true
        do {
            try await power.disableSystemSleep()
        } catch {
            preferences.sleepDisabledByUs = false  // 적용 실패 → 마커 롤백
            logger.warning("disableSystemSleep failed: \(error.localizedDescription)")
            return
        }

        do {
            try await sessionProvider.createSession(
                name: Self.sessionName, command: preferences.caffeinateCommand()
            )
        } catch {
            logger.warning("caffeinate session create failed (pmset stays on): \(error.localizedDescription)")
            // pmset 은 이미 적용 → state 는 ON 유지
        }

        let expiresAt: Date? = duration.map { Date().addingTimeInterval(TimeInterval($0.components.seconds)) }
        state = .on(expiresAt: expiresAt)
        lastSessionProvider = sessionProvider as AnyObject
        self.alsoStopKeepAwakeOnEnd = alsoStopKeepAwakeOnEnd

        if let duration {
            expirationTask = Task { [weak self] in
                let nanos = UInt64(duration.components.seconds) * 1_000_000_000
                    // attoseconds(10⁻¹⁸ s) ÷ 1e9 = nanoseconds (sub-second 분량).
                    + UInt64(duration.components.attoseconds / 1_000_000_000)
                do {
                    try await Task.sleep(nanoseconds: nanos)
                } catch {
                    return  // cancelled
                }
                await self?.forceOffViaTrigger()
            }
        }

        acMonitor.onACDisconnect { [weak self] in
            Task { await self?.forceOffViaTrigger() }
        }
        lidMonitor.onLidOpen { [weak self] in
            Task { await self?.forceOffViaTrigger() }
        }
    }

    /// 자동해제 트리거 (timer/AC/lid) 공통 진입점. 마지막 sessionProvider 가 살아있으면
    /// 그걸로 forceOff, 없으면 pmset 만 silent 복원.
    private func forceOffViaTrigger() async {
        if let provider = lastSessionProvider as? (any SessionProvider) {
            await forceOff(sessionProvider: provider, trigger: .auto)
            return
        }
        // sessionProvider 가 deallocate → pmset 만 복원, state .off.
        guard state.isOn, !isToggling else { return }
        isToggling = true
        defer { isToggling = false }

        do {
            try await power.enableSystemSleep(allowPrompt: false)
            preferences.sleepDisabledByUs = false  // 복원 성공 → 마커 해제
        } catch {
            // NOPASSWD 미설정이면 .passwordRequired — pmset 은 stranded, 마커 유지(다음 실행 self-heal).
            onPmsetRestoreNeeded?()
        }
        acMonitor.stop()
        lidMonitor.stop()
        expirationTask?.cancel()
        expirationTask = nil
        finalizeOff()
    }

    /// state 를 .off 로 전이하면서 turnOn 시점 의도(alsoStopKeepAwakeOnEnd)를 발화한다.
    /// state 가 실제로 .off 로 가는 모든 경로의 마지막 단계에서만 호출 — manual cancel 같은
    /// "OFF 안 함" 경로에서는 호출하지 말 것.
    private func finalizeOff() {
        let shouldStopKeepAwake = alsoStopKeepAwakeOnEnd
        alsoStopKeepAwakeOnEnd = false
        state = .off
        lastSessionProvider = nil
        if shouldStopKeepAwake { onEndShouldStopKeepAwake?() }
    }

    /// 앱 시작 시 1회 호출. 이전 세션이 크래시/강제종료/auto-trigger 복원실패로 `disablesleep 1` 을
    /// 남긴 채 끝났으면(마커 true + state .off + 실제 SleepDisabled==1) 시스템 슬립을 복원한다.
    /// terminate 훅만으로는 못 잡는 비정상 종료 경로의 self-heal.
    public func reconcileStrandedSleepOnLaunch() async {
        guard preferences.sleepDisabledByUs, !state.isOn, !isToggling else { return }
        isToggling = true
        defer { isToggling = false }

        // 사용자가 이미 수동 복원(pmset disablesleep 0)했으면 prompt 없이 마커만 정리.
        guard await power.isSystemSleepDisabled() else {
            preferences.sleepDisabledByUs = false
            logger.info("reconcile: marker stale but SleepDisabled already 0 — marker cleared")
            return
        }

        logger.critical("reconcile: stranded SleepDisabled=1 from previous session — restoring")
        do {
            try await power.enableSystemSleep(allowPrompt: true)
            preferences.sleepDisabledByUs = false
        } catch {
            // 복원 실패(취소/비번필요) — 마커 유지하고 사용자에게 알림.
            logger.warning("reconcile: restore failed: \(error.localizedDescription)")
            onPmsetRestoreNeeded?()
        }
    }

    public func forceOff(sessionProvider: any SessionProvider, trigger: Trigger = .manual) async {
        guard state.isOn, !isToggling else { return }
        isToggling = true
        defer { isToggling = false }

        expirationTask?.cancel()
        expirationTask = nil
        acMonitor.stop()
        lidMonitor.stop()

        let allowPrompt = (trigger == .manual)
        do {
            try await power.enableSystemSleep(allowPrompt: allowPrompt)
            preferences.sleepDisabledByUs = false  // 복원 성공 → 마커 해제
        } catch PowerControl.Error.userCancelled {
            logger.warning("enableSystemSleep cancelled by user — aborting forceOff, monitors 재무장")
            // manual cancel 만 도달 (auto 는 prompt 없어 .userCancelled 안 남). "OFF 안 함" 의도 →
            // state .on 유지 + AC/lid monitor 재구독. timer 는 expiresAt 잔여 계산 복잡 + 사용 빈도 낮아
            // 후속 enhancement 로 미루고 여기선 미재무장.
            acMonitor.onACDisconnect { [weak self] in Task { await self?.forceOffViaTrigger() } }
            lidMonitor.onLidOpen     { [weak self] in Task { await self?.forceOffViaTrigger() } }
            return
        } catch PowerControl.Error.passwordRequired {
            // auto trigger + NOPASSWD 미설정. pmset 은 stale 인 채로 두고 caffeinate 만 kill,
            // state .off 로 정리. UI 가 사용자에게 알림 발송.
            logger.warning("auto trigger: pmset 복원 비밀번호 필요 — caffeinate kill 후 state .off")
            onPmsetRestoreNeeded?()
        } catch {
            logger.warning("enableSystemSleep failed: \(error.localizedDescription)")
            // 비-cancel 실패: kill 진행 + state .off (UI 가 stuck 되지 않도록)
        }

        do {
            try await sessionProvider.kill(sessionName: Self.sessionName)
        } catch {
            logger.warning("kill closed-lid session failed: \(error.localizedDescription)")
        }

        finalizeOff()
    }
}
