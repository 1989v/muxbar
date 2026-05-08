import SwiftUI
import AppKit
import Core

public struct MenuBarIcon: View {
    @ObservedObject public var sessionStore: SessionStore
    @ObservedObject public var awakeStore: AwakeStore
    @ObservedObject public var closedLidStore: ClosedLidStore

    public init(
        sessionStore: SessionStore,
        awakeStore: AwakeStore,
        closedLidStore: ClosedLidStore
    ) {
        self.sessionStore = sessionStore
        self.awakeStore = awakeStore
        self.closedLidStore = closedLidStore
    }

    public var body: some View {
        if closedLidStore.state.isOn {
            // closed-lid ON: 빨간 lock 우선 (Keep Awake ON 여부와 무관)
            Image(systemName: "lock.fill")
                .renderingMode(.template)
                .foregroundColor(.red)
        } else {
            HStack(spacing: 3) {
                if let nsImage = coloredSymbol() {
                    Image(nsImage: nsImage)
                } else {
                    // fallback
                    Image(systemName: isAwake ? "cup.and.saucer.fill" : "cup.and.saucer")
                }
                if sessionCount > 0 {
                    Text("\(sessionCount)")
                        .font(.system(size: 12, weight: .semibold))
                        .monospacedDigit()
                }
            }
        }
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

    private var isAwake: Bool {
        awakeStore.isAwake(in: sessionStore)
    }

    private var sessionCount: Int {
        sessionStore.userVisibleSessions.count
    }
}
