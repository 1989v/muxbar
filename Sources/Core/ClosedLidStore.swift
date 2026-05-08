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

    public init(power: any PowerController) {
        self.power = power
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

        let expiresAt: Date? = duration.map { d in
            Date().addingTimeInterval(TimeInterval(d.components.seconds))
        }
        state = .on(expiresAt: expiresAt)

        if let duration {
            expirationTask = Task { [weak self, sessionProvider] in
                let nanos = UInt64(duration.components.seconds) * 1_000_000_000
                    // attoseconds(10⁻¹⁸ s) ÷ 1e9 = nanoseconds (sub-second 분량).
                    + UInt64(duration.components.attoseconds / 1_000_000_000)
                do {
                    try await Task.sleep(nanoseconds: nanos)
                } catch {
                    return  // cancelled
                }
                guard let self else { return }
                await self.forceOff(sessionProvider: sessionProvider)
            }
        }
    }

    public func forceOff(sessionProvider: any SessionProvider) async {
        guard state.isOn, !isToggling else { return }
        isToggling = true
        defer { isToggling = false }

        expirationTask?.cancel()
        expirationTask = nil
        // TODO(Task5): userCancelled 경로에서 timer 가 죽은 채 state .on 으로 남으면
        // 자동 만료가 더 이상 발화하지 않음. Task 5 의 4중 자동해제 통합과 함께 재무장 처리.

        do {
            try await power.enableSystemSleep()
        } catch PowerControl.Error.userCancelled {
            logger.warning("enableSystemSleep cancelled by user — aborting forceOff (state stays ON)")
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
    }
}
