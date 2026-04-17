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
        HStack {
            Image(systemName: isAwake ? "cup.and.saucer.fill" : "cup.and.saucer")
                .foregroundStyle(isAwake ? .yellow : .secondary)
            Text("Keep Awake")
            Spacer()
            if awakeStore.isToggling {
                ProgressView().scaleEffect(0.6)
            } else {
                Text(isAwake ? "ON" : "OFF")
                    .font(.caption)
                    .foregroundStyle(isAwake ? .green : .secondary)
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
}
