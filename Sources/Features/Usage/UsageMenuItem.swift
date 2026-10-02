import SwiftUI
import Core

/// 메뉴 안의 AI 주간 한도 행 + 세션별 토큰 열기 버튼.
public struct UsageMenuItem: View {
    @ObservedObject public var store: UsageStore

    public init(store: UsageStore) {
        self.store = store
    }

    /// AI 를 하나도 안 쓰면 아무것도 그리지 않는다(아래 구분선 포함).
    public var body: some View {
        if store.hasAnyAI {
            section
            Divider()
        }
    }

    private var section: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(L.usageSection).font(.caption).foregroundStyle(.secondary)
            ForEach(store.activeProviders) { provider in
                row(provider)
            }
            if store.claudeStatuslineMissing {
                Text(L.usageClaudeHint)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            SessionUsageMenu(store: store)
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

    /// 점유율 — 소수 첫째 자리까지라 목록 합이 100% 에서 크게 벗어나 보이지 않는다
    static func share(_ ratio: Double) -> String {
        if ratio > 0, ratio < 0.001 { return "<0.1%" }
        return String(format: "%.1f%%", ratio * 100)
    }

    /// 주간 한도 % (0...100 값)
    static func limitShare(_ percent: Double) -> String {
        if percent > 0, percent < 0.1 { return "<0.1%" }
        return String(format: "%.1f%%", percent)
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
