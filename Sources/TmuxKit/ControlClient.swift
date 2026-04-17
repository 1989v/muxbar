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
    public nonisolated let rawEvents: AsyncStream<ControlEvent>

    public init(tmuxPath: String? = TmuxPath.resolve()) throws {
        guard let path = tmuxPath else { throw ClientError.tmuxBinaryNotFound }
        self.tmuxPath = path

        // AsyncStream 의 빌더 클로저는 동기 실행되므로 init 리턴 전에 continuation 확보 완료.
        var localContinuation: AsyncStream<ControlEvent>.Continuation!
        self.rawEvents = AsyncStream<ControlEvent> { continuation in
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
        case .commandBegin(_, let cmdId, _):
            if !awaitingBegin.isEmpty {
                let cont = awaitingBegin.removeFirst()
                pendingCommands[cmdId] = cont
            }
        case .commandOutput(let cmdId, let body):
            pendingBodies[cmdId] = body
        case .commandEnd(_, let cmdId, _):
            let body = pendingBodies.removeValue(forKey: cmdId) ?? ""
            pendingCommands.removeValue(forKey: cmdId)?.resume(returning: body)
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

    /// tmux 커맨드를 전송하고 응답 본문(raw string)을 반환. %end 수신 시 resolve.
    @discardableResult
    public func send(_ command: TmuxCommand, timeout: TimeInterval = 5.0) async throws -> String {
        guard let stdin = stdinPipe?.fileHandleForWriting else {
            throw ClientError.notConnected
        }

        nextCmdId += 1
        let _ = nextCmdId // cmdId 는 tmux 가 붙이는 것. 우리는 응답 매칭을 body carry 순서로 처리.

        // tmux control mode 는 명령을 라인으로 받고, 본인이 cmdId 를 할당해 %begin 에 실음.
        // 클라이언트 측에서는 "다음 %begin 의 cmdId" 를 예약 대기로 처리해야 함.
        return try await withCheckedThrowingContinuation { continuation in
            Task {
                await self.registerNextPendingCommand(continuation: continuation)
                let line = command.cliString + "\n"
                if let data = line.data(using: .utf8) {
                    do {
                        try stdin.write(contentsOf: data)
                    } catch {
                        await self.rejectLastPending(error: error)
                    }
                }
            }
        }
    }

    // 다음 %begin 이 붙일 cmdId 가 아직 미정이므로, 큐로 보관 → 첫 %begin 수신 시 바인딩.
    private var awaitingBegin: [CheckedContinuation<String, Error>] = []

    private func registerNextPendingCommand(continuation: CheckedContinuation<String, Error>) {
        awaitingBegin.append(continuation)
    }

    private func rejectLastPending(error: Error) {
        if let cont = awaitingBegin.popLast() {
            cont.resume(throwing: error)
        }
    }

    public func listSessions() async throws -> [TmuxSession] {
        let body = try await send(.listSessions)
        return try SessionListParser.parse(body)
    }
}
