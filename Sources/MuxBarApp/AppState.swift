import Foundation
import SwiftUI
import Core
import TmuxKit
import TerminalLauncher
import MuxLogging

@MainActor
public final class AppState: ObservableObject {
    public let sessionStore: SessionStore
    public let awakeStore: AwakeStore
    public let terminalAdapter: TerminalAdapter?
    public private(set) var controlClient: ControlClient?

    private let logger = MuxLogging.logger("MuxBarApp.AppState")

    public init() {
        self.sessionStore = SessionStore()
        self.awakeStore = AwakeStore()

        if let tmuxPath = TmuxPath.resolve() {
            self.terminalAdapter = TerminalAdapter(tmuxPath: tmuxPath)
        } else {
            self.terminalAdapter = nil
        }
    }

    public func bootstrap() async {
        do {
            let client = try ControlClient()
            self.controlClient = client
            try await client.bootstrap()
            sessionStore.bind(to: client)
            logger.info("Bootstrap 완료")
        } catch {
            sessionStore.apply(error: "bootstrap 실패: \(error.localizedDescription)")
            sessionStore.apply(connectionState: .failed(reason: error.localizedDescription))
            logger.error("Bootstrap 실패: \(error.localizedDescription)")
        }
    }

    public func attach(_ session: TmuxSession, using app: TerminalApp = .terminal) {
        guard let adapter = terminalAdapter else {
            sessionStore.apply(error: "tmux 바이너리 없음")
            return
        }
        Task {
            do {
                try await adapter.attach(sessionName: session.id, using: app)
            } catch {
                sessionStore.apply(error: "attach 실패: \(error.localizedDescription)")
            }
        }
    }

    public func kill(_ session: TmuxSession) {
        guard let client = controlClient else { return }
        Task {
            await sessionStore.kill(session, via: client)
        }
    }

    public func toggleAwake() {
        guard let client = controlClient else { return }
        Task {
            await awakeStore.toggle(in: sessionStore, via: client)
        }
    }
}
