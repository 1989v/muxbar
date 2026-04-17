import Foundation

public final class ControlProtocol {
    private var buffer = ""

    // %begin 직후부터 %end/%error 전까지의 본문 누적
    private var inCommand: Bool = false
    private var commandCmdId: Int = -1
    private var commandBody: [String] = []

    public init() {}

    /// 바이트 스트림을 라인 단위로 파싱. 남은 부분 라인은 내부 버퍼에 유지.
    public func feed(_ chunk: String) -> [ControlEvent] {
        buffer += chunk
        var events: [ControlEvent] = []

        while let newlineRange = buffer.range(of: "\n") {
            let line = String(buffer[buffer.startIndex..<newlineRange.lowerBound])
            buffer.removeSubrange(buffer.startIndex...newlineRange.lowerBound)
            events.append(contentsOf: parseLine(line))
        }

        return events
    }

    private func parseLine(_ line: String) -> [ControlEvent] {
        if line.isEmpty {
            return inCommand ? [] : []
        }

        // guard lines
        if line.hasPrefix("%begin ") {
            return handleBegin(line)
        } else if line.hasPrefix("%end ") {
            return handleEnd(line, isError: false)
        } else if line.hasPrefix("%error ") {
            return handleEnd(line, isError: true)
        }

        // 커맨드 응답 본문 누적
        if inCommand {
            commandBody.append(line)
            return []
        }

        // 비동기 이벤트 (다음 Task 에서 확장)
        return parseAsyncEvent(line)
    }

    private func handleBegin(_ line: String) -> [ControlEvent] {
        guard let (time, cmdId, flags) = parseGuardArgs(line, prefix: "%begin ") else {
            return [.unknown(line: line)]
        }
        inCommand = true
        commandCmdId = cmdId
        commandBody = []
        return [.commandBegin(time: time, cmdId: cmdId, flags: flags)]
    }

    private func handleEnd(_ line: String, isError: Bool) -> [ControlEvent] {
        let prefix = isError ? "%error " : "%end "
        guard let (time, cmdId, flags) = parseGuardArgs(line, prefix: prefix) else {
            return [.unknown(line: line)]
        }
        var events: [ControlEvent] = []
        if !commandBody.isEmpty {
            let body = commandBody.joined(separator: "\n")
            events.append(.commandOutput(cmdId: cmdId, body: body))
        }
        events.append(isError
            ? .commandError(time: time, cmdId: cmdId, flags: flags)
            : .commandEnd(time: time, cmdId: cmdId, flags: flags))
        inCommand = false
        commandBody = []
        return events
    }

    private func parseGuardArgs(_ line: String, prefix: String) -> (Int, Int, Int)? {
        let rest = line.dropFirst(prefix.count)
        let parts = rest.split(separator: " ", maxSplits: 3).map(String.init)
        guard parts.count >= 3,
              let t = Int(parts[0]),
              let c = Int(parts[1]),
              let f = Int(parts[2]) else { return nil }
        return (t, c, f)
    }

    // 다음 Task 에서 구현
    fileprivate func parseAsyncEvent(_ line: String) -> [ControlEvent] {
        [.unknown(line: line)]
    }
}
