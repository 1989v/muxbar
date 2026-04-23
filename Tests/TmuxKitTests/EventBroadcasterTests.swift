import XCTest
@testable import TmuxKit

final class EventBroadcasterTests: XCTestCase {
    func test_singleSubscriber_receivesAllYields() async {
        let broadcaster = EventBroadcaster<Int>()
        let stream = broadcaster.stream()

        broadcaster.yield(1)
        broadcaster.yield(2)
        broadcaster.yield(3)
        broadcaster.finish()

        var collected: [Int] = []
        for await v in stream { collected.append(v) }
        XCTAssertEqual(collected, [1, 2, 3])
    }

    /// 핵심 회귀 방지 케이스: 두 구독자가 동시에 iterate 중일 때 모두 전체 이벤트를 받아야 함.
    /// (AsyncStream 단일 iterator 시맨틱 우회 — ControlClient 의 events/paneOutput 동시 구독 버그 방지)
    func test_multipleSubscribers_bothReceiveAllYields() async {
        let broadcaster = EventBroadcaster<Int>()
        let s1 = broadcaster.stream()
        let s2 = broadcaster.stream()

        broadcaster.yield(1)
        broadcaster.yield(2)
        broadcaster.yield(3)
        broadcaster.finish()

        var r1: [Int] = []
        for await v in s1 { r1.append(v) }
        var r2: [Int] = []
        for await v in s2 { r2.append(v) }

        XCTAssertEqual(r1, [1, 2, 3])
        XCTAssertEqual(r2, [1, 2, 3])
    }

    func test_subscribeAfterFinish_endsImmediately() async {
        let broadcaster = EventBroadcaster<Int>()
        broadcaster.finish()

        let stream = broadcaster.stream()
        var collected: [Int] = []
        for await v in stream { collected.append(v) }
        XCTAssertEqual(collected, [])
    }

    func test_unsubscribedContinuation_doesNotBlockOthers() async {
        let broadcaster = EventBroadcaster<Int>()

        // 구독 후 바로 종료시킬 스트림
        do {
            let transient = broadcaster.stream()
            var iter = transient.makeAsyncIterator()
            _ = iter  // iterator 생성 후 scope 벗어나면서 종료 → onTermination 호출
        }

        let live = broadcaster.stream()
        // onTermination 이 비동기 호출이므로 잠깐 양보
        await Task.yield()

        broadcaster.yield(42)
        broadcaster.finish()

        var collected: [Int] = []
        for await v in live { collected.append(v) }
        XCTAssertEqual(collected, [42])
    }
}
