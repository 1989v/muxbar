import Foundation

/// JSONL 한 줄씩 읽기. 쓰는 중인 마지막 줄(개행 전)은 넘기지 않고 다음 읽기로 미룬다.
public enum JSONLReader {
    /// `offset` 부터 끝까지 완결된 줄을 `body` 에 넘기고, 다 읽은 바이트 위치를 돌려준다.
    @discardableResult
    public static func readLines(at url: URL, from offset: UInt64, _ body: (Data) -> Void) -> UInt64 {
        guard let handle = try? FileHandle(forReadingFrom: url) else { return offset }
        defer { try? handle.close() }
        do { try handle.seek(toOffset: offset) } catch { return offset }

        var consumed = offset
        var carry = Data()
        while let chunk = try? handle.read(upToCount: 4 << 20), !chunk.isEmpty {
            carry.append(chunk)
            var start = carry.startIndex
            while let newline = carry[start...].firstIndex(of: 0x0A) {
                body(carry[start..<newline])
                start = carry.index(after: newline)
            }
            consumed += UInt64(start - carry.startIndex)
            carry = Data(carry[start...])
        }
        return consumed
    }

    /// 파일 끝 `maxBytes` 안의 완결된 줄을 뒤에서부터 넘긴다. `body` 가 true 를 돌려주면 멈춘다.
    public static func readTailLinesReversed(at url: URL, maxBytes: UInt64, _ body: (Data) -> Bool) {
        guard let handle = try? FileHandle(forReadingFrom: url) else { return }
        defer { try? handle.close() }
        guard let size = try? handle.seekToEnd() else { return }
        let start = size > maxBytes ? size - maxBytes : 0
        guard (try? handle.seek(toOffset: start)) != nil,
              let data = try? handle.readToEnd() else { return }
        var lines = data.split(separator: 0x0A, omittingEmptySubsequences: true)
        // 중간에서 잘린 첫 줄은 버린다
        if start > 0, !lines.isEmpty { lines.removeFirst() }
        for line in lines.reversed() where body(Data(line)) { return }
    }
}

/// 트랜스크립트·rollout 의 ISO8601 시각 파서. 소수초 유무가 섞여 있어 둘 다 시도한다.
public struct ISOTimestampParser {
    private let fractional: ISO8601DateFormatter
    private let plain: ISO8601DateFormatter

    public init() {
        fractional = ISO8601DateFormatter()
        fractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        plain = ISO8601DateFormatter()
        plain.formatOptions = [.withInternetDateTime]
    }

    public func parse(_ string: String?) -> Date? {
        guard let string else { return nil }
        return fractional.date(from: string) ?? plain.date(from: string)
    }
}

/// Claude Code 트랜스크립트(`~/.claude/projects/**.jsonl`) 한 줄 해석.
public enum ClaudeTranscriptLine: Equatable {
    /// 응답 한 건. 같은 응답이 콘텐츠 블록마다 여러 줄로 반복 기록되고 앞 줄은 스트리밍 중간값일 수 있어,
    /// `messageId` 별로 마지막 줄의 값을 써야 한다.
    case usage(messageId: String, timestamp: Date, tokens: TokenCounts, cwd: String?)
    case title(String, isCustom: Bool)

    private static let usageMarker = Data("\"usage\"".utf8)
    private static let titleMarker = Data("-title\"".utf8)

    public static func parse(_ line: Data, timestamps: ISOTimestampParser) -> ClaudeTranscriptLine? {
        let hasUsage = line.range(of: usageMarker) != nil
        guard hasUsage || line.range(of: titleMarker) != nil,
              let obj = (try? JSONSerialization.jsonObject(with: line)) as? [String: Any] else { return nil }

        switch obj["type"] as? String {
        case "assistant":
            guard let message = obj["message"] as? [String: Any],
                  let id = message["id"] as? String,
                  let usage = message["usage"] as? [String: Any],
                  let ts = timestamps.parse(obj["timestamp"] as? String) else { return nil }
            let tokens = TokenCounts(
                input: intValue(usage["input_tokens"]),
                output: intValue(usage["output_tokens"]),
                cacheRead: intValue(usage["cache_read_input_tokens"]),
                cacheWrite: intValue(usage["cache_creation_input_tokens"])
            )
            return .usage(messageId: id, timestamp: ts, tokens: tokens, cwd: obj["cwd"] as? String)
        case "custom-title":
            return (obj["customTitle"] as? String).map { .title($0, isCustom: true) }
        case "ai-title":
            return (obj["aiTitle"] as? String).map { .title($0, isCustom: false) }
        default:
            return nil
        }
    }
}

