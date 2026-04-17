import Foundation

public enum TmuxPath {
    public static let defaultCandidates: [String] = [
        "/opt/homebrew/bin/tmux",     // Apple Silicon Homebrew
        "/usr/local/bin/tmux",        // Intel Homebrew
        "/usr/bin/tmux",              // 시스템 기본 (없을 수도)
        "/opt/local/bin/tmux",        // MacPorts
    ]

    public static func resolve(from candidates: [String] = defaultCandidates) -> String? {
        let fm = FileManager.default
        return candidates.first { fm.isExecutableFile(atPath: $0) || fm.fileExists(atPath: $0) }
    }
}
