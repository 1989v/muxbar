import SwiftUI
import Core

public struct SettingsMenu: View {
    @ObservedObject public var loginItemService: LoginItemService
    @ObservedObject public var closedLidPreferences: ClosedLidPreferences

    public init(
        loginItemService: LoginItemService,
        closedLidPreferences: ClosedLidPreferences
    ) {
        self.loginItemService = loginItemService
        self.closedLidPreferences = closedLidPreferences
    }

    public var body: some View {
        Menu {
            if loginItemService.isAvailable {
                Toggle(isOn: Binding(
                    get: { loginItemService.isEnabled },
                    set: { loginItemService.set($0) }
                )) {
                    Text("Open at Login")
                }
            } else {
                Button {} label: {
                    Text("Open at Login (install .app to enable)")
                }
                .disabled(true)
            }

            Divider()
            Text("Closed-lid mode").font(.caption).foregroundStyle(.secondary)
            Toggle(isOn: $closedLidPreferences.keepDisplayAwake) {
                Text("Keep display awake")
            }
            Toggle(isOn: $closedLidPreferences.preventScreenSaver) {
                Text("Prevent screen saver")
            }
        } label: {
            HStack(spacing: 6) {
                Image(systemName: "gearshape")
                Text("Settings")
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
        .menuStyle(.borderlessButton)
    }
}
