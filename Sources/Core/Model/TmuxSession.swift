import Foundation

public struct TmuxSession: Identifiable, Sendable, Equatable, Hashable {
    public let id: String
    public let isAttached: Bool
    public let windowCount: Int
    public let createdAt: Date
    public let lastActivityAt: Date
    public let workingDirectory: String?

    public init(
        id: String,
        isAttached: Bool,
        windowCount: Int,
        createdAt: Date,
        lastActivityAt: Date,
        workingDirectory: String?
    ) {
        self.id = id
        self.isAttached = isAttached
        self.windowCount = windowCount
        self.createdAt = createdAt
        self.lastActivityAt = lastActivityAt
        self.workingDirectory = workingDirectory
    }

    public var isInternal: Bool {
        id.hasPrefix("_muxbar-")
    }
}
