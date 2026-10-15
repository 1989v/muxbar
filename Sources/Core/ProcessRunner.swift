import Foundation

/// 끝나기를 기다리는 짧은 외부 명령 실행.
///
/// 출력과 에러를 백그라운드에서 끝까지 읽으면서 종료를 기다린다. 종료를 먼저 기다리고 나중에
/// 읽으면, 자식은 파이프 쓰기에서 막히고 앱은 종료 대기에서 막혀 둘 다 영원히 멈춘다.
/// 실제로 `pmset -g assertions` 가 이렇게 메인 스레드를 굳혀 메뉴바가 먹통이 됐다.
/// 제한 시간이 지나면 자식을 끝낸다 — 어떤 명령도 호출한 스레드를 무한히 붙잡지 않는다.
///
/// 오래 살아 있는 프로세스(tmux 컨트롤 모드)는 대상이 아니다.
public enum ProcessRunner {
    public struct Result: Sendable {
        public let status: Int32
        public let stdout: Data
        public let stderr: Data
        public let timedOut: Bool

        public var succeeded: Bool { !timedOut && status == 0 }
        public var stdoutText: String { String(data: stdout, encoding: .utf8) ?? "" }
        public var stderrText: String { String(data: stderr, encoding: .utf8) ?? "" }
    }

    private final class Buffer: @unchecked Sendable {
        var data = Data()
    }

    /// - Throws: 실행 파일을 띄우지 못했을 때만. 실패 종료·시간 초과는 `Result` 로 돌려준다.
    public static func run(_ executable: String, _ arguments: [String], timeout: TimeInterval = 10) throws -> Result {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: executable)
        p.arguments = arguments
        p.standardInput = FileHandle.nullDevice
        let outPipe = Pipe()
        let errPipe = Pipe()
        p.standardOutput = outPipe
        p.standardError = errPipe

        let exited = DispatchSemaphore(value: 0)
        p.terminationHandler = { _ in exited.signal() }
        try p.run()

        let out = Buffer()
        let err = Buffer()
        let readers = DispatchGroup()
        for (pipe, buffer) in [(outPipe, out), (errPipe, err)] {
            readers.enter()
            DispatchQueue.global(qos: .utility).async {
                buffer.data = pipe.fileHandleForReading.readDataToEndOfFile()
                readers.leave()
            }
        }

        var timedOut = false
        if exited.wait(timeout: .now() + timeout) == .timedOut {
            timedOut = true
            p.terminate()
            if exited.wait(timeout: .now() + 1) == .timedOut {
                kill(p.processIdentifier, SIGKILL)
                exited.wait()
            }
        }
        // 자식이 넘긴 핸들을 손자가 쥐고 있으면 EOF 가 늦을 수 있다 — 읽기도 오래 기다리지 않는다.
        _ = readers.wait(timeout: .now() + 2)

        return Result(status: p.terminationStatus, stdout: out.data, stderr: err.data, timedOut: timedOut)
    }
}
