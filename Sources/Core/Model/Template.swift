import Foundation

public struct Template: Codable, Identifiable, Sendable, Equatable {
    public let id: UUID
    public var name: String
    public var description: String
    public var sessionNameHint: String
    public var windows: [TemplateWindow]

    public init(id: UUID = UUID(), name: String, description: String, sessionNameHint: String, windows: [TemplateWindow]) {
        self.id = id
        self.name = name
        self.description = description
        self.sessionNameHint = sessionNameHint
        self.windows = windows
    }
}

public struct TemplateWindow: Codable, Sendable, Equatable {
    public var name: String
    public var command: String?
    public var cwd: String?

    public init(name: String, command: String? = nil, cwd: String? = nil) {
        self.name = name; self.command = command; self.cwd = cwd
    }
}
