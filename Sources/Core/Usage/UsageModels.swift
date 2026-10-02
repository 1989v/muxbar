import Foundation

/// 사용량을 읽어 오는 AI 도구.
public enum AIProvider: String, CaseIterable, Codable, Sendable, Identifiable {
    case claude
    case codex

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .claude: return "Claude"
        case .codex: return "Codex"
        }
    }
}

/// 토큰 4종. 공급자마다 input 정의가 달라서(Codex 는 input 안에 cached 포함) 파싱 시점에 이 모양으로 맞춘다.
public struct TokenCounts: Equatable, Sendable {
    /// 캐시를 거치지 않은 입력
    public var input: Int
    public var output: Int
    public var cacheRead: Int
    public var cacheWrite: Int

    public init(input: Int = 0, output: Int = 0, cacheRead: Int = 0, cacheWrite: Int = 0) {
        self.input = input
        self.output = output
        self.cacheRead = cacheRead
        self.cacheWrite = cacheWrite
    }

    public static let zero = TokenCounts()

    public var total: Int { input + output + cacheRead + cacheWrite }

    /// 입력 전체(캐시 포함) 중 캐시 읽기 비율. 입력이 없으면 nil.
    public var cacheReadRatio: Double? {
        let inputs = input + cacheRead + cacheWrite
        return inputs > 0 ? Double(cacheRead) / Double(inputs) : nil
    }

    public static func + (lhs: TokenCounts, rhs: TokenCounts) -> TokenCounts {
        TokenCounts(
            input: lhs.input + rhs.input,
            output: lhs.output + rhs.output,
            cacheRead: lhs.cacheRead + rhs.cacheRead,
            cacheWrite: lhs.cacheWrite + rhs.cacheWrite
        )
    }

    /// 누적값 차이. 누적이 줄어드는 경우(세션 재시작 등)는 0 으로 막는다.
    public static func - (lhs: TokenCounts, rhs: TokenCounts) -> TokenCounts {
        TokenCounts(
            input: max(0, lhs.input - rhs.input),
            output: max(0, lhs.output - rhs.output),
            cacheRead: max(0, lhs.cacheRead - rhs.cacheRead),
            cacheWrite: max(0, lhs.cacheWrite - rhs.cacheWrite)
        )
    }
}

/// 주간(7일) 한도 관측값.
public struct WeeklyLimit: Equatable, Sendable {
    public static let window: TimeInterval = 7 * 24 * 3600

    public let provider: AIProvider
    public let usedPercent: Double
    public let resetsAt: Date
    /// 이 값을 기록한 시각. Claude 는 statusline 이 마지막으로 그려진 시각이라 오래됐을 수 있다.
    public let observedAt: Date

    public init(provider: AIProvider, usedPercent: Double, resetsAt: Date, observedAt: Date) {
        self.provider = provider
        self.usedPercent = usedPercent
        self.resetsAt = resetsAt
        self.observedAt = observedAt
    }

    /// 남은 한도(%). 관측 뒤 리셋 시각이 지났으면 새 주가 시작된 것이라 100.
    public func remainingPercent(now: Date = Date()) -> Int {
        if now >= resetsAt { return 100 }
        return max(0, min(100, Int((100 - usedPercent).rounded(.down))))
    }

    /// 현재 주간 창의 시작 시각.
    public func windowStart(now: Date = Date()) -> Date {
        now >= resetsAt ? resetsAt : resetsAt.addingTimeInterval(-Self.window)
    }
}

/// AI 세션 하나의 이번 주 사용량.
public struct SessionUsage: Identifiable, Equatable, Sendable {
    public var id: String { "\(provider.rawValue):\(sessionId)" }
    public let provider: AIProvider
    public let sessionId: String
    public let title: String?
    public let cwd: String?
    public let tokens: TokenCounts
    public let lastActivity: Date

    public init(provider: AIProvider, sessionId: String, title: String?, cwd: String?, tokens: TokenCounts, lastActivity: Date) {
        self.provider = provider
        self.sessionId = sessionId
        self.title = title
        self.cwd = cwd
        self.tokens = tokens
        self.lastActivity = lastActivity
    }
}

public extension Array where Element == SessionUsage {
    /// 이 목록 전체 토큰 중 각 세션의 비율(0...1, 합 1). 키는 `SessionUsage.id`.
    /// 화면에 보이는 목록을 넘기면 어느 필터에서든 합이 100% 가 된다.
    func shareOfTotal() -> [String: Double] {
        let total = reduce(0) { $0 + $1.tokens.total }
        var shares: [String: Double] = [:]
        for s in self {
            shares[s.id] = total > 0 ? Double(s.tokens.total) / Double(total) : 0
        }
        return shares
    }
}
