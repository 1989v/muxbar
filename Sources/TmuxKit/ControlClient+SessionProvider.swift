import Foundation
import Core

extension ControlClient: SessionProvider {
    public nonisolated var events: AsyncStream<SessionProviderEvent> {
        let raw = self.rawEvents
        return AsyncStream { continuation in
            let task = Task {
                for await event in raw {
                    switch event {
                    case .sessionsChanged:
                        continuation.yield(.sessionsChanged)
                    case .exit:
                        continuation.yield(.connectionLost)
                    default:
                        break
                    }
                }
                continuation.finish()
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    public func kill(sessionName: String) async throws {
        _ = try await send(.killSession(name: sessionName))
    }

    public func createSession(name: String, command: String?) async throws {
        _ = try await send(.newSession(name: name, command: command))
    }
}
