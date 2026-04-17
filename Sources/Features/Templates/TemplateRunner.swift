import Foundation
import Core
import TmuxKit
import MuxLogging

@MainActor
public final class TemplateRunner {
    private let logger = MuxLogging.logger("Features.TemplateRunner")

    public init() {}

    /// 템플릿을 실행. 세션 이름은 hint 기반 unique 이름 생성.
    public func run(template: Template, via client: ControlClient, existingSessions: [TmuxSession]) async throws -> String {
        let sessionName = uniqueName(base: template.sessionNameHint, existing: existingSessions)

        // 첫 window 는 new-session 으로 동시 생성
        guard let firstWindow = template.windows.first else {
            throw TemplateError.emptyTemplate
        }

        // new-session + 첫 윈도우 생성
        let firstCommand = firstWindow.command
        _ = try await client.send(.newSession(name: sessionName, command: firstCommand))

        // 나머지 window 는 new-window 로 추가
        for window in template.windows.dropFirst() {
            var cmd = "new-window -t \(shellQuote(sessionName)) -n \(shellQuote(window.name))"
            if let wcmd = window.command {
                cmd += " \(shellQuote(wcmd))"
            }
            _ = try await client.sendRaw(cmd)
        }

        logger.info("template '\(template.name)' → session '\(sessionName)'")
        return sessionName
    }

    private func uniqueName(base: String, existing: [TmuxSession]) -> String {
        let existingIds = Set(existing.map(\.id))
        if !existingIds.contains(base) { return base }
        for i in 2...99 {
            let candidate = "\(base)-\(i)"
            if !existingIds.contains(candidate) { return candidate }
        }
        return "\(base)-\(Int.random(in: 100...999))"
    }

    private func shellQuote(_ s: String) -> String {
        "\"" + s.replacingOccurrences(of: "\"", with: "\\\"") + "\""
    }
}

public enum TemplateError: Error, Equatable {
    case emptyTemplate
    case sessionCreateFailed(String)
}