/// Codex rollout(`~/.codex/sessions/**/rollout-*.jsonl`) 한 줄 해석.
public enum CodexRolloutLine: Equatable {
    case meta(sessionId: String, cwd: String?)
    /// 세션 누적 토큰. 같은 값이 반복 기록되므로 합산하지 않고 누적의 차이로 쓴다.
    case cumulative(timestamp: Date, tokens: TokenCounts)

    private static let metaMarker = Data("\"session_meta\"".utf8)
    private static let tokenMarker = Data("\"token_count\"".utf8)

    public static func parse(_ line: Data, timestamps: ISOTimestampParser) -> CodexRolloutLine? {
        let isMeta = line.range(of: metaMarker) != nil
        guard isMeta || line.range(of: tokenMarker) != nil,
              let obj = (try? JSONSerialization.jsonObject(with: line)) as? [String: Any],
              let payload = obj["payload"] as? [String: Any] else { return nil }

        if obj["type"] as? String == "session_meta" {
            guard let id = payload["id"] as? String else { return nil }
            return .meta(sessionId: id, cwd: payload["cwd"] as? String)
        }
        guard payload["type"] as? String == "token_count",
              let info = payload["info"] as? [String: Any],
              let total = info["total_token_usage"] as? [String: Any],
              let ts = timestamps.parse(obj["timestamp"] as? String) else { return nil }
        let input = intValue(total["input_tokens"])
        let cached = intValue(total["cached_input_tokens"])
        let tokens = TokenCounts(
            input: max(0, input - cached),
            output: intValue(total["output_tokens"]),
            cacheRead: cached,
            cacheWrite: intValue(total["cache_write_input_tokens"])
        )
        return .cumulative(timestamp: ts, tokens: tokens)
    }

    /// `token_count` 줄의 주간(10080분) 한도. primary/secondary 어느 쪽이든 주간 창을 고른다.
    public static func weeklyLimit(_ line: Data, timestamps: ISOTimestampParser) -> WeeklyLimit? {
        guard line.range(of: tokenMarker) != nil,
              let obj = (try? JSONSerialization.jsonObject(with: line)) as? [String: Any],
              let payload = obj["payload"] as? [String: Any],
              let limits = payload["rate_limits"] as? [String: Any] else { return nil }
        if let limitId = limits["limit_id"] as? String, limitId != "codex" { return nil }
        let observed = timestamps.parse(obj["timestamp"] as? String) ?? Date()
        for key in ["primary", "secondary"] {
            guard let window = limits[key] as? [String: Any],
                  intValue(window["window_minutes"]) == 10080,
                  let used = doubleValue(window["used_percent"]),
                  let resets = doubleValue(window["resets_at"]) else { continue }
            return WeeklyLimit(provider: .codex, usedPercent: used,
                               resetsAt: Date(timeIntervalSince1970: resets), observedAt: observed)
        }
        return nil
    }
}

/// statusline 이 남기는 `~/.claude/rate-limits.json` — `{observed_at, rate_limits}`.
public enum ClaudeRateLimitSnapshot {
    public static func weeklyLimit(_ data: Data) -> WeeklyLimit? {
        guard let obj = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
              let limits = obj["rate_limits"] as? [String: Any],
              let week = limits["seven_day"] as? [String: Any],
              let used = doubleValue(week["used_percentage"]),
              let resets = doubleValue(week["resets_at"]) else { return nil }
        let observed = doubleValue(obj["observed_at"]).map { Date(timeIntervalSince1970: $0) } ?? Date()
        return WeeklyLimit(provider: .claude, usedPercent: used,
                           resetsAt: Date(timeIntervalSince1970: resets), observedAt: observed)
    }
}

/// Codex `session_index.jsonl` 한 줄 — 세션 id 와 스레드 이름.
public enum CodexSessionIndexLine {
    public static func parse(_ line: Data) -> (id: String, name: String)? {
        guard let obj = (try? JSONSerialization.jsonObject(with: line)) as? [String: Any],
              let id = obj["id"] as? String,
              let name = obj["thread_name"] as? String, !name.isEmpty else { return nil }
        return (id, name)
    }
}

private func intValue(_ any: Any?) -> Int {
    (any as? NSNumber)?.intValue ?? 0
}

private func doubleValue(_ any: Any?) -> Double? {
    if let n = any as? NSNumber { return n.doubleValue }
    if let s = any as? String { return Double(s) }
    return nil
}
