import XCTest
@testable import Core

final class ProcessRunnerTests: XCTestCase {
    /// 파이프 버퍼보다 큰 출력을 출력·에러 양쪽으로 내도 끝나야 한다.
    func test_run_largeStdoutAndStderr_completes() throws {
        let script = "head -c 200000 /dev/zero | tr '\\0' o; head -c 200000 /dev/zero | tr '\\0' e >&2"
        let result = try ProcessRunner.run("/bin/sh", ["-c", script], timeout: 5)

        XCTAssertFalse(result.timedOut)
        XCTAssertEqual(result.status, 0)
        XCTAssertEqual(result.stdout.count, 200_000)
        XCTAssertEqual(result.stderr.count, 200_000)
    }

    func test_run_hangingChild_isTerminatedAtTimeout() throws {
        let start = Date()
        let result = try ProcessRunner.run("/bin/sleep", ["30"], timeout: 0.5)

        XCTAssertTrue(result.timedOut)
        XCTAssertFalse(result.succeeded)
        XCTAssertLessThan(Date().timeIntervalSince(start), 5)
    }

    func test_run_reportsExitStatusAndStderr() throws {
        let result = try ProcessRunner.run("/bin/sh", ["-c", "echo boom >&2; exit 3"])

        XCTAssertEqual(result.status, 3)
        XCTAssertEqual(result.stderrText, "boom\n")
        XCTAssertFalse(result.succeeded)
    }

    func test_run_missingExecutable_throws() {
        XCTAssertThrowsError(try ProcessRunner.run("/nonexistent/binary", []))
    }

    /// 종료를 기다리는 외부 명령은 전부 ProcessRunner 를 거친다.
    /// 소스에서 직접 `waitUntilExit` 를 부르면 출력 읽기 순서·제한 시간을 각자 다시 짜게 되고,
    /// 한 곳만 틀려도 메뉴바 전체가 굳는다.
    func test_sources_waitUntilExit_onlyInProcessRunner() throws {
        let sources = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("Sources")
        let files = FileManager.default.enumerator(at: sources, includingPropertiesForKeys: nil)?
            .compactMap { $0 as? URL }
            .filter { $0.pathExtension == "swift" } ?? []
        XCTAssertGreaterThan(files.count, 10, "Sources 를 못 찾았다: \(sources.path)")

        let offenders = try files
            .filter { $0.lastPathComponent != "ProcessRunner.swift" }
            .filter { try String(contentsOf: $0, encoding: .utf8).contains("waitUntilExit") }
            .map(\.lastPathComponent)
        XCTAssertEqual(offenders, [], "ProcessRunner.run 을 써야 한다")
    }
}
