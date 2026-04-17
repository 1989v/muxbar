import Foundation
import Combine
import MuxLogging

/// pane 별 원시 출력 바이트를 누적/보관하는 스토어.
/// TmuxKit 의 %output 이벤트 / capture-pane 응답을 이 스토어에 밀어넣고,
/// 뷰는 `snapshots` 변화를 관찰해 렌더링한다.
@MainActor
public final class PaneBufferStore: ObservableObject {
    public struct Snapshot: Sendable, Equatable {
        public let paneId: String
        public let content: Data
        public let updatedAt: Date

        public init(paneId: String, content: Data, updatedAt: Date) {
            self.paneId = paneId
            self.content = content
            self.updatedAt = updatedAt
        }
    }

    @Published public private(set) var snapshots: [String: Snapshot] = [:]
    private let logger = MuxLogging.logger("Core.PaneBufferStore")
    /// 메모리 상한 — 초과 시 앞부분 절삭
    private let maxBytesPerPane: Int = 65_536

    public init() {}

    /// 외부에서 스냅샷 초기 주입 (capture-pane 결과)
    public func seed(paneId: String, data: Data) {
        snapshots[paneId] = Snapshot(paneId: paneId, content: data, updatedAt: .now)
    }

    /// %output 수신 시 append
    public func append(paneId: String, data: Data) {
        if let existing = snapshots[paneId] {
            var combined = existing.content
            combined.append(data)
            if combined.count > maxBytesPerPane {
                combined = combined.suffix(maxBytesPerPane)
            }
            snapshots[paneId] = Snapshot(paneId: paneId, content: combined, updatedAt: .now)
        } else {
            snapshots[paneId] = Snapshot(paneId: paneId, content: data, updatedAt: .now)
        }
    }

    public func snapshot(for paneId: String) -> Snapshot? {
        snapshots[paneId]
    }

    public func clear(paneId: String) {
        snapshots.removeValue(forKey: paneId)
    }

    public func clearAll() {
        snapshots.removeAll()
    }
}
