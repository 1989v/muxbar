import Foundation
import Darwin
import Logging
import os

public enum MuxLogging {
    private static let isBootstrapped = NSLock()
    nonisolated(unsafe) private static var didBootstrap = false
    nonisolated(unsafe) private static var signalSources: [DispatchSourceSignal] = []

    public static func bootstrap() {
        isBootstrapped.lock()
        defer { isBootstrapped.unlock() }
        guard !didBootstrap else { return }

        LoggingSystem.bootstrap { label in
            var stream = StreamLogHandler.standardError(label: label)
            #if DEBUG
            stream.logLevel = .debug
            #else
            stream.logLevel = .info
            #endif
            let oslog = OSLogHandler(label: label)
            return MultiplexLogHandler([stream, oslog])
        }
        didBootstrap = true
        installLifecycleProbes()
    }

    public static func logger(_ label: String) -> Logging.Logger {
        Logging.Logger(label: "muxbar.\(label)")
    }

    /// 비정상 종료 사유를 stderr/OSLog 에 남기기 위한 라이프사이클 훅.
    /// graceful 시그널은 main queue 핸들러로 critical 로그 후 정상 exit,
    /// hard 시그널은 async-signal-safe 한 write 만 사용해 마커를 남기고 _exit.
    private static func installLifecycleProbes() {
        logger("lifecycle").info("probes installed pid=\(getpid()) ppid=\(getppid())")

        for sig in [SIGTERM, SIGINT, SIGHUP, SIGQUIT, SIGPIPE] {
            signal(sig, SIG_IGN)
            let src = DispatchSource.makeSignalSource(signal: sig, queue: .main)
            src.setEventHandler {
                MuxLogging.logger("lifecycle").critical("graceful signal signo=\(sig) — exiting")
                exit(128 &+ sig)
            }
            src.resume()
            signalSources.append(src)
        }

        for sig in [SIGABRT, SIGSEGV, SIGBUS, SIGILL, SIGFPE] {
            signal(sig, hardSignalHandler)
        }

        atexit {
            let s: StaticString = "[muxbar][lifecycle] atexit\n"
            s.withUTF8Buffer { ptr in _ = write(STDERR_FILENO, ptr.baseAddress, ptr.count) }
        }
    }

    private static let hardSignalHandler: @convention(c) (Int32) -> Void = { sig in
        let s: StaticString = "[muxbar][lifecycle] hard signal\n"
        s.withUTF8Buffer { ptr in _ = write(STDERR_FILENO, ptr.baseAddress, ptr.count) }
        _exit(128 &+ sig)
    }
}

/// swift-log → os.Logger 어댑터. 사후 분석을 위해 unified log 에도 기록한다.
public struct OSLogHandler: LogHandler {
    public var metadata: Logging.Logger.Metadata = [:]
    public var logLevel: Logging.Logger.Level = .info
    private let osLog: os.Logger

    public init(label: String, subsystem: String = "com.1989v.muxbar") {
        self.osLog = os.Logger(subsystem: subsystem, category: label)
    }

    public subscript(metadataKey key: String) -> Logging.Logger.Metadata.Value? {
        get { metadata[key] }
        set { metadata[key] = newValue }
    }

    public func log(
        level: Logging.Logger.Level,
        message: Logging.Logger.Message,
        metadata: Logging.Logger.Metadata?,
        source: String,
        file: String,
        function: String,
        line: UInt
    ) {
        let text = "\(message)"
        switch level {
        case .trace, .debug:    osLog.debug("\(text, privacy: .public)")
        case .info, .notice:    osLog.info("\(text, privacy: .public)")
        case .warning:          osLog.warning("\(text, privacy: .public)")
        case .error:            osLog.error("\(text, privacy: .public)")
        case .critical:         osLog.critical("\(text, privacy: .public)")
        }
    }
}
