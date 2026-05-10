import Foundation
import AppKit

public enum PowerControl {
    public enum Error: Swift.Error, Equatable {
        case userCancelled
        case scriptFailed(String)
    }

    static func buildScript(disable: Bool) -> String {
        let value = disable ? "1" : "0"
        return #"do shell script "/usr/bin/pmset -a disablesleep \#(value)" with administrator privileges"#
    }

    static func mapError(_ dict: NSDictionary) -> Error {
        let code = (dict[NSAppleScript.errorNumber] as? NSNumber)?.intValue ?? 0
        let msg = dict[NSAppleScript.errorMessage] as? String ?? "unknown"
        return code == -128 ? .userCancelled : .scriptFailed(msg)
    }

    @MainActor
    public static func disableSystemSleep() async throws {
        if runSudoNoPrompt(disable: true) { return }
        try run(disable: true)
    }

    @MainActor
    public static func enableSystemSleep() async throws {
        if runSudoNoPrompt(disable: false) { return }
        try run(disable: false)
    }

    /// `sudo -n /usr/bin/pmset -a disablesleep N` 시도. NOPASSWD 룰이 있으면 prompt 없이 통과.
    /// 룰 미설정/만료/cache miss 면 sudo 가 non-zero 종료 → false 반환 → AppleScript fallback.
    @MainActor
    private static func runSudoNoPrompt(disable: Bool) -> Bool {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/usr/bin/sudo")
        p.arguments = ["-n", "/usr/bin/pmset", "-a", "disablesleep", disable ? "1" : "0"]
        p.standardError = Pipe()
        p.standardOutput = Pipe()
        do {
            try p.run()
            p.waitUntilExit()
            return p.terminationStatus == 0
        } catch {
            return false
        }
    }

    @MainActor
    private static func run(disable: Bool) throws {
        // NOTE: blocks main thread during password dialog (NSAppleScript runs nested run loop).
        let source = buildScript(disable: disable)
        guard let script = NSAppleScript(source: source) else {
            throw Error.scriptFailed("AppleScript init failed")
        }
        var errorInfo: NSDictionary?
        _ = script.executeAndReturnError(&errorInfo)
        if let dict = errorInfo {
            throw mapError(dict)
        }
    }
}

/// ClosedLidStore.PowerController 어댑터.
public struct DefaultPowerController: ClosedLidStore.PowerController {
    public init() {}
    public func disableSystemSleep() async throws { try await PowerControl.disableSystemSleep() }
    public func enableSystemSleep() async throws { try await PowerControl.enableSystemSleep() }
}
