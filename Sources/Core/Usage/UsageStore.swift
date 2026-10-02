import Foundation
import MuxLogging

/// 메뉴바에 주간 남은 한도를 띄울 AI 목록 (UserDefaults 영구 저장, 최대 2개, 순서 유지).
@MainActor
public final class UsagePreferences: ObservableObject {
    public static let key = "usage.menuBarProviders"
    public static let maxShown = 2

    @Published public private(set) var menuBarProviders: [AIProvider] {
        didSet { defaults.set(menuBarProviders.map(\.rawValue), forKey: Self.key) }
    }

    private let defaults: UserDefaults

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        if let raw = defaults.stringArray(forKey: Self.key) {
            self.menuBarProviders = Array(raw.compactMap(AIProvider.init(rawValue:)).prefix(Self.maxShown))
        } else {
            self.menuBarProviders = [.claude, .codex]
        }
    }

    public func isShown(_ provider: AIProvider) -> Bool {
        menuBarProviders.contains(provider)
    }

    /// 켜면 뒤에 붙인다. 이미 2개면 켜지지 않는다.
    public func set(_ provider: AIProvider, shown: Bool) {
        if shown {
            guard !isShown(provider), menuBarProviders.count < Self.maxShown else { return }
            menuBarProviders.append(provider)
        } else {
            menuBarProviders.removeAll { $0 == provider }
        }
    }
}

/// 주간 한도와 이번 주 세션별 토큰을 주기적으로 읽어 UI 에 내준다.
@MainActor
public final class UsageStore: ObservableObject {
    @Published public private(set) var limits: [AIProvider: WeeklyLimit] = [:]
    @Published public private(set) var sessions: [SessionUsage] = []
    @Published public private(set) var isScanningSessions = false
    @Published public private(set) var sessionsScannedAt: Date?

    private let aggregator: UsageAggregator
    private var timer: Timer?
    private var sessionScanTask: Task<Void, Never>?
    private let logger = MuxLogging.logger("Core.UsageStore")

    /// 한도 갱신 주기. 파일 끝 몇 KB 만 읽어 가볍다.
    public static let limitInterval: TimeInterval = 60

    public init(aggregator: UsageAggregator = UsageAggregator()) {
        self.aggregator = aggregator
    }

    public func start() {
        guard timer == nil else { return }
        refreshLimits()
        timer = Timer.scheduledTimer(withTimeInterval: Self.limitInterval, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.refreshLimits() }
        }
    }

    public func refreshLimits() {
        Task {
            let limits = await aggregator.weeklyLimits()
            self.limits = limits
        }
    }

    /// 세션 집계. 첫 실행은 이번 주 로그 전체를 읽어 수 초 걸리고, 이후는 늘어난 부분만 읽는다.
    public func refreshSessions() {
        guard sessionScanTask == nil else { return }
        isScanningSessions = true
        sessionScanTask = Task {
            let limits = await aggregator.weeklyLimits()
            let now = Date()
            var since: [AIProvider: Date] = [:]
            for provider in AIProvider.allCases {
                since[provider] = limits[provider]?.windowStart(now: now) ?? now.addingTimeInterval(-WeeklyLimit.window)
            }
            let sessions = await aggregator.sessions(since: since)
            self.limits = limits
            self.sessions = sessions
            self.sessionsScannedAt = Date()
            self.isScanningSessions = false
            self.sessionScanTask = nil
            logger.info("usage sessions scanned: \(sessions.count)")
        }
    }

    /// 메뉴바 표기 — 고른 순서대로 남은 %를 `|` 로 잇는다. 관측값이 없는 AI 는 `–`.
    public func menuBarText(for providers: [AIProvider], now: Date = Date()) -> String? {
        guard !providers.isEmpty else { return nil }
        return providers
            .map { limits[$0].map { String($0.remainingPercent(now: now)) } ?? "–" }
            .joined(separator: "|")
    }
}
