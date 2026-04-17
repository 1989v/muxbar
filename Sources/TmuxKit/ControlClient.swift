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
    private var pendingBodies: [Int: String] = [:]

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

    public func bootstrap() async throws {
        try ensureServerRunning()
        try spawnControlProcess()
        startStdoutPump()
        logger.info("ControlClient bootstrapped")
    }

    private func ensureServerRunning() throws {
        // 서버 없으면 detached 관리 세션으로 서버 기동
        let check = Process()
        check.executableURL = URL(fileURLWithPath: tmuxPath)
        check.arguments = ["has-session", "-t", "_muxbar-ctl"]
        check.standardError = Pipe()
        check.standardOutput = Pipe()
        do {
            try check.run()
            check.waitUntilExit()
        } catch {
            throw ClientError.processFailedToStart("tmux has-session 실패: \(error.localizedDescription)")
        }

        if check.terminationStatus != 0 {
            // _muxbar-ctl 없음 → 생성 (서버도 같이 뜸)
            let make = Process()
            make.executableURL = URL(fileURLWithPath: tmuxPath)
            make.arguments = ["new-session", "-d", "-s", "_muxbar-ctl"]
            make.standardError = Pipe()
            make.standardOutput = Pipe()
            try make.run()
            make.waitUntilExit()
            guard make.terminationStatus == 0 else {
                throw ClientError.processFailedToStart("tmux new-session _muxbar-ctl 실패 (exit=\(make.terminationStatus))")
            }
        }
    }

    private func spawnControlProcess() throws {
        let p = Process()
        let inPipe = Pipe()
        let outPipe = Pipe()
        let errPipe = Pipe()

        p.executableURL = URL(fileURLWithPath: tmuxPath)
        p.arguments = ["-C", "attach", "-t", "_muxbar-ctl"]
        p.standardInput = inPipe
        p.standardOutput = outPipe
        p.standardError = errPipe

        p.terminationHandler = { [weak self] proc in
            Task { [weak self] in
                await self?.handleProcessTermination(status: proc.terminationStatus)
            }
        }

        do {
            try p.run()
        } catch {
            throw ClientError.processFailedToStart("tmux -C 실행 실패: \(error.localizedDescription)")
        }

        self.process = p
        self.stdinPipe = inPipe
        self.stdoutPipe = outPipe
        self.stderrPipe = errPipe
    }

    private func startStdoutPump() {
        guard let outPipe = stdoutPipe else { return }
        let handle = outPipe.fileHandleForReading

        handle.readabilityHandler = { [weak self] fh in
            let data = fh.availableData
            guard !data.isEmpty else { return }
            guard let chunk = String(data: data, encoding: .utf8) else { return }
            Task { [weak self] in
                await self?.ingest(chunk)
            }
        }
    }

    private func ingest(_ chunk: String) {
        let events = protocolParser.feed(chunk)
        for event in events {
            handleEvent(event)
        }
    }

    private func handleEvent(_ event: ControlEvent) {
        switch event {
        case .commandOutput(let cmdId, let body):
            // pending 명령의 응답으로 보관. 최종 end/error 에서 resolve.
            pendingBodies[cmdId] = body
        case .commandEnd(_, let cmdId, _):
            if let body = pendingBodies.removeValue(forKey: cmdId) ?? Optional("") {
                pendingCommands.removeValue(forKey: cmdId)?.resume(returning: body)
            }
        case .commandError(_, let cmdId, _):
            let body = pendingBodies.removeValue(forKey: cmdId) ?? ""
            pendingCommands.removeValue(forKey: cmdId)?
                .resume(throwing: ClientError.processFailedToStart("tmux error: \(body)"))
        case .exit:
            disconnect()
        default:
            break
        }
        eventStreamContinuation?.yield(event)
    }

    private func handleProcessTermination(status: Int32) {
        logger.warning("tmux -C process terminated (status=\(status))")
        disconnect()
    }
}
