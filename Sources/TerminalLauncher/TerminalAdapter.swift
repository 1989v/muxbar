import Foundation
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
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
        p.arguments = ["-e", script]
        let errPipe = Pipe()
        p.standardError = errPipe
        p.standardOutput = Pipe()
        do {
            try p.run()
            p.waitUntilExit()
        } catch {
            throw TerminalLaunchError.scriptFailed(error.localizedDescription)
        }
        if p.terminationStatus != 0 {
            let err = String(data: errPipe.fileHandleForReading.availableData, encoding: .utf8) ?? ""
            throw TerminalLaunchError.scriptFailed("osascript exit=\(p.terminationStatus): \(err)")
        }
    }

    private func runOpenNewInstance(bundleId: String, args: [String]) throws {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/usr/bin/open")
        p.arguments = ["-na", "-b", bundleId, "--args"] + args
        let errPipe = Pipe()
        p.standardError = errPipe
        do {
            try p.run()
            p.waitUntilExit()
        } catch {
            throw TerminalLaunchError.scriptFailed(error.localizedDescription)
        }
        if p.terminationStatus != 0 {
            let err = String(data: errPipe.fileHandleForReading.availableData, encoding: .utf8) ?? ""
            throw TerminalLaunchError.scriptFailed("open exit=\(p.terminationStatus): \(err)")
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
