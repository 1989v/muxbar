import Foundation
import Combine
import MuxLogging

@MainActor
public final class SessionStore: ObservableObject {
    @Published public private(set) var sessions: [TmuxSession] = []
    @Published public private(set) var connectionState: ConnectionState = .disconnected
    @Published public private(set) var lastError: String?

    private let logger = MuxLogging.logger("Core.SessionStore")

    public init() {}

    public var userVisibleSessions: [TmuxSession] {
        sessions.filter { !$0.isInternal }
    }

    public var awakeSessionExists: Bool {
        sessions.contains { $0.id == "_muxbar-awake" }
    }

    /// 외부에서 주입 (테스트용 / 실행 시 TmuxKit 연결)
    public func apply(sessions: [TmuxSession]) {
        self.sessions = sessions
    }

    public func apply(connectionState: ConnectionState) {
        self.connectionState = connectionState
    }

    public func apply(error: String?) {
        self.lastError = error
        if let error {
            logger.error("\(error)")
        }
    }
}
