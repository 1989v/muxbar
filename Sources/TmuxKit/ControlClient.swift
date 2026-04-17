import Foundation
import Logging
import MuxLogging
import Core

public actor ControlClient {
    public enum ClientError: Error, Equatable {
        case tmuxBinaryNotFound
        case processFailedToStart(String)
        case notConnected
        case commandTimeout(cmdId: Int)
        case serverExited
    }

    private let logger = MuxLogging.logger("TmuxKit.ControlClient")
    private let tmuxPath: String
    private var process: Process?
    private var stdinPipe: Pipe?
    private var stdoutPipe: Pipe?
    private var stderrPipe: Pipe?
    private let protocolParser = ControlProtocol()

    private var nextCmdId: Int = 0
    private var pendingCommands: [Int: CheckedContinuation<String, Error>] = [:]

    private var eventStreamContinuation: AsyncStream<ControlEvent>.Continuation?
    public nonisolated let events: AsyncStream<ControlEvent>

    public init(tmuxPath: String? = TmuxPath.resolve()) throws {
        guard let path = tmuxPath else { throw ClientError.tmuxBinaryNotFound }
        self.tmuxPath = path

        // AsyncStream 의 빌더 클로저는 동기 실행되므로 init 리턴 전에 continuation 확보 완료.
        var localContinuation: AsyncStream<ControlEvent>.Continuation!
        self.events = AsyncStream<ControlEvent> { continuation in
            localContinuation = continuation
        }
        self.eventStreamContinuation = localContinuation
    }

    public func connectionState() -> ConnectionState {
        process?.isRunning == true ? .connected : .disconnected
    }

    public func disconnect() {
        process?.terminate()
        process = nil
        stdinPipe = nil
        stdoutPipe = nil
        stderrPipe = nil

        for (_, cont) in pendingCommands {
            cont.resume(throwing: ClientError.serverExited)
        }
        pendingCommands.removeAll()

        eventStreamContinuation?.finish()
        logger.info("ControlClient disconnected")
    }
}
