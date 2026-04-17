import Foundation
import AppKit
import SwiftTerm

/// SwiftTerm headless 엔진을 감싸는 래퍼.
/// `feed(Data)` 로 원시 바이트(ANSI escape 포함)를 주입하고,
/// `renderAttributed()` 로 현재 화면 상태를 NSAttributedString 으로 얻는다.
@MainActor
public final class PaneRendererEngine {
    public let terminal: Terminal
    public let cols: Int
    public let rows: Int
    private let delegate: SilentDelegate

    public init(cols: Int = 80, rows: Int = 24) {
        self.cols = cols
        self.rows = rows
        let delegate = SilentDelegate()
        self.delegate = delegate
        self.terminal = Terminal(delegate: delegate)
        self.terminal.resize(cols: cols, rows: rows)
    }

    public func feed(_ data: Data) {
        // Data → [UInt8] → ArraySlice<UInt8> 로 변환. SwiftTerm 은 feed(byteArray:) / feed(buffer:) 지원.
        let bytes = [UInt8](data)
        terminal.feed(byteArray: bytes)
    }

    public func feed(_ string: String) {
        terminal.feed(text: string)
    }

    /// 현재 화면 내용을 NSAttributedString 으로 반환.
    /// 아직 색상/속성은 반영하지 않고 평문만 추출한다. (추후 SGR 속성 처리 확장 여지)
    public func renderAttributed(
        font: NSFont = .monospacedSystemFont(ofSize: 11, weight: .regular)
    ) -> NSAttributedString {
        let result = NSMutableAttributedString()
        let top = terminal.getTopVisibleRow()
        let bottom = top + rows
        let attrs: [NSAttributedString.Key: Any] = [
            .font: font,
            .foregroundColor: NSColor.labelColor
        ]
        for y in top..<bottom {
            guard let line = terminal.getScrollInvariantLine(row: y) else {
                result.append(NSAttributedString(string: "\n", attributes: attrs))
                continue
            }
            var lineString = ""
            for x in 0..<line.count {
                let ch = line[x].getCharacter()
                if ch == "\0" { continue }
                lineString.append(ch)
            }
            // 오른쪽 공백 trim (대부분 빈 셀이 공백으로 채워짐)
            let trimmed = lineString.replacingOccurrences(
                of: "\\s+$",
                with: "",
                options: .regularExpression
            )
            result.append(NSAttributedString(string: trimmed + "\n", attributes: attrs))
        }
        return result
    }

    public func reset() {
        terminal.softReset()
    }
}

/// TerminalDelegate 의 필수 메서드만 no-op 으로 채운 delegate.
/// 대부분의 메서드는 public extension TerminalDelegate 에 기본 구현이 있으므로
/// 아래 3개만 필수로 구현하면 된다.
private final class SilentDelegate: TerminalDelegate {
    func send(source: Terminal, data: ArraySlice<UInt8>) {
        // headless — host 로 송신할 곳 없음. 무시.
    }

    func scrolled(source: Terminal, yDisp: Int) {}

    func windowCommand(source: Terminal, command: Terminal.WindowManipulationCommand) -> [UInt8]? {
        nil
    }
}
