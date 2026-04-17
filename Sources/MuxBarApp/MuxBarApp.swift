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
                    Task { @MainActor in
                        await appState.ensureBootstrapped()
                    }
                }
        } label: {
            MenuBarIcon(
                sessionStore: appState.sessionStore,
                awakeStore: appState.awakeStore
            )
        }
        .menuBarExtraStyle(.window)
    }

    @ViewBuilder
    private var menuContent: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            Divider()

            // 1. 세션 리스트 (메인, 스크롤 가능)
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

            Divider()

            // 2. Keep Awake 토글
            KeepAwakeMenuItem(
                sessionStore: appState.sessionStore,
                awakeStore: appState.awakeStore,
                onToggle: { appState.toggleAwake() }
            )

            Divider()

            // 3. New Session (템플릿 서브메뉴)
            NewSessionMenu(
                store: appState.templateStore,
                onRun: { appState.runTemplate($0) },
                onOpenFolder: { appState.openTemplatesFolder() },
                onReload: { appState.reloadTemplates() }
            )
            .padding(.horizontal, 8)
            .padding(.vertical, 6)

            Divider()

            // 4. 시작 시 자동 실행
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

            // 5. Quit
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
