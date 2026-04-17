import Foundation
import Core
import MuxLogging

@MainActor
public final class TemplateStore: ObservableObject {
    @Published public private(set) var userTemplates: [Template] = []
    @Published public private(set) var builtInTemplates: [Template] = BuiltInTemplates.all

    private let logger = MuxLogging.logger("Features.TemplateStore")

    public init() {}

    public var all: [Template] {
        builtInTemplates + userTemplates
    }

    public func reload() {
        let loaded = UserTemplatesLoader.load()
        self.userTemplates = loaded
        logger.info("user templates loaded: \(loaded.count)")
    }

    public var templatesDirectoryURL: URL {
        UserTemplatesLoader.directory
    }
}
