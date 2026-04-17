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
}
