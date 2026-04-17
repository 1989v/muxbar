import XCTest
@testable import TerminalLauncher

final class TerminalAppTests: XCTestCase {
    func test_bundleIds_areUnique() {
        let ids = TerminalApp.allCases.map(\.rawValue)
        XCTAssertEqual(Set(ids).count, ids.count)
    }

    func test_displayNames() {
        XCTAssertEqual(TerminalApp.terminal.displayName, "Terminal")
        XCTAssertEqual(TerminalApp.iterm2.displayName, "iTerm2")
    }

    func test_isInstalled_terminalApp_shouldReturnTrueOnMac() {
        // Terminal.app 은 macOS 기본 제공
        XCTAssertTrue(TerminalApp.terminal.isInstalled())
    }
}
