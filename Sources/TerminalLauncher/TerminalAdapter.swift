import Foundation
import Core
#if canImport(AppKit)
import AppKit
#endif
import MuxLogging

public enum TerminalLaunchError: Error, Equatable {
    case notInstalled(TerminalApp)
    case scriptFailed(String)
    case tmuxNotFound
}

public struct TerminalAdapter: Sendable {
    private let logger = MuxLogging.logger("TerminalLauncher.Adapter")
    private let tmuxPath: String

    public init(tmuxPath: String) {
        self.tmuxPath = tmuxPath
    }

    public func attach(sessionName: String, using app: TerminalApp) async throws {
        guard app.isInstalled() else { throw TerminalLaunchError.notInstalled(app) }

        let tmuxCommand = "\(tmuxPath) attach -t \(shellQuote(sessionName))"
        logger.info("attach \(sessionName) via \(app.displayName)")

        switch app {
        case .terminal:
            try runOsascript(#"""
            tell application "Terminal"
                activate
                do script "\#(escapeForAppleScript(tmuxCommand))"
            end tell
            """#)
        case .iterm2:
            try runOsascript(#"""
            tell application "iTerm"
                activate
                if (count of windows) = 0 then
                    create window with default profile
                end if
                tell current window
                    tell current session to write text "\#(escapeForAppleScript(tmuxCommand))"
                end tell
            end tell
            """#)
        case .warp, .alacritty, .kitty:
            // Generic: open terminal with -e <cmd>
            try runOpenNewInstance(bundleId: app.rawValue, args: ["-e", tmuxPath, "attach", "-t", sessionName])
        }
    }

    private func runOsascript(_ script: String) throws {
        try runChecked("/usr/bin/osascript", ["-e", script], label: "osascript")
    }

    private func runOpenNewInstance(bundleId: String, args: [String]) throws {
        try runChecked("/usr/bin/open", ["-na", "-b", bundleId, "--args"] + args, label: "open")
    }

    /// 터미널 앱을 처음 띄우거나 자동화 권한을 묻는 동안 기다릴 수 있어 제한 시간을 넉넉히 둔다.
    private func runChecked(_ executable: String, _ args: [String], label: String) throws {
        let result: ProcessRunner.Result
        do {
            result = try ProcessRunner.run(executable, args, timeout: 60)
        } catch {
            throw TerminalLaunchError.scriptFailed(error.localizedDescription)
        }
        if result.timedOut {
            throw TerminalLaunchError.scriptFailed("\(label) 시간 초과")
        }
        if result.status != 0 {
            throw TerminalLaunchError.scriptFailed("\(label) exit=\(result.status): \(result.stderrText)")
        }
    }

    private func shellQuote(_ s: String) -> String {
        "'" + s.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }

    private func escapeForAppleScript(_ s: String) -> String {
        s.replacingOccurrences(of: "\\", with: "\\\\")
         .replacingOccurrences(of: "\"", with: "\\\"")
    }
}
