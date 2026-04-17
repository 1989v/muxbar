import Foundation
import Core

public enum SessionListParser {
    public enum ParseError: Error, Equatable {
        case malformedLine(String)
    }

    public static func parse(_ body: String) throws -> [TmuxSession] {
        let trimmed = body.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return [] }

        return try trimmed.split(separator: "\n").map { line in
            let parts = line.split(separator: "\t", omittingEmptySubsequences: false).map(String.init)
            guard parts.count == 6 else {
                throw ParseError.malformedLine(String(line))
            }
            guard let attached = Int(parts[1]),
                  let windows = Int(parts[2]),
                  let created = TimeInterval(parts[3]),
                  let activity = TimeInterval(parts[4]) else {
                throw ParseError.malformedLine(String(line))
            }
            let cwd = parts[5].isEmpty ? nil : parts[5]
            return TmuxSession(
                id: parts[0],
                isAttached: attached != 0,
                windowCount: windows,
                createdAt: Date(timeIntervalSince1970: created),
                lastActivityAt: Date(timeIntervalSince1970: activity),
                workingDirectory: cwd
            )
        }
    }
}
