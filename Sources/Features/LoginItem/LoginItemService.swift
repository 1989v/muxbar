import Foundation
import ServiceManagement
import MuxLogging

@MainActor
public final class LoginItemService: ObservableObject {
    @Published public private(set) var isEnabled: Bool

    private let logger = MuxLogging.logger("Features.LoginItem")

    /// SMAppService.mainApp 은 번들된 .app 에서만 유효. unbundled 실행 시 호출 회피.
    private static var isBundled: Bool {
        Bundle.main.bundleIdentifier != nil
    }

    public init() {
        self.isEnabled = Self.isBundled ? (SMAppService.mainApp.status == .enabled) : false
    }

    public func refresh() {
        guard Self.isBundled else { return }
        isEnabled = (SMAppService.mainApp.status == .enabled)
    }

    public func set(_ enabled: Bool) {
        guard Self.isBundled else {
            logger.info("Unbundled — Login Item 토글 스킵")
            return
        }
        do {
            if enabled {
                try SMAppService.mainApp.register()
                logger.info("Login Item 등록됨")
            } else {
                try SMAppService.mainApp.unregister()
                logger.info("Login Item 해제됨")
            }
            refresh()
        } catch {
            logger.error("Login Item 토글 실패: \(error.localizedDescription)")
        }
    }
}
