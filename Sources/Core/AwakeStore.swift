import Foundation
import MuxLogging

@MainActor
public final class AwakeStore: ObservableObject {
    public static let awakeSessionName = "_muxbar-awake"

    @Published public private(set) var flags: CaffeinateFlags = .default
    @Published public private(set) var isToggling: Bool = false

    private let logger = MuxLogging.logger("Core.AwakeStore")

    public init(flags: CaffeinateFlags = .default) {
        self.flags = flags
    }

    public func setFlags(_ new: CaffeinateFlags) {
        guard new.isValid else { return }
        self.flags = new
    }

    /// caffeinate 활성 여부 — tmux 세션(muxbar 관리 + 외부) OR 시스템 프로세스.
    public func isAwake(in store: SessionStore) -> Bool {
        store.caffeinateStatus.isActive
    }

    /// caffeinate 소스 표시용: "muxbar", "external", "none"
    public func source(in store: SessionStore) -> Source {
        let status = store.caffeinateStatus
        guard status.isActive else { return .none }
        let hasMuxbar = status.tmuxSessions.contains(Self.awakeSessionName)
        let hasExternal = status.tmuxSessions.contains { $0 != Self.awakeSessionName } || status.systemActive
        if hasMuxbar && hasExternal { return .both }
        if hasMuxbar { return .muxbar }
        return .external
    }

    public enum Source: Sendable, Equatable {
        case none
        case muxbar
        case external
        case both

        public var label: String {
            switch self {
            case .none: return "OFF"
            case .muxbar: return "ON"
            case .external: return "ON (external)"
            case .both: return "ON (muxbar + external)"
            }
        }
    }

    /// 토글 수행.
    /// - ON → OFF: **모든 caffeinate tmux 세션 + 시스템 프로세스** 종료
    /// - OFF → ON: `_muxbar-awake` 세션 생성
    public func toggle(in store: SessionStore, via provider: any SessionProvider) async {
        isToggling = true
        defer { isToggling = false }

        let status = store.caffeinateStatus

        if status.isActive {
            for sessionName in status.tmuxSessions {
                do {
                    try await provider.kill(sessionName: sessionName)
                } catch {
                    logger.warning("kill '\(sessionName)' failed: \(error.localizedDescription)")
                }
            }
            if status.systemActive {
                SystemCaffeinateDetector.pkillAll()
            }
        } else {
            let cmd = "caffeinate \(flags.cliArgs)"
            await store.createSession(name: Self.awakeSessionName, command: cmd, via: provider)
        }

        // 상태 재갱신 (tmux 이벤트 기다릴 필요 없이 즉시 반영)
        try? await Task.sleep(nanoseconds: 300_000_000)
        await store.refreshCaffeinate(from: provider)
    }
}
