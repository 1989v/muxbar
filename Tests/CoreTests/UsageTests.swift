import XCTest
@testable import Core

final class UsageTests: XCTestCase {
    private var root: URL!
    private var paths: UsagePaths!

    override func setUpWithError() throws {
        root = FileManager.default.temporaryDirectory.appendingPathComponent("muxbar-usage-\(UUID().uuidString)")
        paths = UsagePaths(
            claudeProjects: root.appendingPathComponent("claude/projects"),
            claudeRateLimits: root.appendingPathComponent("claude/rate-limits.json"),
            codexSessions: root.appendingPathComponent("codex/sessions"),
            codexSessionIndex: root.appendingPathComponent("codex/session_index.jsonl")
        )
        try FileManager.default.createDirectory(at: paths.claudeProjects, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: paths.codexSessions, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: root)
    }

    private func write(_ lines: [String], to url: URL) throws {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try (lines.joined(separator: "\n") + "\n").write(to: url, atomically: true, encoding: .utf8)
    }

    private func append(_ line: String, to url: URL) throws {
        let handle = try FileHandle(forWritingTo: url)
        try handle.seekToEnd()
        try handle.write(contentsOf: Data((line + "\n").utf8))
        try handle.close()
    }

    private func claudeAssistant(id: String, at ts: String, input: Int, output: Int, read: Int, write: Int) -> String {
        """
        {"type":"assistant","timestamp":"\(ts)","cwd":"/work/repo","message":{"id":"\(id)","usage":{"input_tokens":\(input),"output_tokens":\(output),"cache_read_input_tokens":\(read),"cache_creation_input_tokens":\(write)}}}
        """
    }

    private func codexTokenCount(at ts: String, input: Int, cached: Int, output: Int, used: Double = 36, resets: Int = 1_791_379_255) -> String {
        """
        {"timestamp":"\(ts)","type":"event_msg","payload":{"type":"token_count","info":{"total_token_usage":{"input_tokens":\(input),"cached_input_tokens":\(cached),"cache_write_input_tokens":0,"output_tokens":\(output)}},"rate_limits":{"limit_id":"codex","primary":{"used_percent":\(used),"window_minutes":10080,"resets_at":\(resets)},"secondary":null}}}
        """
    }

    // MARK: limits

    func test_remainingPercent_floorsAndResetsAfterResetTime() {
        let resets = Date(timeIntervalSince1970: 2_000_000)
        let limit = WeeklyLimit(provider: .codex, usedPercent: 43.6, resetsAt: resets, observedAt: resets.addingTimeInterval(-100))
        XCTAssertEqual(limit.remainingPercent(now: resets.addingTimeInterval(-1)), 56)
        XCTAssertEqual(limit.remainingPercent(now: resets), 100)
        XCTAssertEqual(limit.windowStart(now: resets.addingTimeInterval(-1)), resets.addingTimeInterval(-WeeklyLimit.window))
    }

    func test_claudeSnapshot_readsSevenDay() {
        let json = #"{"observed_at":1791000000,"rate_limits":{"five_hour":{"used_percentage":80,"resets_at":1791001000},"seven_day":{"used_percentage":44.2,"resets_at":1791300000}}}"#
        let limit = ClaudeRateLimitSnapshot.weeklyLimit(Data(json.utf8))
        XCTAssertEqual(limit?.usedPercent, 44.2)
        XCTAssertEqual(limit?.resetsAt, Date(timeIntervalSince1970: 1_791_300_000))
        XCTAssertEqual(limit?.observedAt, Date(timeIntervalSince1970: 1_791_000_000))
    }

