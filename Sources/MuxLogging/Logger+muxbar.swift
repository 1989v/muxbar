import Foundation
import Logging

public enum MuxLogging {
    private static let isBootstrapped = NSLock()
    nonisolated(unsafe) private static var didBootstrap = false

    public static func bootstrap() {
        isBootstrapped.lock()
        defer { isBootstrapped.unlock() }
        guard !didBootstrap else { return }

        LoggingSystem.bootstrap { label in
            var handler = StreamLogHandler.standardError(label: label)
            #if DEBUG
            handler.logLevel = .debug
            #else
            handler.logLevel = .info
            #endif
            return handler
        }
        didBootstrap = true
    }

    public static func logger(_ label: String) -> Logger {
        Logger(label: "muxbar.\(label)")
    }
}
