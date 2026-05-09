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
        func enableSystemSleep() async throws
    }

    @Published public private(set) var state: State = .off
    @Published public private(set) var isToggling: Bool = false

    private let power: any PowerController
    private let preferences: ClosedLidPreferences
    private let logger = MuxLogging.logger("Core.ClosedLidStore")
    private var expirationTask: Task<Void, Never>?
    private let acMonitor: PowerSourceMonitor
    private let lidMonitor: LidStateMonitor
    private weak var lastSessionProvider: AnyObject?

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

    public func turnOn(duration: Duration?, sessionProvider: any SessionProvider) async {
        guard !state.isOn, !isToggling else { return }
        isToggling = true
        defer { isToggling = false }

        do {
            try await power.disableSystemSleep()
        } catch {
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
    /// 그걸로 forceOff, 없으면 pmset 만 복원.
    private func forceOffViaTrigger() async {
        if let provider = lastSessionProvider as? (any SessionProvider) {
            await forceOff(sessionProvider: provider)
            return
        }
        // sessionProvider 가 deallocate → pmset 만 복원, state .off.
        guard state.isOn, !isToggling else { return }
        isToggling = true
        defer { isToggling = false }

        try? await power.enableSystemSleep()
        acMonitor.stop()
        lidMonitor.stop()
        expirationTask?.cancel()
        expirationTask = nil
        state = .off
        lastSessionProvider = nil
    }

    public func forceOff(sessionProvider: any SessionProvider) async {
        guard state.isOn, !isToggling else { return }
        isToggling = true
        defer { isToggling = false }

        expirationTask?.cancel()
        expirationTask = nil
        acMonitor.stop()
        lidMonitor.stop()

        do {
            try await power.enableSystemSleep()
        } catch PowerControl.Error.userCancelled {
            logger.warning("enableSystemSleep cancelled by user — aborting forceOff, monitors 재무장")
            // 사용자 cancel 은 "OFF 안 함" 의도이지 자동해제 비활성 의도가 아님 → AC/lid monitor 재구독.
            // timer 는 expiresAt 잔여 계산 복잡 + 사용 빈도 낮아 후속 enhancement 로 미루고 여기선 미재무장.
            acMonitor.onACDisconnect { [weak self] in Task { await self?.forceOffViaTrigger() } }
            lidMonitor.onLidOpen     { [weak self] in Task { await self?.forceOffViaTrigger() } }
            return
        } catch {
            logger.warning("enableSystemSleep failed: \(error.localizedDescription)")
            // 비-cancel 실패: kill 진행 + state .off (UI 가 stuck 되지 않도록)
        }

        do {
            try await sessionProvider.kill(sessionName: Self.sessionName)
        } catch {
            logger.warning("kill closed-lid session failed: \(error.localizedDescription)")
        }

        state = .off
        lastSessionProvider = nil
    }
}
