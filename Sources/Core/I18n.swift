import Foundation

/// 타입세이프 user-facing string 키. 모든 NSLocalizedString lookup 의 단일 진입점.
public enum L {
    // MARK: menu
    public static var menuKeepAwake: String       { lookup("menu.keepAwake") }
    public static var menuClosedLid: String       { lookup("menu.closedLid") }
    public static var menuNewSession: String      { lookup("menu.newSession") }
    public static var menuSettings: String        { lookup("menu.settings") }
    public static var menuQuit: String            { lookup("menu.quit") }
    public static var menuAttach: String          { lookup("menu.attach") }
    public static var menuPreview: String         { lookup("menu.preview") }
    public static var menuKill: String            { lookup("menu.kill") }
    public static var menuOpenTemplates: String   { lookup("menu.openTemplates") }
    public static var menuReloadTemplates: String { lookup("menu.reloadTemplates") }

    // MARK: closed-lid
    public static var closedLidDuration: String      { lookup("closedLid.duration") }
    public static var closedLidDuration30m: String   { lookup("closedLid.duration.30m") }
    public static var closedLidDuration1h: String    { lookup("closedLid.duration.1h") }
    public static var closedLidDuration4h: String    { lookup("closedLid.duration.4h") }
    public static var closedLidDuration8h: String    { lookup("closedLid.duration.8h") }
    public static var closedLidDurationInf: String   { lookup("closedLid.duration.inf") }
    public static var closedLidStateOff: String      { lookup("closedLid.state.off") }
    public static var closedLidStateOnInf: String    { lookup("closedLid.state.onInf") }
    public static var closedLidSubtitle: String      { lookup("closedLid.subtitle") }
    public static func closedLidStateOnTimer(_ time: String) -> String {
        String(format: lookup("closedLid.state.onTimer"), time)
    }

    // MARK: keep awake
    public static var keepAwakeStateOn: String       { lookup("keepAwake.state.on") }
    public static var keepAwakeStateOff: String      { lookup("keepAwake.state.off") }
    public static var keepAwakeStateExternal: String { lookup("keepAwake.state.external") }
    public static var keepAwakeStateBoth: String     { lookup("keepAwake.state.both") }
    public static func keepAwakeExternalPrefix(_ list: String) -> String {
        String(format: lookup("keepAwake.externalPrefix"), list)
    }

    // MARK: settings
    public static var settingsOpenAtLogin: String              { lookup("settings.openAtLogin") }
    public static var settingsOpenAtLoginUnavailable: String   { lookup("settings.openAtLogin.unavailable") }
    public static var settingsClosedLidSection: String         { lookup("settings.closedLidSection") }
    public static var settingsKeepDisplayAwake: String         { lookup("settings.keepDisplayAwake") }
    public static var settingsPreventScreenSaver: String       { lookup("settings.preventScreenSaver") }
    public static var settingsLanguage: String                 { lookup("settings.language") }
    public static var settingsLanguageAuto: String             { lookup("settings.language.auto") }
    public static var settingsLanguageEn: String               { lookup("settings.language.en") }
    public static var settingsLanguageKo: String               { lookup("settings.language.ko") }
    public static var settingsRelaunchTitle: String            { lookup("settings.relaunch.title") }
    public static var settingsRelaunchBody: String             { lookup("settings.relaunch.body") }
    public static var settingsRelaunchConfirm: String          { lookup("settings.relaunch.confirm") }
    public static var settingsRelaunchCancel: String           { lookup("settings.relaunch.cancel") }

    // MARK: error / tooltip / app
    public static var errorTmuxNotConnected: String { lookup("error.tmuxNotConnected") }
    public static var tooltipIdle: String           { lookup("tooltip.idle") }
    public static var tooltipKeepAwake: String      { lookup("tooltip.keepAwake") }
    public static var tooltipClosedLid: String      { lookup("tooltip.closedLid") }
    public static var appName: String               { lookup("app.name") }

    // MARK: helper

    /// 매번 lookup — 언어 변경 후 재시작 시 새 lproj 가 적절히 적용되도록 cache 안 함.
    private static func lookup(_ key: String) -> String {
        NSLocalizedString(key, bundle: .module, comment: "")
    }
}
