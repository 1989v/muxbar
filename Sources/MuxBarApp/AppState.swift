import Foundation
import SwiftUI
import Combine
import Core
import Features
import TmuxKit
import TerminalLauncher
import MuxLogging
import HotKey

@MainActor
public final class AppState: ObservableObject {
    public let sessionStore: SessionStore
    public let awakeStore: AwakeStore
    public let previewController: PreviewController
    public let terminalAdapter: TerminalAdapter?
    public let templateRunner: TemplateRunner
    public let hotKeyCenter: HotKeyCenter
    public let notificationService: NotificationService
    public let loginItemService: LoginItemService
    public private(set) var controlClient: ControlClient?

    @Published public var previewSession: TmuxSession?

    private let logger = MuxLogging.logger("MuxBarApp.AppState")

    public init() {
        self.previewController = PreviewController()
        self.sessionStore = SessionStore()
        self.awakeStore = AwakeStore()
        self.templateRunner = TemplateRunner()
        self.hotKeyCenter = HotKeyCenter()
        self.notificationService = NotificationService()
        self.loginItemService = LoginItemService()

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
            registerHotkeys()
            notificationService.requestAuthorization()
            notificationService.startIdleCheck(store: sessionStore)
            // 세션 변경 감지 → observeSessionsChange 호출
            Task { [weak self] in
                guard let self else { return }
                for await _ in sessionStore.$sessions.values {
                    self.notificationService.observeSessionsChange(current: self.sessionStore.sessions)
                }
            }
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

    public func startPreview(for session: TmuxSession) {
        guard let client = controlClient else { return }
        previewSession = session
        previewController.start(session: session, provider: client)
    }

    public func stopPreview() {
        previewController.stop()
        previewSession = nil
    }

    public func runTemplate(_ template: Template) {
        guard let client = controlClient else { return }
        Task {
            do {
                let sessionName = try await templateRunner.run(
                    template: template,
                    via: client,
                    existingSessions: sessionStore.sessions
                )
                sessionStore.apply(error: nil)
                _ = sessionName
            } catch {
                sessionStore.apply(error: "템플릿 실행 실패: \(error.localizedDescription)")
            }
        }
    }

    public func registerHotkeys() {
        // ⌘⇧A — Toggle Keep Awake
        hotKeyCenter.register(id: "awake", key: .a, modifiers: [.command, .shift]) { [weak self] in
            self?.toggleAwake()
        }
        // ⌘⇧1~9 — 세션 리스트 n번째 attach (간단 버전: index 순서)
        for (idx, key) in [Key.one, .two, .three, .four, .five, .six, .seven, .eight, .nine].enumerated() {
            hotKeyCenter.register(id: "favorite-\(idx+1)", key: key, modifiers: [.command, .shift]) { [weak self] in
                guard let self else { return }
                let visible = self.sessionStore.userVisibleSessions
                guard idx < visible.count else { return }
                self.attach(visible[idx])
            }
        }
    }
}