    func test_codexLimit_picksWeeklyWindowAndIgnoresOtherLimitIds() {
        let ts = ISOTimestampParser()
        let weekly = codexTokenCount(at: "2026-10-02T08:25:20.185Z", input: 1, cached: 0, output: 1)
        XCTAssertEqual(CodexRolloutLine.weeklyLimit(Data(weekly.utf8), timestamps: ts)?.usedPercent, 36)

        let otherId = weekly.replacingOccurrences(of: #""limit_id":"codex""#, with: #""limit_id":"other""#)
        XCTAssertNil(CodexRolloutLine.weeklyLimit(Data(otherId.utf8), timestamps: ts))

        let fiveHour = weekly.replacingOccurrences(of: "10080", with: "300")
        XCTAssertNil(CodexRolloutLine.weeklyLimit(Data(fiveHour.utf8), timestamps: ts))
    }

    func test_aggregator_weeklyLimits_readsBothSources() async throws {
        try #"{"observed_at":1791000000,"rate_limits":{"seven_day":{"used_percentage":43,"resets_at":1791300000}}}"#
            .write(to: paths.claudeRateLimits, atomically: true, encoding: .utf8)
        try write([codexTokenCount(at: "2026-10-02T08:25:20Z", input: 10, cached: 0, output: 1, used: 42)],
                  to: paths.codexSessions.appendingPathComponent("2026/10/02/rollout-a.jsonl"))

        let limits = await UsageAggregator(paths: paths).weeklyLimits()
        XCTAssertEqual(limits[.claude]?.usedPercent, 43)
        XCTAssertEqual(limits[.codex]?.usedPercent, 42)
    }

    // MARK: sessions

    func test_claude_dedupesRepeatedMessageLines_mergesSubagents_andFiltersByWindow() async throws {
        let main = paths.claudeProjects.appendingPathComponent("-work-repo/sid-1.jsonl")
        try write([
            claudeAssistant(id: "old", at: "2026-09-20T00:00:00Z", input: 999, output: 999, read: 0, write: 0),
            claudeAssistant(id: "m1", at: "2026-10-01T00:00:00.123Z", input: 10, output: 5, read: 100, write: 20),
            claudeAssistant(id: "m1", at: "2026-10-01T00:00:00.123Z", input: 10, output: 5, read: 100, write: 20),
            #"{"type":"ai-title","aiTitle":"자동 제목","sessionId":"sid-1"}"#,
            #"{"type":"user","message":{"content":"no usage here"}}"#,
        ], to: main)
        try write([
            claudeAssistant(id: "s1", at: "2026-10-01T01:00:00Z", input: 1, output: 2, read: 3, write: 4),
        ], to: paths.claudeProjects.appendingPathComponent("-work-repo/sid-1/subagents/agent-x.jsonl"))

        let since = ISOTimestampParser().parse("2026-09-25T00:00:00Z")!
        let aggregator = UsageAggregator(paths: paths)
        let sessions = await aggregator.sessions(since: [.claude: since])

        XCTAssertEqual(sessions.count, 1)
        let s = try XCTUnwrap(sessions.first)
        XCTAssertEqual(s.sessionId, "sid-1")
        XCTAssertEqual(s.title, "자동 제목")
        XCTAssertEqual(s.cwd, "/work/repo")
        XCTAssertEqual(s.tokens, TokenCounts(input: 11, output: 7, cacheRead: 103, cacheWrite: 24))
    }

    func test_claude_incrementalRead_picksUpAppendedLinesAndCustomTitleWins() async throws {
        let main = paths.claudeProjects.appendingPathComponent("-work-repo/sid-2.jsonl")
        try write([claudeAssistant(id: "a", at: "2026-10-01T00:00:00Z", input: 1, output: 1, read: 0, write: 0)], to: main)
        let since = ISOTimestampParser().parse("2026-09-25T00:00:00Z")!
        let aggregator = UsageAggregator(paths: paths)
        _ = await aggregator.sessions(since: [.claude: since])

        try append(claudeAssistant(id: "b", at: "2026-10-01T02:00:00Z", input: 2, output: 2, read: 0, write: 0), to: main)
        try append(#"{"type":"custom-title","customTitle":"내 제목"}"#, to: main)
        try append(#"{"type":"ai-title","aiTitle":"자동"}"#, to: main)
        // 아직 개행이 안 붙은 쓰는 중인 줄은 다음 읽기로 미뤄져야 한다
        let handle = try FileHandle(forWritingTo: main)
        try handle.seekToEnd()
        try handle.write(contentsOf: Data(#"{"type":"assistant","timestamp":"2026-10-01T03:00:00Z""#.utf8))
        try handle.close()

        let sessions = await aggregator.sessions(since: [.claude: since])
        let s = try XCTUnwrap(sessions.first)
        XCTAssertEqual(s.tokens.total, 6)
        XCTAssertEqual(s.title, "내 제목")
    }

    func test_codex_usesCumulativeDeltaInsideWindow_andThreadName() async throws {
        let file = paths.codexSessions.appendingPathComponent("2026/10/01/rollout-x.jsonl")
        try write([
            #"{"timestamp":"2026-09-20T00:00:00Z","type":"session_meta","payload":{"id":"cx-1","cwd":"/work/other"}}"#,
            codexTokenCount(at: "2026-09-24T00:00:00Z", input: 1000, cached: 800, output: 50),
            codexTokenCount(at: "2026-10-01T00:00:00Z", input: 3000, cached: 2500, output: 150),
            codexTokenCount(at: "2026-10-01T00:00:00Z", input: 3000, cached: 2500, output: 150),
        ], to: file)
        try write([#"{"id":"cx-1","thread_name":"코덱스 작업","updated_at":"2026-10-01T00:00:00Z"}"#], to: paths.codexSessionIndex)

        let since = ISOTimestampParser().parse("2026-09-25T00:00:00Z")!
        let sessions = await UsageAggregator(paths: paths).sessions(since: [.codex: since])
        let s = try XCTUnwrap(sessions.first)
        XCTAssertEqual(s.sessionId, "cx-1")
        XCTAssertEqual(s.title, "코덱스 작업")
        XCTAssertEqual(s.cwd, "/work/other")
        // 누적 (3000-2500, 150, 2500) − 창 이전 (1000-800, 50, 800)
        XCTAssertEqual(s.tokens, TokenCounts(input: 300, output: 100, cacheRead: 1700, cacheWrite: 0))
    }

    // MARK: preferences / menu bar text

    @MainActor
    func test_preferences_capAtTwo_keepOrder_persist() {
        let defaults = UserDefaults(suiteName: "muxbar.test.usage.\(UUID().uuidString)")!
        let prefs = UsagePreferences(defaults: defaults)
        XCTAssertEqual(prefs.menuBarProviders, [.claude, .codex])
        prefs.set(.claude, shown: false)
        prefs.set(.claude, shown: true)
        XCTAssertEqual(prefs.menuBarProviders, [.codex, .claude])
        XCTAssertEqual(UsagePreferences(defaults: defaults).menuBarProviders, [.codex, .claude])
        prefs.set(.codex, shown: false)
        prefs.set(.claude, shown: false)
        XCTAssertEqual(UsagePreferences(defaults: defaults).menuBarProviders, [])
    }

    @MainActor
    func test_menuBarText_joinsRemainingInChosenOrder() async throws {
        try #"{"observed_at":1791000000,"rate_limits":{"seven_day":{"used_percentage":44,"resets_at":4102444800}}}"#
            .write(to: paths.claudeRateLimits, atomically: true, encoding: .utf8)
        let store = UsageStore(aggregator: UsageAggregator(paths: paths))
        store.refreshLimits()
        for _ in 0..<50 where store.limits.isEmpty { try await Task.sleep(nanoseconds: 20_000_000) }
        XCTAssertEqual(store.menuBarText(for: [.claude, .codex]), "56|–")
        XCTAssertEqual(store.menuBarText(for: [.codex, .claude]), "–|56")
        XCTAssertNil(store.menuBarText(for: []))
    }
}
