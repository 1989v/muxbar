import Foundation
import ServiceManagement
import MuxLogging

@MainActor
public final class LoginItemService: ObservableObject {
    @Published public private(set) var isEnabled: Bool

    private let logger = MuxLogging.logger("Features.LoginItem")

    public init() {
        self.isEnabled = (SMAppService.mainApp.status == .enabled)
    }

    public func refresh() {
        isEnabled = (SMAppService.mainApp.status == .enabled)
    }

    public func set(_ enabled: Bool) {
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
