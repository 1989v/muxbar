import Foundation
import MuxLogging

@MainActor
public final class ClosedLidStore: ObservableObject {
    public static let sessionName = "_muxbar-closed-lid"
    public static let caffeinateCommand = "caffeinate -is"

    public enum State: Equatable {
        case off
        case on(expiresAt: Date?)  // nil = infinite

        public var isOn: Bool { if case .off = self { return false } else { return true } }
    }

    public protocol PowerController: Sendable {
        func disableSystemSleep() async throws
        func enableSystemSleep() async throws
    }

    @Published public private(set) var state: State = .off
    @Published public private(set) var isToggling: Bool = false

    private let power: any PowerController
    private let logger = MuxLogging.logger("Core.ClosedLidStore")

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
    }

    public func forceOff(sessionProvider: any SessionProvider) async {
        guard state.isOn else { return }
        isToggling = true
        defer { isToggling = false }

        do {
            try await power.enableSystemSleep()
        } catch {
            logger.warning("enableSystemSleep failed: \(error.localizedDescription)")
        }

        do {
            try await sessionProvider.kill(sessionName: Self.sessionName)
        } catch {
            logger.warning("kill closed-lid session failed: \(error.localizedDescription)")
        }

        state = .off
    }
}
