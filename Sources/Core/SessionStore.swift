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

    private var bindingTask: Task<Void, Never>?

    public func bind(to provider: any SessionProvider) {
        bindingTask?.cancel()
        bindingTask = Task { [weak self] in
            await self?.initialLoad(from: provider)
            for await event in provider.events {
                guard let self else { break }
                switch event {
                case .sessionsChanged:
                    await self.refresh(from: provider)
                case .connectionLost:
                    self.apply(connectionState: .disconnected)
                case .unknown:
                    break
                }
            }
        }
    }

    public func unbind() {
        bindingTask?.cancel()
        bindingTask = nil
    }

    private func initialLoad(from provider: any SessionProvider) async {
        do {
            self.connectionState = .connecting(attempt: 1)
            let fetched = try await provider.listSessions()
            self.sessions = fetched
            self.connectionState = .connected
        } catch {
            self.apply(error: "initial load failed: \(error.localizedDescription)")
            self.connectionState = .failed(reason: error.localizedDescription)
        }
    }

    private func refresh(from provider: any SessionProvider) async {
        do {
            self.sessions = try await provider.listSessions()
        } catch {
            self.apply(error: "refresh failed: \(error.localizedDescription)")
        }
    }

    public func kill(_ session: TmuxSession, via provider: any SessionProvider) async {
        do {
            try await provider.kill(sessionName: session.id)
        } catch {
            self.apply(error: "kill failed: \(error.localizedDescription)")
        }
    }

    public func createSession(name: String, command: String?, via provider: any SessionProvider) async {
        do {
            try await provider.createSession(name: name, command: command)
        } catch {
            self.apply(error: "create failed: \(error.localizedDescription)")
        }
    }
}

/// Core 에서 TmuxKit 구현을 추상화하기 위한 프로토콜. TmuxKit.ControlClient 가 conformance 제공.
public protocol SessionProvider: Sendable {
    func listSessions() async throws -> [TmuxSession]
    func kill(sessionName: String) async throws
    func createSession(name: String, command: String?) async throws
    var events: AsyncStream<SessionProviderEvent> { get }
}

public enum SessionProviderEvent: Sendable, Equatable {
    case sessionsChanged
    case connectionLost
    case unknown
}
