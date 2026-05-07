import Foundation

public enum TmuxCommand: Sendable, Equatable {
    case listSessions
    case listWindows(session: String)
    case killSession(name: String)
    case newSession(name: String, command: String?)
    case hasSession(name: String)
    case capturePane(target: String, lines: Int, withEscapes: Bool)
    case renameSession(from: String, to: String)

    public var cliString: String {
        switch self {
        case .listSessions:
            // raw 탭(U+0009) separator 는 GUI launch 환경에서 응답 시 underscore 로 둔갑하는
            // 케이스 발견(2026-05-07) → 환경 무관하게 안전한 multi-char 마커로 교체.
            let fields = "#{session_name}@@@#{session_attached}@@@#{session_windows}@@@#{session_created}@@@#{session_activity}@@@#{session_path}"
            return "list-sessions -F \"\(fields)\""

        case .listWindows(let session):
            let fields = "#{window_id}@@@#{window_index}@@@#{window_name}@@@#{window_panes}@@@#{window_active}"
            return "list-windows -t \(quote(session)) -F \"\(fields)\""

        case .killSession(let name):
            return #"kill-session -t \#(quote(name))"#

        case .newSession(let name, let command):
            if let command {
                return #"new-session -d -s \#(quote(name)) \#(quote(command))"#
            } else {
                return #"new-session -d -s \#(quote(name))"#
            }

        case .hasSession(let name):
            return #"has-session -t \#(quote(name))"#

        case .capturePane(let target, let lines, let withEscapes):
            let e = withEscapes ? " -e" : ""
            return #"capture-pane -pt \#(quote(target)) -J\#(e) -S -\#(lines)"#

        case .renameSession(let from, let to):
            return #"rename-session -t \#(quote(from)) \#(quote(to))"#
        }
    }

    /// 큰따옴표로 감싸고 내부 `"` 만 이스케이프.
    private func quote(_ s: String) -> String {
        let escaped = s.replacingOccurrences(of: "\"", with: "\\\"")
        return "\"\(escaped)\""
    }
}
