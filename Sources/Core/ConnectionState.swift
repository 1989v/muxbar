import Foundation

public enum ConnectionState: Sendable, Equatable {
    case disconnected
    case connecting(attempt: Int)
    case connected
    case reconnecting(nextAttemptIn: TimeInterval)
    case failed(reason: String)
}
