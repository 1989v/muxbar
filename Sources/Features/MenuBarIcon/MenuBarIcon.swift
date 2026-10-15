import SwiftUI
import AppKit
import Core

public struct MenuBarIcon: View {
    @ObservedObject public var sessionStore: SessionStore
    @ObservedObject public var awakeStore: AwakeStore
    @ObservedObject public var closedLidStore: ClosedLidStore
    @ObservedObject public var usageStore: UsageStore
    @ObservedObject public var usagePreferences: UsagePreferences

    public init(
        sessionStore: SessionStore,
        awakeStore: AwakeStore,
        closedLidStore: ClosedLidStore,
        usageStore: UsageStore,
        usagePreferences: UsagePreferences
    ) {
        self.sessionStore = sessionStore
        self.awakeStore = awakeStore
        self.closedLidStore = closedLidStore
        self.usageStore = usageStore
        self.usagePreferences = usagePreferences
    }

    public var body: some View {
        // 아이콘 몸통 위에 주간 남은 한도("56|57"), 오른쪽 위 원 안에 세션 수.
        // closed-lid 자물쇠에는 세션 수를 달지 않는다.
        if let base = modeImage {
            Image(nsImage: LimitOverlay.image(
                base: base,
                limitText: usageStore.menuBarText(for: usagePreferences.menuBarProviders),
                sessionCount: closedLidStore.state.isOn ? 0 : sessionCount,
                color: modeColor,
                isTemplate: base.isTemplate
            ))
        } else {
            // fallback
            Image(systemName: closedLidStore.state.isOn ? "lock.fill"
                  : isAwake ? "cup.and.saucer.fill" : "cup.and.saucer")
        }
    }

    /// closed-lid ON 이면 빨간 lock 우선 (Keep Awake ON 여부와 무관), 아니면 커피잔.
    /// SwiftUI .foregroundColor(.red) 는 NSStatusItem 컨텍스트에서 system tint 로 override 됨.
    /// awake 오렌지와 동일하게 NSImage + paletteColors + isTemplate=false 경로 사용.
    private var modeImage: NSImage? {
        closedLidStore.state.isOn ? paletteSymbol("lock.fill", color: .systemRed) : coloredSymbol()
    }

    /// 한도 판의 색 — 아이콘과 같게. 템플릿(비활성 커피잔)이면 시스템이 다시 칠한다.
    private var modeColor: NSColor {
        if closedLidStore.state.isOn { return .systemRed }
        return isAwake ? .systemOrange : .black
    }

    /// macOS 메뉴바는 기본적으로 template image (모노크롬) 로 렌더함.
    /// caffeinate 활성 시 오렌지 색상을 강제하려면 NSImage + isTemplate=false 조합 필요.
    private func coloredSymbol() -> NSImage? {
        let symbolName = isAwake ? "cup.and.heat.waves.fill" : "cup.and.saucer"
        guard var image = NSImage(systemSymbolName: symbolName, accessibilityDescription: "muxbar") else {
            return nil
        }

        if isAwake {
            // hierarchical palette 로 오렌지 적용
            let config = NSImage.SymbolConfiguration(paletteColors: [.systemOrange])
            if let colored = image.withSymbolConfiguration(config) {
                image = colored
            }
            image.isTemplate = false  // template 이면 시스템이 단색으로 덮어씀
        } else {
            image.isTemplate = true   // 비활성 시 메뉴바 자동 다크/라이트 대응
        }
        return image
    }

    /// 임의의 SF Symbol 을 지정 색상으로 렌더한 NSImage 를 반환한다.
    /// isTemplate=false 로 설정해 메뉴바 시스템 tint 가 색상을 덮어쓰지 않도록 한다.
    private func paletteSymbol(_ name: String, color: NSColor) -> NSImage? {
        guard var image = NSImage(systemSymbolName: name, accessibilityDescription: name) else {
            return nil
        }
        let config = NSImage.SymbolConfiguration(paletteColors: [color])
        if let colored = image.withSymbolConfiguration(config) {
            image = colored
        }
        image.isTemplate = false
        return image
    }

    private var isAwake: Bool {
        awakeStore.isAwake(in: sessionStore)
    }

    private var sessionCount: Int {
        sessionStore.userVisibleSessions.count
    }
}
