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

    /// SessionStore 의 awake 세션 존재 여부 참조.
    public func isAwake(in store: SessionStore) -> Bool {
        store.awakeSessionExists
    }

    /// 토글 수행. SessionStore 가 awake 세션 변경을 감지해 UI 자동 갱신.
    public func toggle(in store: SessionStore, via provider: any SessionProvider) async {
        isToggling = true
        defer { isToggling = false }

        if store.awakeSessionExists {
            await store.kill(
                TmuxSession(id: Self.awakeSessionName, isAttached: false, windowCount: 1,
                            createdAt: .now, lastActivityAt: .now, workingDirectory: nil),
                via: provider
            )
            logger.info("Keep Awake OFF")
        } else {
            let cmd = "caffeinate \(flags.cliArgs)"
            await store.createSession(name: Self.awakeSessionName, command: cmd, via: provider)
            logger.info("Keep Awake ON (caffeinate \(flags.cliArgs))")
        }
    }
}
