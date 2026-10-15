import AppKit

/// 메뉴바 아이콘 한 장 합성 — 아이콘 몸통 위에 주간 남은 한도, 오른쪽 위 작은 원 안에 세션 수.
///
/// 숫자를 아이콘 옆에 이어 붙이면 메뉴바 폭이 두 배 가까이 늘어서 아이콘에 겹친다.
/// 메뉴바 라벨은 SwiftUI 겹치기·색 지정을 그대로 그려 주지 않으므로 이미지 한 장으로 합성한다.
/// 글자·원 둘레를 비워 아이콘 선과 엉키지 않게 한다. 원 안 숫자는 오려 내 메뉴바 바탕이 비친다.
/// 템플릿 이미지면 시스템이 전부 메뉴바 글자색으로 다시 칠한다. 색 있는 아이콘(주황 잔·빨간 자물쇠)
/// 위의 한도 숫자는 같은 색이면 안 읽혀서 메뉴바 글자색(어두운 바=흰색, 밝은 바=검정)으로 칠한다.
/// 숫자는 아이콘 아래쪽(잔 받침)에만 걸치게 아이콘을 위로 올려 아이콘 모양이 남게 한다.
enum LimitOverlay {
    static func image(base: NSImage, limitText: String?, sessionCount: Int,
                      color: NSColor, isTemplate: Bool) -> NSImage {
        guard limitText != nil || sessionCount > 0 else { return base }

        // 잔량을 겹칠 때만 아이콘을 20pt 로 키우고 3.5pt 올린다 — 옆 메뉴바 아이콘과 비슷한 크기.
        // 세션 수 원만 달 때는 원래 크기 — 세션이 0 ↔ 1 개를 오갈 때 잔 크기가 바뀌지 않게.
        let scale = limitText == nil ? 1 : 20 / max(base.size.height, 1)
        let lift: CGFloat = limitText == nil ? 0 : 3.5
        let baseSize = NSSize(width: base.size.width * scale, height: base.size.height * scale)

        let limitFont = NSFont.monospacedDigitSystemFont(ofSize: 9.5, weight: .black)
        let limitSize = limitText.map { ($0 as NSString).size(withAttributes: [.font: limitFont]) } ?? .zero

        let badgeText = sessionCount > 99 ? "99+" : "\(sessionCount)"
        let badgeFont = NSFont.monospacedDigitSystemFont(ofSize: 7, weight: .heavy)
        let badgeTextSize = (badgeText as NSString).size(withAttributes: [.font: badgeFont])
        let badgeHeight: CGFloat = 9
        let badge = sessionCount > 0
            ? NSSize(width: max(badgeHeight, ceil(badgeTextSize.width) + 3), height: badgeHeight) : .zero

        // 원은 아이콘 오른쪽 위 모서리에 반쯤 걸치게 둔다
        let iconWidth = max(baseSize.width, ceil(limitSize.width) + 1)
        let size = NSSize(width: iconWidth + (badge.width > 0 ? badge.width / 2 : 0),
                          height: max(baseSize.height + lift, badge.height + baseSize.height / 2))

        let image = NSImage(size: size, flipped: false) { _ in
            guard let cg = NSGraphicsContext.current?.cgContext else { return false }
            base.draw(in: NSRect(x: (iconWidth - baseSize.width) / 2, y: lift,
                                 width: baseSize.width, height: baseSize.height))

            if let limitText {
                // 잔 받침 높이(아래쪽). 글자 둘레를 비운 뒤 칠한다
                let origin = NSPoint(x: (iconWidth - limitSize.width) / 2, y: -1)
                cg.setBlendMode(.destinationOut)
                (limitText as NSString).draw(at: origin, withAttributes: [
                    .font: limitFont, .foregroundColor: NSColor.black,
                    .strokeColor: NSColor.black, .strokeWidth: -(1.8 / limitFont.pointSize * 100),
                ])
                cg.setBlendMode(.normal)
                let digitColor = isTemplate ? color : barTextColor
                (limitText as NSString).draw(at: origin, withAttributes: [.font: limitFont, .foregroundColor: digitColor])
            }

            if badge.width > 0 {
                let rect = NSRect(x: size.width - badge.width, y: size.height - badge.height,
                                  width: badge.width, height: badge.height)
                let radius = badge.height / 2
                // 원 둘레 1pt 를 비워 잔·김과 떨어져 보이게 한다
                cg.setBlendMode(.destinationOut)
                NSBezierPath(roundedRect: rect.insetBy(dx: -1, dy: -1), xRadius: radius + 1, yRadius: radius + 1).fill()
                cg.setBlendMode(.normal)
                color.setFill()
                NSBezierPath(roundedRect: rect, xRadius: radius, yRadius: radius).fill()
                cg.setBlendMode(.destinationOut)
                let origin = NSPoint(x: rect.midX - badgeTextSize.width / 2,
                                     y: rect.midY - badgeTextSize.height / 2 + 0.3)
                (badgeText as NSString).draw(at: origin, withAttributes: [.font: badgeFont, .foregroundColor: NSColor.black])
                cg.setBlendMode(.normal)
            }
            return true
        }
        image.isTemplate = isTemplate
        return image
    }

    /// 그리는 시점의 외형(메뉴바 버튼이 그릴 때는 메뉴바 외형)으로 고른 글자색
    private static var barTextColor: NSColor {
        NSAppearance.currentDrawing().bestMatch(from: [.aqua, .darkAqua]) == .darkAqua ? .white : .black
    }
}
