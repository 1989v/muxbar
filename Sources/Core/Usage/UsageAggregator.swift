import Foundation

/// 로컬 로그 위치. 테스트에서 임시 디렉터리로 바꿔 끼운다.
public struct UsagePaths: Sendable {
    public let claudeProjects: URL
    public let claudeRateLimits: URL
    public let codexSessions: URL
    public let codexSessionIndex: URL

    public init(claudeProjects: URL, claudeRateLimits: URL, codexSessions: URL, codexSessionIndex: URL) {
        self.claudeProjects = claudeProjects
        self.claudeRateLimits = claudeRateLimits
        self.codexSessions = codexSessions
        self.codexSessionIndex = codexSessionIndex
    }

    public static var standard: UsagePaths {
        let home = FileManager.default.homeDirectoryForCurrentUser
        return UsagePaths(
            claudeProjects: home.appendingPathComponent(".claude/projects"),
            claudeRateLimits: home.appendingPathComponent(".claude/rate-limits.json"),
            codexSessions: home.appendingPathComponent(".codex/sessions"),
            codexSessionIndex: home.appendingPathComponent(".codex/session_index.jsonl")
        )
    }
}

/// 주간 한도 읽기 + 세션별 토큰 집계.
///
/// 로그가 GB 단위라 파일마다 읽은 위치를 기억해 두고 늘어난 부분만 읽는다.
/// 기간 밖으로 밀려난 기록은 집계할 때 시각으로 거른다.
public actor UsageAggregator {
    private struct ClaudeFile {
        var offset: UInt64 = 0
        var size: UInt64 = 0
        let sessionId: String
        var records: [String: (Date, TokenCounts)] = [:]
        var aiTitle: String?
        var customTitle: String?
        var cwd: String?
    }

    private struct CodexFile {
        var offset: UInt64 = 0
        var size: UInt64 = 0
        /// 집계 단위 세션 id. 하위 에이전트 rollout 은 자기 meta 다음에 부모 meta 가 이어 나오므로
        /// 마지막 meta 의 id 가 곧 부모(최상위) 세션이다. 토큰 누적은 파일마다 자기 몫이다.
        var sessionId: String
        var cwd: String?
        /// (시각, 누적 토큰) — 시각 순
        var points: [(Date, TokenCounts)] = []
    }

    private let paths: UsagePaths
    private let timestamps = ISOTimestampParser()
    private var claudeFiles: [String: ClaudeFile] = [:]
    private var codexFiles: [String: CodexFile] = [:]

    public init(paths: UsagePaths = .standard) {
        self.paths = paths
    }

    // MARK: weekly limits

    /// 최근 7일 안에 관측된 한도만 돌려준다. 없는 AI 는 쓰지 않는 것으로 본다.
    public func weeklyLimits(now: Date = Date()) -> [AIProvider: WeeklyLimit] {
        var result: [AIProvider: WeeklyLimit] = [:]
        // statusline 파일은 Claude 를 그만 써도 남아 있으므로 관측 시각으로 거른다
        if let data = try? Data(contentsOf: paths.claudeRateLimits),
           let limit = ClaudeRateLimitSnapshot.weeklyLimit(data),
           limit.observedAt >= now.addingTimeInterval(-WeeklyLimit.window) {
            result[.claude] = limit
        }
        if let limit = latestCodexLimit() {
            result[.codex] = limit
        }
        return result
    }

    /// 최근 7일 안에 Claude Code 를 썼는가. 한도 파일이 없을 때 statusline 설정 안내를 띄울지 판단한다.
    /// 하위 에이전트까지 뒤지지 않고 `<root>/<project>/*.jsonl` 만 본다.
    public func hasRecentClaudeTranscripts(now: Date = Date()) -> Bool {
        let fm = FileManager.default
        let since = now.addingTimeInterval(-WeeklyLimit.window)
        guard let projects = try? fm.contentsOfDirectory(at: paths.claudeProjects, includingPropertiesForKeys: nil) else { return false }
        for project in projects {
            guard let files = try? fm.contentsOfDirectory(at: project, includingPropertiesForKeys: [.contentModificationDateKey]) else { continue }
            for file in files where file.pathExtension == "jsonl" {
                if let mtime = try? file.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate,
                   mtime >= since { return true }
            }
        }
        return false
    }

    /// 가장 최근에 쓰인 rollout 몇 개의 끝부분에서 마지막 주간 한도를 찾는다.
    private func latestCodexLimit() -> WeeklyLimit? {
        let recent = jsonlFiles(under: paths.codexSessions, modifiedSince: Date().addingTimeInterval(-WeeklyLimit.window))
            .sorted { $0.mtime > $1.mtime }
            .prefix(5)
        for file in recent {
            var found: WeeklyLimit?
            JSONLReader.readTailLinesReversed(at: file.url, maxBytes: 1 << 20) { line in
                found = CodexRolloutLine.weeklyLimit(line, timestamps: timestamps)
                return found != nil
            }
            if let found { return found }
        }
        return nil
    }

    // MARK: sessions

    /// `since[provider]` 이후 사용량을 AI 세션 단위로 모은다. 사용량 0 인 세션은 뺀다.
    public func sessions(since: [AIProvider: Date]) -> [SessionUsage] {
        var result: [SessionUsage] = []
        if let start = since[.claude] {
            result += claudeSessions(since: start)
        }
        if let start = since[.codex] {
            result += codexSessions(since: start)
        }
        return result.sorted { $0.tokens.total > $1.tokens.total }
    }

    private func claudeSessions(since start: Date) -> [SessionUsage] {
        let files = jsonlFiles(under: paths.claudeProjects, modifiedSince: start)
        // 기간 밖으로 밀려난 파일은 기억에서 지운다
        let seen = Set(files.map(\.url.path))
        claudeFiles = claudeFiles.filter { seen.contains($0.key) }
        for file in files {
            guard let sessionId = Self.claudeSessionId(for: file.url, root: paths.claudeProjects) else { continue }
            var state = claudeFiles[file.url.path] ?? ClaudeFile(sessionId: sessionId)
            if file.size < state.offset { state = ClaudeFile(sessionId: sessionId) }  // 잘렸거나 교체됨
            guard file.size != state.size || state.offset == 0 else { continue }
            state.offset = JSONLReader.readLines(at: file.url, from: state.offset) { line in
                switch ClaudeTranscriptLine.parse(line, timestamps: timestamps) {
                case let .usage(id, ts, tokens, cwd):
                    state.records[id] = (ts, tokens)
                    if let cwd { state.cwd = cwd }
                case let .title(title, isCustom):
                    if isCustom { state.customTitle = title } else { state.aiTitle = title }
                case nil:
                    break
                }
            }
            state.size = file.size
            claudeFiles[file.url.path] = state
        }

        // 하위 에이전트 파일은 부모 세션으로 합친다. 메시지 id 가 서로 달라 단순 합산으로 충분하다.
        struct Acc { var tokens = TokenCounts.zero; var last = Date.distantPast; var title: String?; var cwd: String? }
        var bySession: [String: Acc] = [:]
        for state in claudeFiles.values {
            var acc = bySession[state.sessionId] ?? Acc()
            for (ts, tokens) in state.records.values where ts >= start {
                acc.tokens = acc.tokens + tokens
                acc.last = max(acc.last, ts)
            }
            if let title = state.customTitle ?? state.aiTitle { acc.title = title }
            if acc.cwd == nil { acc.cwd = state.cwd }
            bySession[state.sessionId] = acc
        }
        return bySession.compactMap { id, acc in
            guard acc.tokens.total > 0 else { return nil }
            return SessionUsage(provider: .claude, sessionId: id, title: acc.title, cwd: acc.cwd,
                                tokens: acc.tokens, lastActivity: acc.last)
        }
    }

    private func codexSessions(since start: Date) -> [SessionUsage] {
        let files = jsonlFiles(under: paths.codexSessions, modifiedSince: start)
        let seen = Set(files.map(\.url.path))
        codexFiles = codexFiles.filter { seen.contains($0.key) }
        for file in files {
            var state = codexFiles[file.url.path] ?? CodexFile(sessionId: file.url.deletingPathExtension().lastPathComponent)
            if file.size < state.offset { state = CodexFile(sessionId: state.sessionId) }
            guard file.size != state.size || state.offset == 0 else { continue }
            state.offset = JSONLReader.readLines(at: file.url, from: state.offset) { line in
                switch CodexRolloutLine.parse(line, timestamps: timestamps) {
                case let .meta(id, cwd):
                    state.sessionId = id
                    state.cwd = cwd
                case let .cumulative(ts, tokens):
                    state.points.append((ts, tokens))
                case nil:
                    break
                }
            }
            state.size = file.size
            codexFiles[file.url.path] = state
        }

        // 하위 에이전트 파일은 부모 세션으로 합친다(Claude 와 같은 규칙)
        struct Acc { var tokens = TokenCounts.zero; var last = Date.distantPast; var cwd: String? }
        var bySession: [String: Acc] = [:]
        for state in codexFiles.values {
            guard let last = state.points.last, last.0 >= start else { continue }
            let baseline = state.points.last(where: { $0.0 < start })?.1 ?? .zero
            var acc = bySession[state.sessionId] ?? Acc()
            acc.tokens = acc.tokens + (last.1 - baseline)
            acc.last = max(acc.last, last.0)
            if acc.cwd == nil { acc.cwd = state.cwd }
            bySession[state.sessionId] = acc
        }
        let names = codexThreadNames()
        return bySession.compactMap { id, acc in
            guard acc.tokens.total > 0 else { return nil }
            return SessionUsage(provider: .codex, sessionId: id, title: names[id],
                                cwd: acc.cwd, tokens: acc.tokens, lastActivity: acc.last)
        }
    }

    private func codexThreadNames() -> [String: String] {
        var names: [String: String] = [:]
        JSONLReader.readLines(at: paths.codexSessionIndex, from: 0) { line in
            if let entry = CodexSessionIndexLine.parse(line) { names[entry.id] = entry.name }
        }
        return names
    }

    // MARK: files

    /// `<root>/<project>/<sid>.jsonl` 은 그 세션, `<root>/<project>/<sid>/subagents/*.jsonl` 은 부모 세션 `<sid>`.
    static func claudeSessionId(for url: URL, root: URL) -> String? {
        let parts = url.standardizedFileURL.pathComponents
        let rootParts = root.standardizedFileURL.pathComponents
        guard parts.count > rootParts.count else { return nil }
        let rel = Array(parts[rootParts.count...])
        switch rel.count {
        case 2: return url.deletingPathExtension().lastPathComponent
        case 4 where rel[2] == "subagents": return rel[1]
        default: return nil
        }
    }

    private struct FileInfo { let url: URL; let size: UInt64; let mtime: Date }

    private func jsonlFiles(under root: URL, modifiedSince start: Date) -> [FileInfo] {
        let keys: [URLResourceKey] = [.contentModificationDateKey, .fileSizeKey, .isRegularFileKey]
        guard let enumerator = FileManager.default.enumerator(at: root, includingPropertiesForKeys: keys) else { return [] }
        var files: [FileInfo] = []
        for case let url as URL in enumerator where url.pathExtension == "jsonl" {
            guard let values = try? url.resourceValues(forKeys: Set(keys)),
                  values.isRegularFile == true,
                  let mtime = values.contentModificationDate, mtime >= start else { continue }
            files.append(FileInfo(url: url, size: UInt64(values.fileSize ?? 0), mtime: mtime))
        }
        return files
    }
}
