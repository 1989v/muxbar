import XCTest
@testable import Core

final class CoreTests: XCTestCase {
    func testConnectionStateEquatable() {
        XCTAssertEqual(ConnectionState.disconnected, ConnectionState.disconnected)
        XCTAssertNotEqual(ConnectionState.connected, ConnectionState.disconnected)
    }
}
