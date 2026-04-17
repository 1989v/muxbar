import Foundation
import Combine
import MuxLogging

@MainActor
public final class SessionStore: ObservableObject {
    @Published public private(set) var sessions: [TmuxSession] = []
    @Published public private(set) var connectionState: ConnectionState = .disconnected
    @Published public private(set) var lastError: String?
    @Published public private(set) var caffeinateStatus: CaffeinateStatus = CaffeinateStatus()

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
        self.connectionState = .connecting(attempt: 1)
        logger.info("initialLoad 시작 (list-sessions 요청)")
        do {
            let fetched = try await provider.listSessions()
            self.sessions = fetched
            self.connectionState = .connected
            logger.info("initialLoad 완료 — \(fetched.count) sessions (\(fetched.map(\.id).joined(separator: ", ")))")
            await refreshCaffeinate(from: provider)
        } catch {
            self.apply(error: "initial load failed: \(error.localizedDescription)")
            self.connectionState = .failed(reason: error.localizedDescription)
            logger.error("initialLoad 실패: \(error.localizedDescription)")
        }
    }

    private func refresh(from provider: any SessionProvider) async {
        do {
            let fetched = try await provider.listSessions()
            self.sessions = fetched
            logger.info("refresh — \(fetched.count) sessions")
            await refreshCaffeinate(from: provider)
        } catch {
            self.apply(error: "refresh failed: \(error.localizedDescription)")
        }
    }

    public func refreshCaffeinate(from provider: any SessionProvider) async {
        do {
            let tmuxList = try await provider.listCaffeinateSessions()
            let systemActive = SystemCaffeinateDetector.isActive()
            self.caffeinateStatus = CaffeinateStatus(tmuxSessions: tmuxList, systemActive: systemActive)
            logger.info("caffeinate 상태 — tmux=\(tmuxList.count) (\(tmuxList.joined(separator: ","))), system=\(systemActive)")
        } catch {
            logger.warning("caffeinate 감지 실패: \(error.localizedDescription)")
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
    func capturePane(target: String, lines: Int) async throws -> String
    /// tmux 내에서 caffeinate 를 실행 중인 세션 이름들.
    func listCaffeinateSessions() async throws -> [String]
    var events: AsyncStream<SessionProviderEvent> { get }
    var paneOutput: AsyncStream<PaneOutputChunk> { get }
}

public enum SessionProviderEvent: Sendable, Equatable {
    case sessionsChanged
    case connectionLost
    case unknown
}

/// %output 이벤트의 Core 레이어 표현.
public struct PaneOutputChunk: Sendable, Equatable {
    public let paneId: String
    public let data: Data
    public init(paneId: String, data: Data) {
        self.paneId = paneId
        self.data = data
    }
}

/// caffeinate 활성 상태 — tmux 세션 레벨 + 시스템 pmset 통합.
public struct CaffeinateStatus: Sendable, Equatable {
    /// caffeinate 가 실행 중인 tmux 세션 이름들 (muxbar 관리 + 외부 모두 포함)
    public let tmuxSessions: [String]
    /// tmux 외부에서 caffeinate 프로세스가 돌고 있는지 (pmset -g assertions 기반)
    public let systemActive: Bool

    public init(tmuxSessions: [String] = [], systemActive: Bool = false) {
        self.tmuxSessions = tmuxSessions
        self.systemActive = systemActive
    }

    public var isActive: Bool { !tmuxSessions.isEmpty || systemActive }

    /// tmux 외부에서만 caffeinate 가 돌고 있을 때 true (kill 대상이 tmux 에 없음 → pkill 필요)
    public var hasExternalOnly: Bool { tmuxSessions.isEmpty && systemActive }
}

/// 시스템 전역 caffeinate 프로세스 존재 여부 검사.
public enum SystemCaffeinateDetector {
    public static func isActive() -> Bool {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/usr/bin/pmset")
        p.arguments = ["-g", "assertions"]
        let pipe = Pipe()
        p.standardOutput = pipe
        p.standardError = Pipe()
        do {
            try p.run()
            p.waitUntilExit()
        } catch {
            return false
        }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        let output = String(data: data, encoding: .utf8) ?? ""
        // pmset 은 assertion 보유 프로세스명을 "pid N(caffeinate): ..." 형태로 출력
        return output.range(of: "caffeinate", options: .caseInsensitive) != nil
    }

    /// tmux 밖에서 돌고 있는 caffeinate 프로세스 전부 종료.
    public static func pkillAll() {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/usr/bin/pkill")
        p.arguments = ["-x", "caffeinate"]
        p.standardOutput = Pipe()
        p.standardError = Pipe()
        try? p.run()
        p.waitUntilExit()
    }
}
