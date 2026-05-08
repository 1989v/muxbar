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
        let code = (dict["NSAppleScriptErrorNumber"] as? NSNumber)?.intValue ?? 0
        let msg = dict["NSAppleScriptErrorMessage"] as? String ?? "unknown"
        return code == -128 ? .userCancelled : .scriptFailed(msg)
    }

    @MainActor
    public static func disableSystemSleep() async throws {
        try run(disable: true)
    }

    @MainActor
    public static func enableSystemSleep() async throws {
        try run(disable: false)
    }

    @MainActor
    private static func run(disable: Bool) throws {
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
