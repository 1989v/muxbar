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
        sessions
            .filter { !$0.isInternal }
            .sorted { lhs, rhs in
                // 1순위: attached 세션 먼저
                if lhs.isAttached != rhs.isAttached {
                    return lhs.isAttached
                }
                // 2순위: 최근 생성된 세션 먼저 (createdAt DESC)
                return lhs.createdAt > rhs.createdAt
            }
    }

    public var awakeSessionExists: Bool {
        sessions.contains { $0.id == "_muxbar-awake" }
    }

    /// 외부에서 주입 (테스트용 / 실행 시 TmuxKit 연결)
    public func apply(sessions: [TmuxSession]) {
        self.sessions = sessions
    }

    public func apply(caffeinateStatus: CaffeinateStatus) {
        self.caffeinateStatus = caffeinateStatus
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
        do {
            let fetched = try await provider.listSessions()
            self.sessions = fetched
            self.connectionState = .connected
            await refreshCaffeinate(from: provider)
        } catch {
            self.apply(error: "initial load failed: \(error.localizedDescription)")
            self.connectionState = .failed(reason: error.localizedDescription)
            logger.error("initial load failed: \(error.localizedDescription)")
        }
    }

    private func refresh(from provider: any SessionProvider) async {
        do {
            self.sessions = try await provider.listSessions()
            await refreshCaffeinate(from: provider)
        } catch {
            self.apply(error: "refresh failed: \(error.localizedDescription)")
        }
    }

    public func refreshCaffeinate(from provider: any SessionProvider) async {
        do {
            let tmuxList = try await provider.listCaffeinateSessions()
            // 외부 명령이라 메인 스레드 밖에서 — 응답이 늦어도 메뉴바는 굳지 않는다.
            let externalPids = await Task.detached { SystemCaffeinateDetector.externalPids() }.value
            self.caffeinateStatus = CaffeinateStatus(tmuxSessions: tmuxList, externalPids: externalPids)
        } catch {
            logger.warning("caffeinate detection failed: \(error.localizedDescription)")
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
    /// tmux 밖에서 잠자기를 막고 있는 caffeinate 의 pid (pmset -g assertions 기반)
    public let externalPids: [Int32]

    public init(tmuxSessions: [String] = [], externalPids: [Int32] = []) {
        self.tmuxSessions = tmuxSessions
        self.externalPids = externalPids
    }

    public var systemActive: Bool { !externalPids.isEmpty }

    /// Keep Awake 가 보고 끄는 tmux 세션. Closed-lid 의 caffeinate 는 그 모드가 켜고 끄므로 뺀다.
    public var keepAwakeSessions: [String] {
        tmuxSessions.filter { $0 != ClosedLidStore.sessionName }
    }

    /// Keep Awake 기준 활성 여부 — Closed-lid 만 켜져 있으면 false.
    public var isActive: Bool { !keepAwakeSessions.isEmpty || systemActive }
}

/// tmux 밖에서 도는 caffeinate 검출·종료.
public enum SystemCaffeinateDetector {
    /// 잠자기를 막고 있는 caffeinate 중 부모가 tmux 가 아닌 것의 pid.
    /// tmux 안의 것은 세션 단위로 다루므로 여기서 빼고, 특히 Closed-lid 세션의 caffeinate 를
    /// 바깥 것으로 잘못 세어 끄지 않게 한다. 부모를 확인하지 못하면 아무것도 바깥으로 치지 않는다.
    public static func externalPids() -> [Int32] {
        guard let assertions = try? ProcessRunner.run("/usr/bin/pmset", ["-g", "assertions"], timeout: 5),
              !assertions.timedOut else { return [] }
        let pids = caffeinatePids(fromAssertions: assertions.stdoutText)
        guard !pids.isEmpty else { return [] }
        guard let ps = try? ProcessRunner.run("/bin/ps", ["-axo", "pid=,ppid=,comm="], timeout: 5),
              ps.succeeded else { return [] }
        return excludingTmuxChildren(pids, psOutput: ps.stdoutText)
    }

    /// pmset 은 assertion 보유 프로세스를 "pid N(caffeinate): ..." 형태로 출력한다.
    static func caffeinatePids(fromAssertions text: String) -> [Int32] {
        let pattern = #/pid (\d+)\(caffeinate\)/#
        let pids = text.matches(of: pattern).compactMap { Int32($0.output.1) }
        return Array(Set(pids)).sorted()
    }

    /// `ps -axo pid=,ppid=,comm=` 출력으로 부모가 tmux 인 pid 를 뺀다.
    static func excludingTmuxChildren(_ pids: [Int32], psOutput: String) -> [Int32] {
        var parent: [Int32: Int32] = [:]
        var command: [Int32: String] = [:]
        for line in psOutput.split(separator: "\n") {
            let fields = line.split(separator: " ", maxSplits: 2, omittingEmptySubsequences: true)
            guard fields.count == 3, let pid = Int32(fields[0]), let ppid = Int32(fields[1]) else { continue }
            parent[pid] = ppid
            command[pid] = String(fields[2])
        }
        return pids.filter { pid in
            guard let ppid = parent[pid] else { return false }  // 이미 끝난 프로세스
            let parentName = (command[ppid] ?? "").split(separator: "/").last.map(String.init) ?? ""
            return !parentName.hasPrefix("tmux")
        }
    }

    public static func terminate(_ pids: [Int32]) {
        for pid in pids { kill(pid, SIGTERM) }
    }
}
