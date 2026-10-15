import AppKit

/// 메뉴바 아이콘 위에 주간 한도 숫자를 겹친 이미지.
///
/// 숫자를 아이콘 옆에 이어 붙이면 메뉴바 폭이 두 배 가까이 늘어서 아이콘에 겹친다.
/// 메뉴바 라벨은 SwiftUI 겹치기·색 지정을 그대로 그려 주지 않으므로 이미지 한 장으로 합성한다.
/// 숫자 둘레를 비워 아이콘 선과 엉키지 않게 하고, 숫자는 아이콘과 같은 색으로 칠한다 —
/// 템플릿 이미지일 때는 시스템이 아이콘과 함께 다시 칠한다.
enum LimitOverlay {
    static func image(base: NSImage, text: String, color: NSColor, isTemplate: Bool) -> NSImage {
        let font = NSFont.monospacedDigitSystemFont(ofSize: 7.5, weight: .bold)
        let textSize = (text as NSString).size(withAttributes: [.font: font])
        // 숫자가 잔 폭 안에 대부분 들어가도록 아이콘을 메뉴바 높이(약 18pt) 안에서 키운다
        let scale = 18 / max(base.size.height, 1)
        let baseSize = NSSize(width: base.size.width * scale, height: base.size.height * scale)
        let size = NSSize(width: max(baseSize.width, ceil(textSize.width) + 1), height: baseSize.height)

        let image = NSImage(size: size, flipped: false) { _ in
            guard let cg = NSGraphicsContext.current?.cgContext else { return false }
            base.draw(in: NSRect(x: (size.width - baseSize.width) / 2, y: 0,
                                 width: baseSize.width, height: baseSize.height))

            // 숫자는 잔 몸통 높이(아래쪽)에 둔다
            let origin = NSPoint(x: (size.width - textSize.width) / 2, y: 1.5)
            // 글자 둘레를 얇게 비워 아이콘 선과 엉키지 않게 한다
            cg.setBlendMode(.destinationOut)
            (text as NSString).draw(at: origin, withAttributes: [
                .font: font, .foregroundColor: NSColor.black,
                .strokeColor: NSColor.black, .strokeWidth: -(1.6 / font.pointSize * 100),
            ])
            cg.setBlendMode(.normal)
            (text as NSString).draw(at: origin, withAttributes: [.font: font, .foregroundColor: color])
            return true
        }
        image.isTemplate = isTemplate
        return image
    }
}
