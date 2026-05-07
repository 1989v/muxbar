import Foundation
import Core

extension ControlClient: SessionProvider {
    public nonisolated var events: AsyncStream<SessionProviderEvent> {
        sessionEventBroadcaster.stream()
    }

    public nonisolated var paneOutput: AsyncStream<PaneOutputChunk> {
        paneOutputBroadcaster.stream()
    }

    public func kill(sessionName: String) async throws {
        _ = try await send(.killSession(name: sessionName))
    }

    public func createSession(name: String, command: String?) async throws {
        _ = try await send(.newSession(name: name, command: command))
    }

    public func capturePane(target: String, lines: Int) async throws -> String {
        try await send(.capturePane(target: target, lines: lines, withEscapes: true))
    }

    public func listCaffeinateSessions() async throws -> [String] {
        // 모든 세션의 모든 pane 의 현재 커맨드를 한 번에 조회.
        // 포맷: "<session_name>@@@<pane_current_command>"
        // listSessions 와 동일하게 환경 무관 안전 marker.
        let raw = try await sendRaw("list-panes -a -F \"#{session_name}@@@#{pane_current_command}\"")
        let sessions = raw
            .split(separator: "\n", omittingEmptySubsequences: true)
            .compactMap { line -> String? in
                let parts = String(line).components(separatedBy: "@@@")
                guard parts.count == 2 else { return nil }
                let command = parts[1].lowercased()
                guard command.contains("caffeinate") else { return nil }
                return parts[0]
            }
        // 중복 제거 (세션에 caffeinate pane 여러개 있을 수 있음)
        return Array(Set(sessions)).sorted()
    }
}
