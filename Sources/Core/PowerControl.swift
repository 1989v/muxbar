import Foundation
import AppKit

public enum PowerControl {
    public enum Error: Swift.Error, Equatable {
        case userCancelled
        case passwordRequired
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

    /// - parameter allowPrompt: false면 sudo -n 만 시도. NOPASSWD 룰 없으면 `.passwordRequired` throw —
    ///   타이머/AC/lid 같은 자동 trigger 에서 password dialog 가 뜨는 걸 막기 위한 옵션.
    @MainActor
    public static func enableSystemSleep(allowPrompt: Bool = true) async throws {
        if runSudoNoPrompt(disable: false) { return }
        guard allowPrompt else { throw Error.passwordRequired }
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

    /// `pmset -g` 의 `SleepDisabled` 값을 읽어 현재 시스템 슬립이 꺼져있는지 반환.
    /// 읽기 전용이라 sudo/비밀번호 불필요 — launch reconcile 에서 불필요한 password prompt 를
    /// 피하기 위한 게이트로 사용.
    static func isSystemSleepDisabled() -> Bool {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/usr/bin/pmset")
        p.arguments = ["-g"]
        let out = Pipe()
        p.standardOutput = out
        p.standardError = Pipe()
        do {
            try p.run()
            let data = out.fileHandleForReading.readDataToEndOfFile()
            p.waitUntilExit()
            guard let text = String(data: data, encoding: .utf8) else { return false }
            // 예: " SleepDisabled\t\t1"
            for line in text.split(separator: "\n") {
                let fields = line.split(whereSeparator: \.isWhitespace)
                guard fields.first == "SleepDisabled", let value = fields.last else { continue }
                return value == "1"
            }
            return false
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
    public func enableSystemSleep(allowPrompt: Bool) async throws {
        try await PowerControl.enableSystemSleep(allowPrompt: allowPrompt)
    }
    public func isSystemSleepDisabled() async -> Bool {
        PowerControl.isSystemSleepDisabled()
    }
}
