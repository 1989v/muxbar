import Foundation

public struct TmuxWindow: Identifiable, Sendable, Equatable, Hashable {
    public let id: String          // "@<n>"
    public let sessionId: String
    public let index: Int
    public let name: String
    public let paneCount: Int
    public let isActive: Bool

    public init(id: String, sessionId: String, index: Int, name: String, paneCount: Int, isActive: Bool) {
        self.id = id
        self.sessionId = sessionId
        self.index = index
        self.name = name
        self.paneCount = paneCount
        self.isActive = isActive
    }
}
