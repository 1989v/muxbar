import XCTest
@testable import TmuxKit

final class OctalUnescapeTests: XCTestCase {
    func test_plainAscii_unchanged() {
        XCTAssertEqual(OctalUnescape.decode("hello world"), "hello world".data(using: .utf8)!)
    }

    func test_singleEscape_newline() {
        // \012 = \n = 0x0A
        let result = OctalUnescape.decode("line1\\012line2")
        XCTAssertEqual(result, "line1\nline2".data(using: .utf8)!)
    }

    func test_escapedBackslash() {
        // \134 = \ = 0x5C
        let result = OctalUnescape.decode("a\\134b")
        XCTAssertEqual(result, "a\\b".data(using: .utf8)!)
    }

    func test_tab() {
        // \011 = \t
        let result = OctalUnescape.decode("col1\\011col2")
        XCTAssertEqual(result, "col1\tcol2".data(using: .utf8)!)
    }

    func test_escapeAtEnd() {
        let result = OctalUnescape.decode("trailing\\015")
        XCTAssertEqual(result, "trailing\r".data(using: .utf8)!)
    }

    func test_malformedEscape_passthrough() {
        // less than 3 digits or non-octal → keep as-is
        let result = OctalUnescape.decode("bad\\9")
        XCTAssertEqual(result, "bad\\9".data(using: .utf8)!)
    }

    func test_multipleEscapes_inRow() {
        let result = OctalUnescape.decode("\\033\\133")
        // \033 = ESC (0x1B), \133 = [ (0x5B)
        XCTAssertEqual(result, Data([0x1B, 0x5B]))
    }
}
