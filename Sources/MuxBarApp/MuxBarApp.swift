import SwiftUI
import AppKit
import Core
import Features
import TerminalLauncher
import MuxLogging
import Foundation

@main
struct MuxBarApp: App {
    @NSApplicationDelegateAdaptor(MuxBarAppDelegate.self) private var appDelegate
    @StateObject private var appState = AppState()

    init() {
        MuxLogging.bootstrap()
        MuxLogging.logger("app").info("muxbar launched")
        // 가장 이른 시점에 AppleLanguages 결정 — 이후 모든 NSLocalizedString lookup 이 적절한 lproj 사용.
        LocaleService().applyAtLaunch()
    }

    var body: some Scene {
        MenuBarExtra {
            menuContent
                .onAppear {
                    appDelegate.appState = appState
                    Task { @MainActor in
                        await appState.ensureBootstrapped()
                    }
                }
        } label: {
            MenuBarIcon(
                sessionStore: appState.sessionStore,
                awakeStore: appState.awakeStore,
                closedLidStore: appState.closedLidStore
            )
            .help(menuBarTooltip)
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

            // 2b. Closed-lid mode (KeepAwakeMenuItem 와 동일하게 외부 padding 없음 — 내부에 이미 padding 보유)
            ClosedLidMenuItem(
                store: appState.closedLidStore,
                onTurnOn: { duration in appState.turnOnClosedLid(duration: duration) },
                onTurnOff: { appState.turnOffClosedLid() }
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

            // 4. Settings (Open at Login + Closed-lid mode flags)
            SettingsMenu(
                loginItemService: appState.loginItemService,
                closedLidPreferences: appState.closedLidPreferences,
                localeService: appState.localeService
            )
            .padding(.horizontal, 8)
            .padding(.vertical, 6)

            Divider()

            // 5. Quit
            Button("Quit muxbar") { NSApplication.shared.terminate(nil) }
                .keyboardShortcut("q")
                .padding(.horizontal, 8)
                .padding(.vertical, 6)
        }
        .frame(width: 320)
    }

    /// 메뉴바 아이콘 hover tooltip — 현재 활성 모드 안내.
    private var menuBarTooltip: String {
        if appState.closedLidStore.state.isOn {
            return "muxbar — Closed-lid mode active (system sleep blocked)"
        }
        if appState.awakeStore.isAwake(in: appState.sessionStore) {
            return "muxbar — Keep Awake active (caffeinate running)"
        }
        return "muxbar — tmux session manager"
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
