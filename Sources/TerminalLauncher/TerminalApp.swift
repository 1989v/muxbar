import Foundation

public enum TerminalApp: String, Sendable, CaseIterable, Identifiable {
    case terminal  = "com.apple.Terminal"
    case iterm2    = "com.googlecode.iterm2"
    case warp      = "dev.warp.Warp-Stable"
    case alacritty = "org.alacritty"
    case kitty     = "net.kovidgoyal.kitty"

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .terminal: return "Terminal"
        case .iterm2:   return "iTerm2"
        case .warp:     return "Warp"
        case .alacritty: return "Alacritty"
        case .kitty:    return "kitty"
        }
    }

    public func isInstalled() -> Bool {
        NSWorkspace.shared.urlForApplication(withBundleIdentifier: rawValue) != nil
    }
}

#if canImport(AppKit)
import AppKit
#endif
