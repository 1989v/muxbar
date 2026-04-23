import Foundation

/// 다수 구독자에게 fan-out 하는 브로드캐스트 스트림.
///
/// `AsyncStream` 은 단일 iterator 시맨틱이라 같은 스트림을 여러 곳에서 iterate 하면
/// 원소가 경쟁적으로 분할 소비된다. 이 브로드캐스터는 `stream()` 호출마다 독립된
/// `AsyncStream` 을 새로 만들고 continuation 을 내부 dict 에 등록해, `yield` 시
/// 등록된 모든 continuation 에 같은 값을 전달한다.
final class EventBroadcaster<Element: Sendable>: @unchecked Sendable {
    private let lock = NSLock()
    private var continuations: [UUID: AsyncStream<Element>.Continuation] = [:]
    private var isFinished = false

    func stream() -> AsyncStream<Element> {
        AsyncStream { continuation in
            let id = UUID()
            lock.lock()
            if isFinished {
                lock.unlock()
                continuation.finish()
                return
            }
            continuations[id] = continuation
            lock.unlock()

            continuation.onTermination = { [weak self] _ in
                guard let self else { return }
                self.lock.lock()
                self.continuations.removeValue(forKey: id)
                self.lock.unlock()
            }
        }
    }

    func yield(_ element: Element) {
        lock.lock()
        let snapshot = Array(continuations.values)
        lock.unlock()
        for cont in snapshot {
            cont.yield(element)
        }
    }

    func finish() {
        lock.lock()
        let snapshot = Array(continuations.values)
        continuations.removeAll()
        isFinished = true
        lock.unlock()
        for cont in snapshot {
            cont.finish()
        }
    }
}
