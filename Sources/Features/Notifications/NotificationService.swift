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
        guard canUseNotifications else {
            logger.info("Unbundled 실행 감지 — UserNotifications 스킵")
            return
        }
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { [weak self] granted, error in
            if let error {
                self?.logger.warning("알림 권한 요청 오류: \(error.localizedDescription)")
            } else {
                self?.logger.info("알림 권한 granted=\(granted)")
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

    private func checkIdle(store: SessionStore) async {
        let threshold = TimeInterval(idleThresholdMinutes * 60)
        let now = Date.now
        for session in store.userVisibleSessions {
            let elapsed = now.timeIntervalSince(session.lastActivityAt)
            if elapsed > threshold {
                // 최근 10분 안에 중복 알림 방지를 위한 간단한 가드: 날짜 단위 flag 없음 → skip
                // 본격적인 dedupe 는 v0.2
                logger.info("세션 '\(session.id)' idle \(Int(elapsed / 60))분")
            }
        }
    }

    private func postNotification(title: String, body: String) {
        guard canUseNotifications else {
            logger.info("[notify skipped] \(title): \(body)")
            return
        }
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
