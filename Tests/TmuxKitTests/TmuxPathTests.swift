import XCTest
@testable import TmuxKit

final class TmuxPathTests: XCTestCase {
    func test_candidates_includesKnownPaths() {
        let candidates = TmuxPath.defaultCandidates
        XCTAssertTrue(candidates.contains("/opt/homebrew/bin/tmux"))
        XCTAssertTrue(candidates.contains("/usr/local/bin/tmux"))
        XCTAssertTrue(candidates.contains("/usr/bin/tmux"))
    }

    func test_resolve_returnsFirstExistingPath() throws {
        // tmpFile 하나 만들어서 실제 존재 경로가 resolve 되는지
        let fm = FileManager.default
        let tmp = fm.temporaryDirectory.appendingPathComponent("fake-tmux-\(UUID())")
        try "dummy".write(to: tmp, atomically: true, encoding: .utf8)
        defer { try? fm.removeItem(at: tmp) }

        let candidates = ["/nonexistent/tmux", tmp.path, "/also/nonexistent"]
        let resolved = TmuxPath.resolve(from: candidates)
        XCTAssertEqual(resolved, tmp.path)
    }

    func test_resolve_returnsNilWhenNoneExist() {
        let resolved = TmuxPath.resolve(from: ["/no/where", "/nope"])
        XCTAssertNil(resolved)
    }
}
