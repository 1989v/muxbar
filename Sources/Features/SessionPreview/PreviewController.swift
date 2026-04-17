import Foundation
import SwiftUI
import Core
import MuxLogging

/// 세션 프리뷰의 오케스트레이터.
/// `start(session:provider:)` → capture-pane 으로 초기 스냅샷을 주입 후
/// provider.paneOutput 스트림을 구독해 PaneRendererEngine 에 실시간 feed.
/// 렌더는 throttle(20ms ≈ 50 FPS) 로 묶어 UI 부담 완화.
@MainActor
public final class PreviewController: ObservableObject {
    @Published public private(set) var attributedContent: NSAttributedString = NSAttributedString()
    @Published public private(set) var isLoading: Bool = false

    private let engine = PaneRendererEngine()
    private let logger = MuxLogging.logger("Features.PreviewController")
    private var subscription: Task<Void, Never>?
    private var pendingUpdate: Task<Void, Never>?
    private var lastRenderAt: Date = .distantPast
    private var currentSessionId: String?

    public init() {}

    public func start(session: TmuxSession, provider: any SessionProvider) {
        stop()
        isLoading = true
        currentSessionId = session.id

        Task { [weak self] in
            guard let self else { return }
            do {
                let body = try await provider.capturePane(target: session.id, lines: 200)
                self.engine.feed(body)
                self.render()
                self.isLoading = false
            } catch {
                self.logger.error("capturePane 실패: \(error.localizedDescription)")
                self.isLoading = false
            }
        }

        subscription = Task { [weak self, provider] in
            guard let self else { return }
            for await chunk in provider.paneOutput {
                if Task.isCancelled { break }
                await self.receive(chunk: chunk)
            }
        }
    }

    private func receive(chunk: PaneOutputChunk) async {
        // TODO: 현재는 세션별 pane 필터 없이 모든 pane 출력을 engine 에 feed.
        // 추후 active pane id 를 listWindows 로 획득해서 필터링 필요.
        engine.feed(chunk.data)
        scheduleRender()
    }

    private func scheduleRender() {
        pendingUpdate?.cancel()
        pendingUpdate = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 20_000_000) // 20ms ≈ 50 FPS
            guard !Task.isCancelled else { return }
            self?.render()
        }
    }

    private func render() {
        attributedContent = engine.renderAttributed()
        lastRenderAt = .now
    }

    public func stop() {
        subscription?.cancel()
        pendingUpdate?.cancel()
        subscription = nil
        pendingUpdate = nil
        currentSessionId = nil
        engine.reset()
        attributedContent = NSAttributedString()
    }
}
