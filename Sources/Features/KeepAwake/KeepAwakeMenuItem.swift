import SwiftUI
import Core

public struct KeepAwakeMenuItem: View {
    @ObservedObject public var sessionStore: SessionStore
    @ObservedObject public var awakeStore: AwakeStore
    public let onToggle: () -> Void

    public init(sessionStore: SessionStore, awakeStore: AwakeStore, onToggle: @escaping () -> Void) {
        self.sessionStore = sessionStore
        self.awakeStore = awakeStore
        self.onToggle = onToggle
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack {
                Image(systemName: isAwake ? "cup.and.saucer.fill" : "cup.and.saucer")
                    .foregroundStyle(isAwake ? .yellow : .secondary)
                Text("Keep Awake")
                Spacer()
                if awakeStore.isToggling {
                    ProgressView().scaleEffect(0.6)
                } else {
                    Text(source.label)
                        .font(.caption)
                        .foregroundStyle(isAwake ? .green : .secondary)
                }
            }
            if case .external = source, !externalSessionList.isEmpty {
                Text("external: \(externalSessionList)")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            } else if case .both = source {
                Text("external: \(externalSessionList)")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .contentShape(Rectangle())
        .onTapGesture { onToggle() }
    }

    private var isAwake: Bool {
        awakeStore.isAwake(in: sessionStore)
    }

    private var source: AwakeStore.Source {
        awakeStore.source(in: sessionStore)
    }

    private var externalSessionList: String {
        sessionStore.caffeinateStatus.tmuxSessions
            .filter { $0 != AwakeStore.awakeSessionName }
            .joined(separator: ", ")
    }
}
