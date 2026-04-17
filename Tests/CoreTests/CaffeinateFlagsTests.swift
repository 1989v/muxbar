import XCTest
@testable import Core

final class CaffeinateFlagsTests: XCTestCase {
    func test_default_isDIMS() {
        XCTAssertEqual(CaffeinateFlags.default.cliArgs, "-dims")
    }

    func test_empty_producesEmptyString() {
        let empty = CaffeinateFlags(d: false, i: false, m: false, s: false, u: false)
        XCTAssertEqual(empty.cliArgs, "")
        XCTAssertFalse(empty.isValid)
    }

    func test_singleFlag_u() {
        let flags = CaffeinateFlags(d: false, i: false, m: false, s: false, u: true)
        XCTAssertEqual(flags.cliArgs, "-u")
        XCTAssertTrue(flags.isValid)
    }

    func test_order_isDimsuStable() {
        let flags = CaffeinateFlags(d: true, i: true, m: true, s: true, u: true)
        XCTAssertEqual(flags.cliArgs, "-dimsu")
    }

    func test_default_isValid() {
        XCTAssertTrue(CaffeinateFlags.default.isValid)
    }
}
