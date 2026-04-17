import Foundation

public struct CaffeinateFlags: Sendable, Equatable, Hashable, Codable {
    public var preventDisplaySleep: Bool      // -d
    public var preventIdleSleep: Bool         // -i
    public var preventDiskIdleSleep: Bool     // -m
    public var preventSystemSleep: Bool       // -s
    public var preventUserIdleSleep: Bool     // -u

    public init(d: Bool, i: Bool, m: Bool, s: Bool, u: Bool) {
        self.preventDisplaySleep = d
        self.preventIdleSleep = i
        self.preventDiskIdleSleep = m
        self.preventSystemSleep = s
        self.preventUserIdleSleep = u
    }

    public static let `default` = CaffeinateFlags(d: true, i: true, m: true, s: true, u: false)

    public var cliArgs: String {
        var chars = ""
        if preventDisplaySleep   { chars += "d" }
        if preventIdleSleep      { chars += "i" }
        if preventDiskIdleSleep  { chars += "m" }
        if preventSystemSleep    { chars += "s" }
        if preventUserIdleSleep  { chars += "u" }
        return chars.isEmpty ? "" : "-\(chars)"
    }

    public var isValid: Bool {
        preventDisplaySleep || preventIdleSleep || preventDiskIdleSleep
            || preventSystemSleep || preventUserIdleSleep
    }
}
