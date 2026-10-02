import SwiftUI
import Core

/// 메뉴 안의 AI 주간 한도 행 + 세션별 토큰 열기 버튼.
public struct UsageMenuItem: View {
    @ObservedObject public var store: UsageStore
    public let onShowSessions: () -> Void

    public init(store: UsageStore, onShowSessions: @escaping () -> Void) {
        self.store = store
        self.onShowSessions = onShowSessions
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(L.usageSection).font(.caption).foregroundStyle(.secondary)
            ForEach(AIProvider.allCases) { provider in
                row(provider)
            }
            if store.limits[.claude] == nil {
                Text(L.usageClaudeHint)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Button(action: onShowSessions) {
                HStack(spacing: 6) {
                    Image(systemName: "chart.bar.doc.horizontal")
                    Text(L.usageShowSessions)
                    Spacer()
                    Image(systemName: "chevron.right")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .padding(.top, 2)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
    }

    @ViewBuilder
    private func row(_ provider: AIProvider) -> some View {
        let now = Date()
        HStack {
            Text(provider.displayName)
            Spacer()
            if let limit = store.limits[provider] {
                VStack(alignment: .trailing, spacing: 0) {
                    Text(L.usageRemaining(limit.remainingPercent(now: now)))
                        .font(.callout.monospacedDigit())
                        .foregroundStyle(color(limit.remainingPercent(now: now)))
                    Text("\(L.usageResets(UsageFormat.dateTime(limit.resetsAt))) · \(L.usageObserved(UsageFormat.relative(limit.observedAt, now: now)))")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            } else {
                Text(L.usageNoData).font(.caption).foregroundStyle(.secondary)
            }
        }
    }

    private func color(_ remaining: Int) -> Color {
        if remaining <= 15 { return .red }
        if remaining <= 40 { return .orange }
        return .primary
    }
}

/// 토큰·시각 표기 공용.
enum UsageFormat {
    static func tokens(_ n: Int) -> String {
        let value = Double(n)
        switch value {
        case 1_000_000_000...: return String(format: "%.1fB", value / 1_000_000_000)
        case 1_000_000...: return String(format: "%.1fM", value / 1_000_000)
        case 1_000...: return String(format: "%.1fK", value / 1_000)
        default: return "\(n)"
        }
    }

    static func percent(_ ratio: Double?) -> String {
        guard let ratio else { return "–" }
        if ratio > 0, ratio < 0.01 { return "<1%" }
        return "\(Int((ratio * 100).rounded()))%"
    }

    static func dateTime(_ date: Date) -> String {
        let f = DateFormatter()
        f.setLocalizedDateFormatFromTemplate("MMdd HH:mm")
        return f.string(from: date)
    }

    static func relative(_ date: Date, now: Date) -> String {
        let f = RelativeDateTimeFormatter()
        f.unitsStyle = .short
        return f.localizedString(for: date, relativeTo: now)
    }
}
