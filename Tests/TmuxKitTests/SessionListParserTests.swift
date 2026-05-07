import XCTest
@testable import TmuxKit
import Core

final class SessionListParserTests: XCTestCase {
    func test_singleLine_parsedCorrectly() throws {
        let body = "dev@@@1@@@3@@@1700000000@@@1700001234@@@/Users/kgd/msa"
        let sessions = try SessionListParser.parse(body)
        XCTAssertEqual(sessions.count, 1)

        let s = sessions[0]
        XCTAssertEqual(s.id, "dev")
        XCTAssertTrue(s.isAttached)
        XCTAssertEqual(s.windowCount, 3)
        XCTAssertEqual(s.createdAt, Date(timeIntervalSince1970: 1_700_000_000))
        XCTAssertEqual(s.lastActivityAt, Date(timeIntervalSince1970: 1_700_001_234))
        XCTAssertEqual(s.workingDirectory, "/Users/kgd/msa")
    }

    func test_multipleLines() throws {
        let body = """
        dev@@@1@@@3@@@1700000000@@@1700001234@@@/Users/kgd/msa
        api-test@@@0@@@1@@@1700002000@@@1700002500@@@/Users/kgd/msa/api
        """
        let sessions = try SessionListParser.parse(body)
        XCTAssertEqual(sessions.map(\.id), ["dev", "api-test"])
        XCTAssertEqual(sessions[1].isAttached, false)
    }

    func test_underscorePrefixedSessionName_doesNotBreakParser() throws {
        // 회귀 방지: 세션 이름이 underscore 시작일 때도 정상 파싱되어야 함
        let body = "_muxbar-ctl@@@1@@@1@@@1700000000@@@1700001234@@@/"
        let sessions = try SessionListParser.parse(body)
        XCTAssertEqual(sessions.count, 1)
        XCTAssertEqual(sessions[0].id, "_muxbar-ctl")
    }

    func test_emptyBody_returnsEmpty() throws {
        XCTAssertEqual(try SessionListParser.parse(""), [])
    }

    func test_malformedLine_throws() {
        let body = "malformed@@@line"
        XCTAssertThrowsError(try SessionListParser.parse(body))
    }
}
