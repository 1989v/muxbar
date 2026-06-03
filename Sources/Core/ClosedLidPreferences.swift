import Foundation

/// Closed-lid mode 의 사용자 토글 옵션 (UserDefaults 영구 저장).
/// 디폴트는 둘 다 false — 기존 동작(`caffeinate -is`)과 동일.
@MainActor
public final class ClosedLidPreferences: ObservableObject {
    public static let keyDisplay = "closedLid.keepDisplayAwake"
    public static let keyScreensaver = "closedLid.preventScreenSaver"
    public static let keyAlsoStopKeepAwakeOnEnd = "closedLid.alsoStopKeepAwakeOnEnd"
    public static let keyLastCustomMinutes = "closedLid.lastCustomMinutes"
    public static let keySleepDisabledByUs = "closedLid.sleepDisabledByUs"

    /// `caffeinate -d` (display sleep 차단). lid open 상태에서 화면 안 끄고 싶을 때.
    @Published public var keepDisplayAwake: Bool {
        didSet { defaults.set(keepDisplayAwake, forKey: Self.keyDisplay) }
    }

    /// `caffeinate -u` (declareUserActivity, idle timer 리셋). screensaver / lock screen 발동 차단.
    @Published public var preventScreenSaver: Bool {
        didSet { defaults.set(preventScreenSaver, forKey: Self.keyScreensaver) }
    }

    /// closed-lid 종료 시점에 Keep Awake 도 함께 OFF. 사용자가 시작 시점에 체크.
    /// 모든 종료 경로(manual/timer/AC/lid)에 일관 적용 — "시작 시 의식적 동의" 가 기준.
    @Published public var alsoStopKeepAwakeOnEnd: Bool {
        didSet { defaults.set(alsoStopKeepAwakeOnEnd, forKey: Self.keyAlsoStopKeepAwakeOnEnd) }
    }

    /// Custom duration picker 의 마지막 입력 값(분). 다음 picker open 시 prefill.
    @Published public var lastCustomMinutes: Int {
        didSet { defaults.set(lastCustomMinutes, forKey: Self.keyLastCustomMinutes) }
    }

    /// "우리가 `pmset disablesleep 1` 을 켜둔 채 아직 복원 못 했다" 는 영구 마커.
    /// disableSystemSleep 성공 시 true, enableSystemSleep 성공 시 false. 크래시/강제종료/
    /// auto-trigger 복원 실패로 `SleepDisabled=1` 이 stranded 됐는지를 다음 실행에서 판별하는 근거.
    public var sleepDisabledByUs: Bool {
        didSet { defaults.set(sleepDisabledByUs, forKey: Self.keySleepDisabledByUs) }
    }

    private let defaults: UserDefaults

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        self.keepDisplayAwake = defaults.bool(forKey: Self.keyDisplay)
        self.preventScreenSaver = defaults.bool(forKey: Self.keyScreensaver)
        self.alsoStopKeepAwakeOnEnd = defaults.bool(forKey: Self.keyAlsoStopKeepAwakeOnEnd)
        let savedMinutes = defaults.integer(forKey: Self.keyLastCustomMinutes)
        self.lastCustomMinutes = savedMinutes > 0 ? savedMinutes : 90
        self.sleepDisabledByUs = defaults.bool(forKey: Self.keySleepDisabledByUs)
    }

    /// 현재 prefs 에 따른 caffeinate 명령. base flag 는 항상 `-is`.
    public func caffeinateCommand() -> String {
        var flags = "is"
        if keepDisplayAwake { flags += "d" }
        if preventScreenSaver { flags += "u" }
        return "caffeinate -\(flags)"
    }
}
