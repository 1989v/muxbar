import Foundation

public enum ControlEvent: Sendable, Equatable {
    case commandBegin(time: Int, cmdId: Int, flags: Int)
    case commandEnd(time: Int, cmdId: Int, flags: Int)
    case commandError(time: Int, cmdId: Int, flags: Int)

    /// Guard 라인 사이의 응답 본문 (파서가 하나로 합쳐서 전달)
    case commandOutput(cmdId: Int, body: String)

    case paneOutput(paneId: String, data: Data)

    case sessionChanged(sessionId: String, name: String)
    case sessionRenamed(sessionId: String, name: String)
    case sessionsChanged

    case windowAdd(windowId: String)
    case windowClose(windowId: String)
    case windowRenamed(windowId: String, name: String)
    case windowPaneChanged(windowId: String, paneId: String)

    case paneModeChanged(paneId: String)

    case pause(paneId: String)
    case continueFlow(paneId: String)

    case exit

    /// 알 수 없는/미지원 라인 (로깅용)
    case unknown(line: String)
}
