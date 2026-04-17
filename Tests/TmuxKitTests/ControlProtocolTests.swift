import XCTest
@testable import TmuxKit

final class ControlProtocolTests: XCTestCase {
    func test_beginLine() {
        let parser = ControlProtocol()
        let events = parser.feed("%begin 1700000000 42 1\n")
        XCTAssertEqual(events, [.commandBegin(time: 1_700_000_000, cmdId: 42, flags: 1)])
    }

    func test_endLine_withBody_emitsOutputThenEnd() {
        let parser = ControlProtocol()
        let input = """
        %begin 1700000000 42 1
        hello
        world
        %end 1700000000 42 1

        """
        let events = parser.feed(input)
        XCTAssertEqual(events.count, 3)
        XCTAssertEqual(events[0], .commandBegin(time: 1_700_000_000, cmdId: 42, flags: 1))
        XCTAssertEqual(events[1], .commandOutput(cmdId: 42, body: "hello\nworld"))
        XCTAssertEqual(events[2], .commandEnd(time: 1_700_000_000, cmdId: 42, flags: 1))
    }

    func test_errorLine_withBody() {
        let parser = ControlProtocol()
        let input = """
        %begin 1700000000 43 1
        unknown command
        %error 1700000000 43 1

        """
        let events = parser.feed(input)
        XCTAssertEqual(events.count, 3)
        XCTAssertEqual(events[0], .commandBegin(time: 1_700_000_000, cmdId: 43, flags: 1))
        XCTAssertEqual(events[1], .commandOutput(cmdId: 43, body: "unknown command"))
        XCTAssertEqual(events[2], .commandError(time: 1_700_000_000, cmdId: 43, flags: 1))
    }

    func test_partialBuffer_crossesFeeds() {
        let parser = ControlProtocol()
        let first = parser.feed("%begin 1700000000 42 ")
        XCTAssertEqual(first, [])
        let second = parser.feed("1\n")
        XCTAssertEqual(second, [.commandBegin(time: 1_700_000_000, cmdId: 42, flags: 1)])
    }

    func test_paneOutput_decoded() {
        let parser = ControlProtocol()
        let events = parser.feed("%output %5 hello\\012world\n")
        guard case .paneOutput(let paneId, let data) = events.first else {
            return XCTFail("expected paneOutput, got \(events)")
        }
        XCTAssertEqual(paneId, "%5")
        XCTAssertEqual(String(data: data, encoding: .utf8), "hello\nworld")
    }

    func test_sessionsChanged() {
        let parser = ControlProtocol()
        XCTAssertEqual(parser.feed("%sessions-changed\n"), [.sessionsChanged])
    }

    func test_sessionChanged() {
        let parser = ControlProtocol()
        XCTAssertEqual(
            parser.feed("%session-changed $2 dev\n"),
            [.sessionChanged(sessionId: "$2", name: "dev")]
        )
    }

    func test_sessionRenamed() {
        let parser = ControlProtocol()
        XCTAssertEqual(
            parser.feed("%session-renamed $2 newname\n"),
            [.sessionRenamed(sessionId: "$2", name: "newname")]
        )
    }

    func test_windowAddClose() {
        let parser = ControlProtocol()
        XCTAssertEqual(parser.feed("%window-add @7\n"), [.windowAdd(windowId: "@7")])
        XCTAssertEqual(parser.feed("%window-close @7\n"), [.windowClose(windowId: "@7")])
    }

    func test_windowRenamed() {
        let parser = ControlProtocol()
        XCTAssertEqual(
            parser.feed("%window-renamed @7 logs\n"),
            [.windowRenamed(windowId: "@7", name: "logs")]
        )
    }

    func test_paneModeChanged() {
        let parser = ControlProtocol()
        XCTAssertEqual(
            parser.feed("%pane-mode-changed %5\n"),
            [.paneModeChanged(paneId: "%5")]
        )
    }

    func test_pauseContinue() {
        let parser = ControlProtocol()
        XCTAssertEqual(parser.feed("%pause %5\n"), [.pause(paneId: "%5")])
        XCTAssertEqual(parser.feed("%continue %5\n"), [.continueFlow(paneId: "%5")])
    }

    func test_exit() {
        let parser = ControlProtocol()
        XCTAssertEqual(parser.feed("%exit\n"), [.exit])
    }

    func test_unknown_pctLine() {
        let parser = ControlProtocol()
        let events = parser.feed("%future-event foo bar\n")
        XCTAssertEqual(events, [.unknown(line: "%future-event foo bar")])
    }
}
