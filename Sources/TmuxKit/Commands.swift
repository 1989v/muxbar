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
            let fields = #"#{session_name}\t#{session_attached}\t#{session_windows}\t#{session_created}\t#{session_activity}\t#{session_path}"#
            return #"list-sessions -F "\#(fields)""#

        case .listWindows(let session):
            let fields = #"#{window_id}\t#{window_index}\t#{window_name}\t#{window_panes}\t#{window_active}"#
            return #"list-windows -t \#(quote(session)) -F "\#(fields)""#

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
