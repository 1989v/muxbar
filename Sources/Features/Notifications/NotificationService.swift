import Foundation
import UserNotifications
import Core
import MuxLogging

@MainActor
public final class NotificationService {
    private let logger = MuxLogging.logger("Features.NotificationService")
    private var lastActivityByPane: [String: Date] = [:]
    private var priorSessions: [String] = []
    private var idleCheckTimer: Task<Void, Never>?

    public var idleThresholdMinutes: Int = 30
    public var notifyOnCrash: Bool = true

    public init() {}

    /// UNUserNotificationCenter 는 bundle identifier 있는 .app 번들에서만 동작.
    /// raw `swift run` / `./build/release/muxbar` 실행 시에는 nil → 크래시 방지 위해 skip.
    private var canUseNotifications: Bool {
        Bundle.main.bundleIdentifier != nil
    }

    public func requestAuthorization() {
        guard canUseNotifications else { return }
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { [weak self] _, error in
            if let error {
                self?.logger.warning("notification auth error: \(error.localizedDescription)")
            }
        }
    }

    public func startIdleCheck(store: SessionStore) {
        idleCheckTimer?.cancel()
        idleCheckTimer = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 60_000_000_000) // 1분
                guard let self else { break }
                await self.checkIdle(store: store)
            }
        }
    }

    public func stopIdleCheck() {
        idleCheckTimer?.cancel()
    }

    /// 세션 목록 변경 감지. priorSessions 와 비교해 사라진 세션이 있으면 crash 알림.
    public func observeSessionsChange(current: [TmuxSession]) {
        let currentIds = current.map(\.id)
        let disappeared = Set(priorSessions).subtracting(currentIds)
            .filter { !$0.hasPrefix("_muxbar-") }

        if notifyOnCrash && !priorSessions.isEmpty && !disappeared.isEmpty {
            for sessionId in disappeared {
                postNotification(
                    title: "세션 종료됨",
                    body: "tmux 세션 '\(sessionId)' 이 종료되었습니다"
                )
            }
        }
        priorSessions = currentIds
    }

    public func recordPaneActivity(paneId: String) {
        lastActivityByPane[paneId] = .now
    }

    /// Closed-lid 타이머 만료(또는 AC/lid 자동 트리거) 시 pmset 복원에 password 가 필요할 때 호출.
    /// NOPASSWD 룰 미설정 사용자에게 stale pmset 상태를 알리는 용도.
    public func postPmsetRestoreNeeded() {
        postNotification(
            title: "Closed lid mode 종료됨",
            body: "pmset 복원에 비밀번호가 필요합니다. 메뉴에서 OFF 토글로 다시 시도하세요."
        )
    }

    private func checkIdle(store: SessionStore) async {
        // v0.1: idle 검출만, dedupe 는 v0.2 에서 처리 예정 (로그 노이즈 방지 위해 알림 미발송)
        _ = store
        _ = idleThresholdMinutes
    }

    private func postNotification(title: String, body: String) {
        guard canUseNotifications else { return }
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .default
        let request = UNNotificationRequest(
            identifier: UUID().uuidString,
            content: content,
            trigger: nil
        )
        UNUserNotificationCenter.current().add(request)
    }
}
