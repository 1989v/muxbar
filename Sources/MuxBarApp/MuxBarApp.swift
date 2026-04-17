import SwiftUI
import Core
import Features
import TerminalLauncher
import MuxLogging

@main
struct MuxBarApp: App {
    @StateObject private var appState = AppState()

    init() {
        MuxLogging.bootstrap()
        MuxLogging.logger("app").info("muxbar 기동")
    }

    var body: some Scene {
        MenuBarExtra {
            menuContent
                .onAppear {
                    // 메뉴가 처음 열릴 때 bootstrap 보장 (이미 됐으면 idempotent skip).
                    // .task 는 메뉴 닫힘 시 cancel 되어 listSessions 가 중간에 끊길 수 있어 detached Task 사용.
                    Task { @MainActor in
                        await appState.ensureBootstrapped()
                    }
                }
        } label: {
            Image(systemName: iconName)
        }
        .menuBarExtraStyle(.window)
    }

    private var iconName: String {
        if appState.awakeStore.isAwake(in: appState.sessionStore) {
            return "terminal.fill"
        }
        return "terminal"
    }

    @ViewBuilder
    private var menuContent: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            Divider()
            SessionListView(
                store: appState.sessionStore,
                onAttach: { appState.attach($0) },
                onKill: { appState.kill($0) },
                onPreview: { appState.startPreview(for: $0) }
            )
            .popover(
                isPresented: Binding(
                    get: { appState.previewSession != nil },
                    set: { if !$0 { appState.stopPreview() } }
                ),
                arrowEdge: .leading
            ) {
                SessionPreviewView(controller: appState.previewController)
            }
            TemplatePickerView { template in
                appState.runTemplate(template)
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            Divider()
            KeepAwakeMenuItem(
                sessionStore: appState.sessionStore,
                awakeStore: appState.awakeStore,
                onToggle: { appState.toggleAwake() }
            )
            Divider()
            Toggle(isOn: Binding(
                get: { appState.loginItemService.isEnabled },
                set: { appState.loginItemService.set($0) }
            )) {
                Text("시작 시 자동 실행")
            }
            .toggleStyle(.switch)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            Divider()
            Button("Quit muxbar") { NSApplication.shared.terminate(nil) }
                .keyboardShortcut("q")
                .padding(.horizontal, 8)
                .padding(.vertical, 6)
        }
        .frame(width: 320)
    }

    private var header: some View {
        HStack {
            Image(systemName: "terminal.fill")
            Text("muxbar")
                .font(.headline)
            Spacer()
            if case .connected = appState.sessionStore.connectionState {
                Circle().fill(.green).frame(width: 8, height: 8)
            } else {
                Circle().fill(.orange).frame(width: 8, height: 8)
            }
        }
        .padding(8)
    }
}
