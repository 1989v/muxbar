import Foundation
import ServiceManagement
import MuxLogging

@MainActor
public final class LoginItemService: ObservableObject {
    @Published public private(set) var isEnabled: Bool

    private let logger = MuxLogging.logger("Features.LoginItem")

    /// SMAppService.mainApp 은 번들된 .app 에서만 유효. unbundled 실행 시 호출 회피.
    public static var isBundled: Bool {
        Bundle.main.bundleIdentifier != nil
    }

    /// UI 에서 "시작 시 자동 실행" 토글을 노출할지 결정.
    public var isAvailable: Bool { Self.isBundled }

    public init() {
        self.isEnabled = Self.isBundled ? (SMAppService.mainApp.status == .enabled) : false
    }

    public func refresh() {
        guard Self.isBundled else { return }
        isEnabled = (SMAppService.mainApp.status == .enabled)
    }

    public func set(_ enabled: Bool) {
        guard Self.isBundled else { return }
        do {
            if enabled {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
            refresh()
        } catch {
            logger.error("login item toggle failed: \(error.localizedDescription)")
        }
    }
}
