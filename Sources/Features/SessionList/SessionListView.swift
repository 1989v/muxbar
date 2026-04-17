import SwiftUI
import Core

public struct SessionListView: View {
    @ObservedObject public var store: SessionStore
    public let onAttach: (TmuxSession) -> Void
    public let onKill: (TmuxSession) -> Void

    public init(store: SessionStore, onAttach: @escaping (TmuxSession) -> Void, onKill: @escaping (TmuxSession) -> Void) {
        self.store = store
        self.onAttach = onAttach
        self.onKill = onKill
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            if store.userVisibleSessions.isEmpty {
                Text(placeholderText)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding(.vertical, 4)
            } else {
                ForEach(store.userVisibleSessions) { session in
                    SessionRowView(
                        session: session,
                        onAttach: { onAttach(session) },
                        onKill: { onKill(session) }
                    )
                    Divider()
                }
            }
        }
        .padding(.horizontal, 8)
    }

    private var placeholderText: String {
        switch store.connectionState {
        case .connecting:  return "tmux 연결 중…"
        case .connected:   return "세션 없음. tmux new-session 으로 시작"
        case .disconnected: return "연결 끊김"
        case .reconnecting: return "재연결 중…"
        case .failed(let reason): return "연결 실패: \(reason)"
        }
    }
}
