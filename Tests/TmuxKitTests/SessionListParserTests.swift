import XCTest
@testable import TmuxKit
import Core

final class SessionListParserTests: XCTestCase {
    func test_singleLine_parsedCorrectly() throws {
        let body = "dev\t1\t3\t1700000000\t1700001234\t/Users/kgd/msa"
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
        dev\t1\t3\t1700000000\t1700001234\t/Users/kgd/msa
        api-test\t0\t1\t1700002000\t1700002500\t/Users/kgd/msa/api
        """
        let sessions = try SessionListParser.parse(body)
        XCTAssertEqual(sessions.map(\.id), ["dev", "api-test"])
        XCTAssertEqual(sessions[1].isAttached, false)
    }

    func test_emptyBody_returnsEmpty() throws {
        XCTAssertEqual(try SessionListParser.parse(""), [])
    }

    func test_malformedLine_throws() {
        let body = "malformed\tline"
        XCTAssertThrowsError(try SessionListParser.parse(body))
    }
}
