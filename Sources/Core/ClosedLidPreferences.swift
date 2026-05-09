import Foundation

/// Closed-lid mode 의 사용자 토글 옵션 (UserDefaults 영구 저장).
/// 디폴트는 둘 다 false — 기존 동작(`caffeinate -is`)과 동일.
@MainActor
public final class ClosedLidPreferences: ObservableObject {
    public static let keyDisplay = "closedLid.keepDisplayAwake"
    public static let keyScreensaver = "closedLid.preventScreenSaver"

    /// `caffeinate -d` (display sleep 차단). lid open 상태에서 화면 안 끄고 싶을 때.
    @Published public var keepDisplayAwake: Bool {
        didSet { defaults.set(keepDisplayAwake, forKey: Self.keyDisplay) }
    }

    /// `caffeinate -u` (declareUserActivity, idle timer 리셋). screensaver / lock screen 발동 차단.
    @Published public var preventScreenSaver: Bool {
        didSet { defaults.set(preventScreenSaver, forKey: Self.keyScreensaver) }
    }

    private let defaults: UserDefaults

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        self.keepDisplayAwake = defaults.bool(forKey: Self.keyDisplay)
        self.preventScreenSaver = defaults.bool(forKey: Self.keyScreensaver)
    }

    /// 현재 prefs 에 따른 caffeinate 명령. base flag 는 항상 `-is`.
    public func caffeinateCommand() -> String {
        var flags = "is"
        if keepDisplayAwake { flags += "d" }
        if preventScreenSaver { flags += "u" }
        return "caffeinate -\(flags)"
    }
}
