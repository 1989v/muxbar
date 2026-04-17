import SwiftUI
import Core

public struct SettingsMenu: View {
    @ObservedObject public var loginItemService: LoginItemService

    public init(loginItemService: LoginItemService) {
        self.loginItemService = loginItemService
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
            // 향후 설정 항목은 여기 추가: Keep Awake flags, idle threshold 등
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
