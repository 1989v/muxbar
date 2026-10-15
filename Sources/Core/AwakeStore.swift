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

    /// caffeinate 활성 여부 — muxbar 세션 OR 외부 tmux 세션 OR tmux 밖 프로세스.
    /// Closed-lid 의 caffeinate 는 세지 않는다.
    public func isAwake(in store: SessionStore) -> Bool {
        store.awakeSessionExists || store.caffeinateStatus.isActive
    }

    /// caffeinate 소스 표시용: "muxbar", "external", "none"
    public func source(in store: SessionStore) -> Source {
        let status = store.caffeinateStatus
        guard isAwake(in: store) else { return .none }
        let hasMuxbar = store.awakeSessionExists || status.tmuxSessions.contains(Self.awakeSessionName)
        let hasExternal = status.keepAwakeSessions.contains { $0 != Self.awakeSessionName } || status.systemActive
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
    /// - ON → OFF: **caffeinate tmux 세션(Closed-lid 제외) + tmux 밖 caffeinate** 종료
    /// - OFF → ON: `_muxbar-awake` 세션 생성
    public func toggle(in store: SessionStore, via provider: any SessionProvider) async {
        isToggling = true
        defer { isToggling = false }

        let status = store.caffeinateStatus

        if isAwake(in: store) {
            var targets = Set(status.keepAwakeSessions)
            if store.awakeSessionExists { targets.insert(Self.awakeSessionName) }
            for sessionName in targets.sorted() {
                do {
                    try await provider.kill(sessionName: sessionName)
                } catch {
                    logger.warning("kill '\(sessionName)' failed: \(error.localizedDescription)")
                }
            }
            SystemCaffeinateDetector.terminate(status.externalPids)
        } else {
            let cmd = "caffeinate \(flags.cliArgs)"
            await store.createSession(name: Self.awakeSessionName, command: cmd, via: provider)
        }

        // 상태 재갱신 (tmux 이벤트 기다릴 필요 없이 즉시 반영)
        try? await Task.sleep(nanoseconds: 300_000_000)
        await store.refreshCaffeinate(from: provider)
    }
}
