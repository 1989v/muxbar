import SwiftUI
import Core

public struct MenuBarIcon: View {
    @ObservedObject public var sessionStore: SessionStore
    @ObservedObject public var awakeStore: AwakeStore

    public init(sessionStore: SessionStore, awakeStore: AwakeStore) {
        self.sessionStore = sessionStore
        self.awakeStore = awakeStore
    }

    public var body: some View {
        HStack(spacing: 3) {
            Image(systemName: iconName)
                .foregroundStyle(iconColor)
            if sessionCount > 0 {
                Text("\(sessionCount)")
                    .font(.system(size: 12, weight: .semibold))
                    .monospacedDigit()
            }
        }
    }

    /// active 시 `cup.and.heat.waves.fill` (SF Symbols 5+) — 김 나오는 커피잔.
    /// fallback 으로 `cup.and.saucer.fill`. 시스템이 없는 심볼은 빈 아이콘으로 렌더.
    private var iconName: String {
        if isAwake {
            return "cup.and.heat.waves.fill"
        } else {
            return "cup.and.saucer"
        }
    }

    private var iconColor: Color {
        isAwake ? .orange : .primary
    }

    private var isAwake: Bool {
        awakeStore.isAwake(in: sessionStore)
    }

    private var sessionCount: Int {
        sessionStore.userVisibleSessions.count
    }
}
