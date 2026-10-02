import SwiftUI
import Core

/// 이번 주 AI 세션별 토큰 목록. 많이 쓴 세션부터.
public struct SessionUsageView: View {
    @ObservedObject public var store: UsageStore
    @State private var filter: AIProvider?

    public init(store: UsageStore) {
        self.store = store
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(L.usageShowSessions).font(.headline)
                Spacer()
                if store.isScanningSessions {
                    ProgressView().scaleEffect(0.6)
                    Text(L.usageScanning).font(.caption).foregroundStyle(.secondary)
                } else {
                    Button { store.refreshSessions() } label: { Image(systemName: "arrow.clockwise") }
                        .buttonStyle(.borderless)
                }
            }
            Picker("", selection: $filter) {
                Text(L.usageFilterAll).tag(AIProvider?.none)
                ForEach(providersInSessions) { Text($0.displayName).tag(AIProvider?.some($0)) }
            }
            .pickerStyle(.segmented)
            .labelsHidden()

            let rows = visible
            let shares = store.sessions.shareOfProviderTotal()
            Text(L.usageTotal(UsageFormat.tokens(rows.reduce(0) { $0 + $1.tokens.total }), sessions: rows.count))
                .font(.caption)
                .foregroundStyle(.secondary)

            if rows.isEmpty {
                Spacer()
                Text(store.isScanningSessions ? L.usageScanning : L.usageEmpty)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity)
                Spacer()
            } else {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 0) {
                        ForEach(rows) { session in
                            SessionUsageRow(session: session, share: shares[session.id] ?? 0)
                            Divider()
                        }
                    }
                }
            }
        }
        .padding(12)
        .frame(width: 440, height: 480)
        .onAppear { store.refreshSessions() }
    }

    private var providersInSessions: [AIProvider] {
        AIProvider.allCases.filter { p in store.sessions.contains { $0.provider == p } }
    }

    private var visible: [SessionUsage] {
        guard let filter else { return store.sessions }
        return store.sessions.filter { $0.provider == filter }
    }
}

private struct SessionUsageRow: View {
    let session: SessionUsage
    /// 같은 AI 의 이번 주 전체 토큰 중 이 세션의 비율
    let share: Double

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            Text(session.provider == .claude ? "C" : "X")
                .font(.caption2.bold())
                .frame(width: 16, height: 16)
                .background(Circle().fill(session.provider == .claude ? Color.orange.opacity(0.25) : Color.blue.opacity(0.25)))
            VStack(alignment: .leading, spacing: 2) {
                Text(session.title ?? L.usageUntitled)
                    .lineLimit(1)
                    .truncationMode(.tail)
                Text(subtitle)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            Spacer(minLength: 8)
            VStack(alignment: .trailing, spacing: 2) {
                HStack(spacing: 6) {
                    Text(UsageFormat.percent(share))
                        .font(.callout.monospacedDigit().bold())
                        .foregroundStyle(.secondary)
                    Text(UsageFormat.tokens(session.tokens.total))
                        .font(.callout.monospacedDigit().bold())
                }
                ProgressView(value: share)
                    .progressViewStyle(.linear)
                    .frame(width: 90)
                    .tint(session.provider == .claude ? .orange : .blue)
                    .help(L.usageShareHelp(session.provider.displayName))
                Text(L.usageDetail(output: UsageFormat.tokens(session.tokens.output),
                                   cache: UsageFormat.percent(session.tokens.cacheReadRatio)))
                    .font(.caption2.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 6)
        .help("\(session.sessionId)\n\(session.cwd ?? "")")
    }

    private var subtitle: String {
        let place = session.cwd.map { URL(fileURLWithPath: $0).lastPathComponent } ?? "–"
        return "\(place) · \(UsageFormat.dateTime(session.lastActivity))"
    }
}
