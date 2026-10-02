import SwiftUI
import AppKit
import Core

/// 세션별 토큰 목록을 띄우는 독립 창. 메뉴 팝오버는 안의 탭을 누르면 메뉴 바깥 클릭으로 처리돼
/// 닫혀 버려서, 사용자가 닫을 때까지 남는 창으로 연다. 창은 하나만 두고 다시 열면 앞으로 가져온다.
@MainActor
public enum SessionUsageWindow {
    private static var window: NSWindow?

    public static func show(store: UsageStore) {
        if window == nil {
            let w = NSWindow(contentViewController: NSHostingController(rootView: SessionUsageView(store: store)))
            w.title = L.usageShowSessions
            w.styleMask = [.titled, .closable, .miniaturizable]
            w.isReleasedWhenClosed = false
            w.center()
            window = w
        }
        // 메뉴바 전용 앱(LSUIElement)이라 활성화하지 않으면 창이 다른 앱 뒤에 뜬다
        NSApp.activate(ignoringOtherApps: true)
        window?.makeKeyAndOrderFront(nil)
        store.refreshSessions()
    }
}
