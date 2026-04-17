import Foundation

public struct TmuxPane: Identifiable, Sendable, Equatable, Hashable {
    public let id: String          // "%<n>"
    public let windowId: String
    public let command: String?
    public let pid: pid_t?
    public let isActive: Bool

    public init(id: String, windowId: String, command: String?, pid: pid_t?, isActive: Bool) {
        self.id = id
        self.windowId = windowId
        self.command = command
        self.pid = pid
        self.isActive = isActive
    }
}
