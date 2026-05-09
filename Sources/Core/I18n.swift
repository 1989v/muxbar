import Foundation
import AppKit

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
    public static var menuSectionBuiltIn: String  { lookup("menu.sectionBuiltIn") }
    public static var menuSectionCustom: String   { lookup("menu.sectionCustom") }

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

    // MARK: status (connection placeholders)
    public static var statusConnecting: String      { lookup("status.connecting") }
    public static var statusConnectedEmpty: String  { lookup("status.connected.empty") }
    public static var statusDisconnected: String    { lookup("status.disconnected") }
    public static var statusReconnecting: String    { lookup("status.reconnecting") }
    public static func statusFailed(_ reason: String) -> String {
        String(format: lookup("status.failed"), reason)
    }

    // MARK: error / tooltip / app
    public static var errorTmuxNotConnected: String   { lookup("error.tmuxNotConnected") }
    public static var errorTmuxBinaryNotFound: String { lookup("error.tmuxBinaryNotFound") }
    public static func errorBootstrapFailed(_ desc: String) -> String {
        String(format: lookup("error.bootstrapFailed"), desc)
    }
    public static func errorAttachFailed(_ desc: String) -> String {
        String(format: lookup("error.attachFailed"), desc)
    }
    public static func errorTemplateRunFailed(_ desc: String) -> String {
        String(format: lookup("error.templateRunFailed"), desc)
    }
    public static var tooltipIdle: String             { lookup("tooltip.idle") }
    public static var tooltipKeepAwake: String        { lookup("tooltip.keepAwake") }
    public static var tooltipClosedLid: String        { lookup("tooltip.closedLid") }
    public static var appName: String                 { lookup("app.name") }

    // MARK: helper

    /// 매번 lookup — 언어 변경 후 재시작 시 새 lproj 가 적절히 적용되도록 cache 안 함.
    private static func lookup(_ key: String) -> String {
        NSLocalizedString(key, bundle: .module, comment: "")
    }
}

/// Settings 의 Language picker 모델.
public enum LanguagePreference: String, Codable, CaseIterable, Identifiable, Sendable {
    case auto
    case en
    case ko
    public var id: String { rawValue }
}

/// 언어 preference 저장 + AppleLanguages override + relaunch.
@MainActor
public final class LocaleService: ObservableObject {
    public static let key = "muxbar.language"
    private static let appleLanguagesKey = "AppleLanguages"

    @Published public var preference: LanguagePreference {
        didSet { defaults.set(preference.rawValue, forKey: Self.key) }
    }
    private let defaults: UserDefaults

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        let raw = defaults.string(forKey: Self.key) ?? LanguagePreference.auto.rawValue
        self.preference = LanguagePreference(rawValue: raw) ?? .auto
    }

    /// 앱 시작 시 호출. preference 따라 AppleLanguages 결정.
    /// .auto 면 시스템 그대로 (AppleLanguages key 제거), 나머진 forced override.
    public func applyAtLaunch() {
        switch preference {
        case .auto:
            defaults.removeObject(forKey: Self.appleLanguagesKey)
        case .en:
            defaults.set(["en"], forKey: Self.appleLanguagesKey)
        case .ko:
            defaults.set(["ko"], forKey: Self.appleLanguagesKey)
        }
    }

    /// Settings 에서 변경 후 호출 — preference 적용 + 새 인스턴스 띄우고 현재 종료.
    public func applyAndRelaunch() {
        applyAtLaunch()
        let url = Bundle.main.bundleURL
        let config = NSWorkspace.OpenConfiguration()
        config.createsNewApplicationInstance = true
        NSWorkspace.shared.openApplication(at: url, configuration: config) { _, _ in
            DispatchQueue.main.async { NSApp.terminate(nil) }
        }
    }
}
