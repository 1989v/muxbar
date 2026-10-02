import SwiftUI
import AppKit
import Core

/// 이번 주 세션별 토큰 — Settings·New Session 과 같은 펼침 메뉴.
/// AI 별 구역으로 나누고 비율은 구역 안 합계 기준(구역마다 합 100%).
public struct SessionUsageMenu: View {
    @ObservedObject public var store: UsageStore

    /// 구역마다 보여 줄 세션 수. 나머지는 "외 N개" 한 줄로 묶는다.
    /// 메뉴가 화면 높이를 넘으면 macOS 가 스크롤 모드로 바꿔 위로 되돌아가기 어렵다 —
    /// 두 구역을 합쳐도 한 화면에 들어오게 10줄로 둔다.
    static let rowLimit = 10

    public init(store: UsageStore) {
        self.store = store
    }

    public var body: some View {
        Menu {
            if store.sessions.isEmpty {
                Text(store.isScanningSessions ? L.usageScanning : L.usageEmpty)
            }
            ForEach(AIProvider.allCases) { provider in
                let rows = store.sessions.filter { $0.provider == provider }
                if !rows.isEmpty {
                    section(provider, rows)
                }
            }
            Divider()
            Button(L.usageRefresh) { store.refreshSessions() }
        } label: {
            HStack(spacing: 6) {
                Image(systemName: "chart.bar.doc.horizontal")
                Text(L.usageShowSessions)
                Spacer()
                if store.isScanningSessions {
                    ProgressView().scaleEffect(0.5)
                }
                Image(systemName: "chevron.right")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
        .menuStyle(.borderlessButton)
    }

    @ViewBuilder
    private func section(_ provider: AIProvider, _ rows: [SessionUsage]) -> some View {
        let total = rows.reduce(0) { $0 + $1.tokens.total }
        let limit = store.limits[provider]
        // 한도를 알면 주간 한도 100% 중 세션 몫(합 = 이번 주 사용률), 모르면 구역 안 토큰 비율
        let values: [String: String] = limit.map { l in
            rows.shareOfLimit(usedPercent: l.usedPercent).mapValues(UsageFormat.limitShare)
        } ?? rows.shareOfTotal().mapValues(UsageFormat.share)
        let header = limit.map {
            L.usageSectionHeaderWithLimit(provider.displayName, used: UsageFormat.limitShare($0.usedPercent),
                                          total: UsageFormat.tokens(total), sessions: rows.count)
        } ?? L.usageSectionHeader(provider.displayName, total: UsageFormat.tokens(total), sessions: rows.count)
        Section(header) {
            ForEach(rows.prefix(Self.rowLimit)) { session in
                // 누르면 세션 id 복사 — `claude --resume <id>` 등에 붙여 넣는 용도
                Button {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(session.sessionId, forType: .string)
                } label: {
                    Text(rowText(session, value: values[session.id] ?? "–"))
                }
            }
            if rows.count > Self.rowLimit {
                Text(L.usageMore(rows.count - Self.rowLimit))
            }
        }
    }

    private func rowText(_ session: SessionUsage, value: String) -> String {
        let place = session.cwd.map { URL(fileURLWithPath: $0).lastPathComponent } ?? "–"
        let title = session.title ?? L.usageUntitled
        let clipped = title.count > 40 ? String(title.prefix(40)) + "…" : title
        return "\(value)   \(UsageFormat.tokens(session.tokens.total))   \(clipped) · \(place)"
    }
}
