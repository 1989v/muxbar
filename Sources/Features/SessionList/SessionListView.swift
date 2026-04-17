import SwiftUI
import Core

public struct SessionListView: View {
    @ObservedObject public var store: SessionStore
    public let onAttach: (TmuxSession) -> Void
    public let onKill: (TmuxSession) -> Void
    public let onPreview: (TmuxSession) -> Void

    /// 한 번에 보이는 최대 row 수 (그 이상은 스크롤)
    public var visibleRowLimit: Int = 5

    public init(
        store: SessionStore,
        onAttach: @escaping (TmuxSession) -> Void,
        onKill: @escaping (TmuxSession) -> Void,
        onPreview: @escaping (TmuxSession) -> Void,
        visibleRowLimit: Int = 5
    ) {
        self.store = store
        self.onAttach = onAttach
        self.onKill = onKill
        self.onPreview = onPreview
        self.visibleRowLimit = visibleRowLimit
    }

    public var body: some View {
        if store.userVisibleSessions.isEmpty {
            Text(placeholderText)
                .font(.caption)
                .foregroundStyle(.secondary)
                .padding(.vertical, 8)
                .padding(.horizontal, 8)
                .frame(maxWidth: .infinity, alignment: .leading)
        } else {
            let rowHeight: CGFloat = 40
            ScrollView(.vertical, showsIndicators: store.userVisibleSessions.count > visibleRowLimit) {
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(store.userVisibleSessions) { session in
                        SessionRowView(
                            session: session,
                            onAttach: { onAttach(session) },
                            onKill: { onKill(session) },
                            onPreview: { onPreview(session) }
                        )
                        if session.id != store.userVisibleSessions.last?.id {
                            Divider()
                        }
                    }
                }
                .padding(.horizontal, 8)
            }
            .frame(maxHeight: CGFloat(min(store.userVisibleSessions.count, visibleRowLimit)) * rowHeight)
        }
    }

    private var placeholderText: String {
        switch store.connectionState {
        case .connecting:  return "Connecting to tmux…"
        case .connected:   return "No sessions yet. Use New Session to create one."
        case .disconnected: return "Disconnected"
        case .reconnecting: return "Reconnecting…"
        case .failed(let reason): return "Connection failed: \(reason)"
        }
    }
}
