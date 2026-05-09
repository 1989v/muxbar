import SwiftUI
import Core

public struct SettingsMenu: View {
    @ObservedObject public var loginItemService: LoginItemService
    @ObservedObject public var closedLidPreferences: ClosedLidPreferences
    @ObservedObject public var localeService: LocaleService

    @State private var showingRelaunchAlert = false
    @State private var pendingPreference: LanguagePreference?

    public init(
        loginItemService: LoginItemService,
        closedLidPreferences: ClosedLidPreferences,
        localeService: LocaleService
    ) {
        self.loginItemService = loginItemService
        self.closedLidPreferences = closedLidPreferences
        self.localeService = localeService
    }

    public var body: some View {
        Menu {
            if loginItemService.isAvailable {
                Toggle(isOn: Binding(
                    get: { loginItemService.isEnabled },
                    set: { loginItemService.set($0) }
                )) {
                    Text(L.settingsOpenAtLogin)
                }
            } else {
                Button {} label: {
                    Text(L.settingsOpenAtLoginUnavailable)
                }
                .disabled(true)
            }

            Divider()
            Text(L.settingsClosedLidSection).font(.caption).foregroundStyle(.secondary)
            Toggle(isOn: $closedLidPreferences.keepDisplayAwake) {
                Text(L.settingsKeepDisplayAwake)
            }
            Toggle(isOn: $closedLidPreferences.preventScreenSaver) {
                Text(L.settingsPreventScreenSaver)
            }

            Divider()
            Picker(selection: Binding(
                get: { localeService.preference },
                set: { newValue in
                    pendingPreference = newValue
                    showingRelaunchAlert = true
                }
            )) {
                Text(L.settingsLanguageAuto).tag(LanguagePreference.auto)
                Text(L.settingsLanguageEn).tag(LanguagePreference.en)
                Text(L.settingsLanguageKo).tag(LanguagePreference.ko)
            } label: {
                Text(L.settingsLanguage)
            }
        } label: {
            HStack(spacing: 6) {
                Image(systemName: "gearshape")
                Text(L.menuSettings)
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
        .menuStyle(.borderlessButton)
        .alert(L.settingsRelaunchTitle, isPresented: $showingRelaunchAlert) {
            Button(L.settingsRelaunchConfirm) {
                if let p = pendingPreference {
                    localeService.preference = p
                    localeService.applyAndRelaunch()
                }
                pendingPreference = nil
            }
            Button(L.settingsRelaunchCancel, role: .cancel) {
                pendingPreference = nil
            }
        } message: {
            Text(L.settingsRelaunchBody)
        }
    }
}
