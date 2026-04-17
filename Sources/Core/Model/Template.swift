import Foundation

public struct Template: Codable, Identifiable, Sendable, Equatable {
    public var id: UUID
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

    // YAML 파일에 id 생략 가능 — 없으면 생성
    private enum CodingKeys: String, CodingKey {
        case id, name, description, sessionNameHint, windows
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.id = (try? c.decode(UUID.self, forKey: .id)) ?? UUID()
        self.name = try c.decode(String.self, forKey: .name)
        self.description = try c.decodeIfPresent(String.self, forKey: .description) ?? ""
        self.sessionNameHint = try c.decodeIfPresent(String.self, forKey: .sessionNameHint) ?? name.lowercased()
        self.windows = try c.decode([TemplateWindow].self, forKey: .windows)
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
