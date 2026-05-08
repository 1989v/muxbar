import Foundation
import MuxLogging

@MainActor
public final class ClosedLidStore: ObservableObject {
    public static let sessionName = "_muxbar-closed-lid"
    public static let caffeinateCommand = "caffeinate -is"

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
    private let logger = MuxLogging.logger("Core.ClosedLidStore")
    private var expirationTask: Task<Void, Never>?
    private let acMonitor: PowerSourceMonitor
    private let lidMonitor: LidStateMonitor
    private weak var lastSessionProvider: AnyObject?

    public init(
        power: any PowerController,
        acMonitor: PowerSourceMonitor = IOKitPowerSourceMonitor(),
        lidMonitor: LidStateMonitor = IOKitLidStateMonitor()
    ) {
        self.power = power
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
                name: Self.sessionName, command: Self.caffeinateCommand
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
        try? await power.enableSystemSleep()
        state = .off
        acMonitor.stop()
        lidMonitor.stop()
        expirationTask?.cancel()
        expirationTask = nil
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
            logger.warning("enableSystemSleep cancelled by user — aborting forceOff (state stays ON)")
            // 주의: monitors/timer 가 모두 stop 됐음. 자동 OFF 가 지금부터 발화 안 됨.
            // Spec 의도와 부합 (사용자가 명시적 cancel). 단 향후 enhancement 로 monitor/timer
            // 재무장 검토 가능.
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
