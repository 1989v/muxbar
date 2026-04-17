import Foundation
import Core
import TmuxKit

@MainActor
public final class TemplateRunner {
    public init() {}

    /// 템플릿을 실행. hint 기반 unique 세션 이름 생성.
    public func run(template: Template, via client: ControlClient, existingSessions: [TmuxSession]) async throws -> String {
        guard let firstWindow = template.windows.first else {
            throw TemplateError.emptyTemplate
        }

        let sessionName = uniqueName(base: template.sessionNameHint, existing: existingSessions)
        _ = try await client.send(.newSession(name: sessionName, command: firstWindow.command))

        for window in template.windows.dropFirst() {
            var cmd = "new-window -t \(shellQuote(sessionName)) -n \(shellQuote(window.name))"
            if let wcmd = window.command {
                cmd += " \(shellQuote(wcmd))"
            }
            _ = try await client.sendRaw(cmd)
        }

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
