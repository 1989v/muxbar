import SwiftUI
import Core

public struct SessionRowView: View {
    public let session: TmuxSession
    public let onAttach: () -> Void
    public let onKill: () -> Void

    public init(session: TmuxSession, onAttach: @escaping () -> Void, onKill: @escaping () -> Void) {
        self.session = session
        self.onAttach = onAttach
        self.onKill = onKill
    }

    public var body: some View {
        HStack(spacing: 8) {
            Image(systemName: session.isAttached ? "circle.fill" : "circle")
                .foregroundStyle(session.isAttached ? .green : .secondary)
                .font(.system(size: 8))

            VStack(alignment: .leading, spacing: 2) {
                Text(session.id)
                    .font(.system(.body, design: .monospaced))
                if let cwd = session.workingDirectory {
                    Text(cwd)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
            }

            Spacer(minLength: 8)

            Text("\(session.windowCount)w")
                .font(.caption)
                .foregroundStyle(.secondary)

            Menu {
                Button("Attach") { onAttach() }
                Button("Kill", role: .destructive) { onKill() }
            } label: {
                Image(systemName: "ellipsis")
            }
            .menuStyle(.borderlessButton)
            .fixedSize()
        }
        .padding(.vertical, 2)
    }
}
