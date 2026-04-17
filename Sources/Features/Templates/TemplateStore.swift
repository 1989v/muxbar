import Foundation
import Core

@MainActor
public final class TemplateStore: ObservableObject {
    @Published public private(set) var userTemplates: [Template] = []
    @Published public private(set) var builtInTemplates: [Template] = BuiltInTemplates.all

    public init() {}

    public var all: [Template] {
        builtInTemplates + userTemplates
    }

    public func reload() {
        userTemplates = UserTemplatesLoader.load()
    }

    public var templatesDirectoryURL: URL {
        UserTemplatesLoader.directory
    }
}
