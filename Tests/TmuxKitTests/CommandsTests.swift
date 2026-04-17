import XCTest
@testable import TmuxKit

final class CommandsTests: XCTestCase {
    func test_listSessions_cliString() {
        XCTAssertEqual(
            TmuxCommand.listSessions.cliString,
            #"list-sessions -F "#{session_name}\t#{session_attached}\t#{session_windows}\t#{session_created}\t#{session_activity}\t#{session_path}""#
        )
    }

    func test_killSession_quotesName() {
        XCTAssertEqual(
            TmuxCommand.killSession(name: "dev").cliString,
            #"kill-session -t "dev""#
        )
    }

    func test_killSession_escapesQuotes() {
        XCTAssertEqual(
            TmuxCommand.killSession(name: "a\"b").cliString,
            #"kill-session -t "a\"b""#
        )
    }

    func test_newSession_detached() {
        XCTAssertEqual(
            TmuxCommand.newSession(name: "dev", command: nil).cliString,
            #"new-session -d -s "dev""#
        )
    }

    func test_newSession_withCommand() {
        XCTAssertEqual(
            TmuxCommand.newSession(name: "awake", command: "caffeinate -dims").cliString,
            #"new-session -d -s "awake" "caffeinate -dims""#
        )
    }

    func test_hasSession() {
        XCTAssertEqual(
            TmuxCommand.hasSession(name: "dev").cliString,
            #"has-session -t "dev""#
        )
    }

    func test_capturePane() {
        XCTAssertEqual(
            TmuxCommand.capturePane(target: "dev", lines: 200, withEscapes: true).cliString,
            #"capture-pane -pt "dev" -J -e -S -200"#
        )
    }
}
