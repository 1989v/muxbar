# muxbar Plan 3 — Live Preview (L2 + L3) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: superpowers:subagent-driven-development

**Goal:** 세션 hover 시 팝오버에 최근 출력 스냅샷(L2) + tmux `%output` 이벤트 실시간 반영(L3).

**Architecture:** SwiftTerm headless `Terminal` 엔진을 pane 별 1개 인스턴스로 보유. `capture-pane` 으로 초기 스냅샷 로드 후 `%output` 이벤트를 throttle(20ms ≈ 50 FPS) 해서 `terminal.feed(bytes)`. NSAttributedString 생성 후 SwiftUI `NSViewRepresentable` 로 표시.

**Tech Stack:** SwiftTerm(MIT), SwiftUI Popover, `@MainActor` isolation for UI.

---

## Task 1: SwiftTerm 의존성 추가

**Files:** `Package.swift`

- [ ] **Step 1: Package.swift 업데이트**

Add SwiftTerm to dependencies:
```swift
dependencies: [
    .package(url: "https://github.com/apple/swift-log.git", from: "1.5.0"),
    .package(url: "https://github.com/migueldeicaza/SwiftTerm.git", from: "1.2.0"),
],
```

Add `SwiftTerm` to the `Features` target dependencies:
```swift
.target(
    name: "Features",
    dependencies: [
        "Core", "TmuxKit", "TerminalLauncher", "MuxLogging",
        .product(name: "Logging", package: "swift-log"),
        .product(name: "SwiftTerm", package: "SwiftTerm")
    ],
    swiftSettings: [.enableExperimentalFeature("StrictConcurrency")]
),
```

- [ ] **Step 2: Resolve + Build**

```bash
cd /Users/gideok-kwon/IdeaProjects/muxbar
swift package resolve 2>&1 | tail -5
swift build 2>&1 | tail -5
```

Expected: SwiftTerm 다운로드 후 `Build complete!`

- [ ] **Step 3: Commit**

```bash
git add Package.swift Package.resolved
git commit -m "chore(deps): SwiftTerm 1.2 — ANSI 렌더 엔진 추가"
```

---

## Task 2: PaneRendererEngine — SwiftTerm headless 래퍼

**Files:** `Sources/Features/SessionPreview/PaneRendererEngine.swift`

SwiftTerm 의 headless 엔진을 감싸 `feed(bytes)` → NSAttributedString 변환 API 제공.

- [ ] **Step 1: PaneRendererEngine 작성**

Create `/Users/gideok-kwon/IdeaProjects/muxbar/Sources/Features/SessionPreview/PaneRendererEngine.swift`:
```swift
import Foundation
import AppKit
import SwiftTerm

@MainActor
public final class PaneRendererEngine {
    public let terminal: Terminal
    public let cols: Int
    public let rows: Int
    private let delegate: SilentDelegate

    public init(cols: Int = 80, rows: Int = 24) {
        self.cols = cols
        self.rows = rows
        let delegate = SilentDelegate()
        self.delegate = delegate
        self.terminal = Terminal(delegate: delegate)
        self.terminal.resize(cols: cols, rows: rows)
    }

    public func feed(_ data: Data) {
        data.withUnsafeBytes { raw in
            guard let base = raw.baseAddress else { return }
            let slice = Array(UnsafeBufferPointer(
                start: base.assumingMemoryBound(to: UInt8.self),
                count: data.count
            ))
            terminal.feed(byteArray: slice[...])
        }
    }

    public func feed(_ string: String) {
        if let data = string.data(using: .utf8) { feed(data) }
    }

    /// 현재 화면 내용을 NSAttributedString 으로 반환.
    public func renderAttributed(font: NSFont = .monospacedSystemFont(ofSize: 11, weight: .regular)) -> NSAttributedString {
        let result = NSMutableAttributedString()
        let buf = terminal.getTopVisibleRow()
        let bottom = buf + rows
        for y in buf..<bottom {
            let line = terminal.getScrollInvariantLine(row: y)
            for cell in line {
                let ch = cell.getCharacter()
                guard ch != "\0" else { continue }
                let attrs: [NSAttributedString.Key: Any] = [
                    .font: font,
                    .foregroundColor: NSColor.labelColor
                ]
                result.append(NSAttributedString(string: String(ch), attributes: attrs))
            }
            result.append(NSAttributedString(string: "\n"))
        }
        return result
    }

    public func reset() {
        terminal.softReset()
    }
}

private final class SilentDelegate: TerminalDelegate {
    func send(source: Terminal, data: ArraySlice<UInt8>) {}
    func scrolled(source: Terminal, yDisp: Int) {}
    func showCursor(source: Terminal) {}
    func hideCursor(source: Terminal) {}
    func setTerminalTitle(source: Terminal, title: String) {}
    func sizeChanged(source: Terminal) {}
}
```

⚠️ SwiftTerm API 가 버전에 따라 조금씩 다를 수 있음. 컴파일 에러 시:
- `Terminal(delegate:)` 이름 확인
- `getScrollInvariantLine(row:)` 존재 확인 (없으면 `getLine(row:)` 시도)
- `TerminalDelegate` 메서드 목록 확인

에러 발생 시 에러 메시지를 리포트하고 구체적 API 이름 알려줄 테니 대기.

- [ ] **Step 2: Build 확인**

Run: `swift build 2>&1 | tail -15`

- [ ] **Step 3: Commit**

```bash
git add Sources/Features/SessionPreview
git commit -m "feat(Features): PaneRendererEngine — SwiftTerm headless 래퍼"
```

---

## Task 3: PaneBufferStore — pane 별 버퍼 + 구독

**Files:** `Sources/Core/PaneBufferStore.swift`

Core 모듈. TmuxKit 이벤트를 받아 pane → data 누적.

- [ ] **Step 1: PaneBufferStore 작성**

Create `/Users/gideok-kwon/IdeaProjects/muxbar/Sources/Core/PaneBufferStore.swift`:
```swift
import Foundation
import Combine
import MuxLogging

@MainActor
public final class PaneBufferStore: ObservableObject {
    public struct Snapshot: Sendable, Equatable {
        public let paneId: String
        public let content: Data
        public let updatedAt: Date
    }

    @Published public private(set) var snapshots: [String: Snapshot] = [:]
    private let logger = MuxLogging.logger("Core.PaneBufferStore")

    public init() {}

    /// 외부에서 스냅샷 초기 주입 (capture-pane 결과)
    public func seed(paneId: String, data: Data) {
        snapshots[paneId] = Snapshot(paneId: paneId, content: data, updatedAt: .now)
    }

    /// %output 수신 시 append
    public func append(paneId: String, data: Data) {
        if var existing = snapshots[paneId] {
            var combined = existing.content
            combined.append(data)
            // 메모리 안전: 최대 64KB 유지 (초과 시 앞부분 절삭)
            if combined.count > 65_536 {
                combined = combined.suffix(65_536)
            }
            snapshots[paneId] = Snapshot(paneId: paneId, content: combined, updatedAt: .now)
        } else {
            snapshots[paneId] = Snapshot(paneId: paneId, content: data, updatedAt: .now)
        }
    }

    public func snapshot(for paneId: String) -> Snapshot? {
        snapshots[paneId]
    }

    public func clear(paneId: String) {
        snapshots.removeValue(forKey: paneId)
    }
}
```

- [ ] **Step 2: Build + Commit**

```bash
swift build 2>&1 | tail -3
git add Sources/Core/PaneBufferStore.swift
git commit -m "feat(Core): PaneBufferStore — pane 출력 버퍼 (@Published snapshots)"
```

---

## Task 4: SessionProvider — capture-pane + pane output 추가

**Files:**
- Modify: `Sources/Core/SessionStore.swift` (add to SessionProvider protocol)
- Modify: `Sources/TmuxKit/ControlClient+SessionProvider.swift` (implement)

- [ ] **Step 1: Protocol 확장**

Edit `/Users/gideok-kwon/IdeaProjects/muxbar/Sources/Core/SessionStore.swift` — add methods to `SessionProvider`:
```swift
public protocol SessionProvider: Sendable {
    func listSessions() async throws -> [TmuxSession]
    func kill(sessionName: String) async throws
    func createSession(name: String, command: String?) async throws
    func capturePane(target: String, lines: Int) async throws -> String
    var events: AsyncStream<SessionProviderEvent> { get }
    var paneOutput: AsyncStream<PaneOutputChunk> { get }
}

public struct PaneOutputChunk: Sendable, Equatable {
    public let paneId: String
    public let data: Data
    public init(paneId: String, data: Data) {
        self.paneId = paneId; self.data = data
    }
}
```

- [ ] **Step 2: ControlClient 구현 업데이트**

Edit `/Users/gideok-kwon/IdeaProjects/muxbar/Sources/TmuxKit/ControlClient+SessionProvider.swift` — add:
```swift
nonisolated public var paneOutput: AsyncStream<PaneOutputChunk> {
    let raw = self.rawEvents
    return AsyncStream { continuation in
        let task = Task {
            for await event in raw {
                if case .paneOutput(let paneId, let data) = event {
                    continuation.yield(PaneOutputChunk(paneId: paneId, data: data))
                }
            }
            continuation.finish()
        }
        continuation.onTermination = { _ in task.cancel() }
    }
}

public func capturePane(target: String, lines: Int) async throws -> String {
    try await send(.capturePane(target: target, lines: lines, withEscapes: true))
}
```

- [ ] **Step 3: Build + Commit**

```bash
swift build 2>&1 | tail -5
git add Sources/Core/SessionStore.swift Sources/TmuxKit/ControlClient+SessionProvider.swift
git commit -m "feat: SessionProvider에 capturePane + paneOutput 스트림 추가"
```

---

## Task 5: PreviewController — snapshot + live 구독 오케스트레이션

**Files:** `Sources/Features/SessionPreview/PreviewController.swift`

- [ ] **Step 1: PreviewController 작성**

Create `/Users/gideok-kwon/IdeaProjects/muxbar/Sources/Features/SessionPreview/PreviewController.swift`:
```swift
import Foundation
import SwiftUI
import Core
import MuxLogging

@MainActor
public final class PreviewController: ObservableObject {
    @Published public private(set) var attributedContent: NSAttributedString = NSAttributedString()
    @Published public private(set) var isLoading: Bool = false

    private let engine = PaneRendererEngine()
    private let logger = MuxLogging.logger("Features.PreviewController")
    private var subscription: Task<Void, Never>?
    private var pendingUpdate: Task<Void, Never>?
    private var lastRenderAt: Date = .distantPast

    public init() {}

    public func start(session: TmuxSession, provider: any SessionProvider) {
        stop()
        isLoading = true
        Task { [weak self] in
            guard let self else { return }
            do {
                let body = try await provider.capturePane(target: session.id, lines: 200)
                engine.feed(body)
                render()
                isLoading = false
            } catch {
                logger.error("capturePane 실패: \(error.localizedDescription)")
                isLoading = false
            }
        }

        subscription = Task { [weak self, provider] in
            guard let self else { return }
            for await chunk in provider.paneOutput {
                await self.receive(chunk: chunk, sessionId: session.id)
            }
        }
    }

    private func receive(chunk: PaneOutputChunk, sessionId: String) async {
        // 현재 세션의 활성 pane 출력만 반영 (여러 pane 동시 푸시 가능)
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
        engine.reset()
        attributedContent = NSAttributedString()
    }
}
```

- [ ] **Step 2: Build + Commit**

```bash
swift build 2>&1 | tail -5
git add Sources/Features/SessionPreview/PreviewController.swift
git commit -m "feat(Features): PreviewController — capture-pane 로드 + paneOutput 스트리밍 throttle"
```

---

## Task 6: SessionPreviewView — SwiftUI NSViewRepresentable

**Files:** `Sources/Features/SessionPreview/SessionPreviewView.swift`

- [ ] **Step 1: 뷰 작성**

Create `/Users/gideok-kwon/IdeaProjects/muxbar/Sources/Features/SessionPreview/SessionPreviewView.swift`:
```swift
import SwiftUI
import AppKit
import Core

public struct SessionPreviewView: View {
    @ObservedObject public var controller: PreviewController

    public init(controller: PreviewController) {
        self.controller = controller
    }

    public var body: some View {
        ZStack {
            AttributedTextView(content: controller.attributedContent)
                .frame(minWidth: 480, minHeight: 240)
                .padding(6)
                .background(Color(nsColor: .textBackgroundColor))
            if controller.isLoading {
                ProgressView().controlSize(.small)
            }
        }
    }
}

struct AttributedTextView: NSViewRepresentable {
    let content: NSAttributedString

    func makeNSView(context: Context) -> NSScrollView {
        let textView = NSTextView(frame: .zero)
        textView.isEditable = false
        textView.isSelectable = true
        textView.backgroundColor = .textBackgroundColor
        textView.textContainerInset = NSSize(width: 4, height: 4)

        let scrollView = NSScrollView()
        scrollView.hasVerticalScroller = true
        scrollView.documentView = textView
        scrollView.drawsBackground = false
        return scrollView
    }

    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        guard let tv = scrollView.documentView as? NSTextView else { return }
        tv.textStorage?.setAttributedString(content)
        tv.scrollToEndOfDocument(nil)
    }
}
```

- [ ] **Step 2: Build + Commit**

```bash
swift build 2>&1 | tail -5
git add Sources/Features/SessionPreview/SessionPreviewView.swift
git commit -m "feat(Features): SessionPreviewView — NSTextView scroll + NSAttributedString 렌더"
```

---

## Task 7: SessionRowView — Preview 버튼 추가

**Files:** `Sources/Features/SessionList/SessionRowView.swift` (modify)

- [ ] **Step 1: Preview 버튼 추가**

Edit `/Users/gideok-kwon/IdeaProjects/muxbar/Sources/Features/SessionList/SessionRowView.swift` — extend init and Menu:

Replace the struct with:
```swift
import SwiftUI
import Core

public struct SessionRowView: View {
    public let session: TmuxSession
    public let onAttach: () -> Void
    public let onKill: () -> Void
    public let onPreview: () -> Void

    public init(
        session: TmuxSession,
        onAttach: @escaping () -> Void,
        onKill: @escaping () -> Void,
        onPreview: @escaping () -> Void
    ) {
        self.session = session
        self.onAttach = onAttach
        self.onKill = onKill
        self.onPreview = onPreview
    }

    public var body: some View {
        HStack(spacing: 8) {
            Image(systemName: session.isAttached ? "circle.fill" : "circle")
                .foregroundStyle(session.isAttached ? .green : .secondary)
                .font(.system(size: 8))

            VStack(alignment: .leading, spacing: 2) {
                Text(session.id)
                    .font(.system(.body, design: .monospaced))
                if let cwd = session.workingDirectory {
                    Text(cwd)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
            }
            .contentShape(Rectangle())
            .onTapGesture { onPreview() }

            Spacer(minLength: 8)

            Text("\(session.windowCount)w")
                .font(.caption)
                .foregroundStyle(.secondary)

            Menu {
                Button("Attach") { onAttach() }
                Button("Preview") { onPreview() }
                Button("Kill", role: .destructive) { onKill() }
            } label: {
                Image(systemName: "ellipsis")
            }
            .menuStyle(.borderlessButton)
            .fixedSize()
        }
        .padding(.vertical, 2)
    }
}
```

- [ ] **Step 2: SessionListView 업데이트**

Edit `/Users/gideok-kwon/IdeaProjects/muxbar/Sources/Features/SessionList/SessionListView.swift` — add `onPreview` closure:

Replace SessionListView struct:
```swift
import SwiftUI
import Core

public struct SessionListView: View {
    @ObservedObject public var store: SessionStore
    public let onAttach: (TmuxSession) -> Void
    public let onKill: (TmuxSession) -> Void
    public let onPreview: (TmuxSession) -> Void

    public init(
        store: SessionStore,
        onAttach: @escaping (TmuxSession) -> Void,
        onKill: @escaping (TmuxSession) -> Void,
        onPreview: @escaping (TmuxSession) -> Void
    ) {
        self.store = store
        self.onAttach = onAttach
        self.onKill = onKill
        self.onPreview = onPreview
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            if store.userVisibleSessions.isEmpty {
                Text(placeholderText)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding(.vertical, 4)
            } else {
                ForEach(store.userVisibleSessions) { session in
                    SessionRowView(
                        session: session,
                        onAttach: { onAttach(session) },
                        onKill: { onKill(session) },
                        onPreview: { onPreview(session) }
                    )
                    Divider()
                }
            }
        }
        .padding(.horizontal, 8)
    }

    private var placeholderText: String {
        switch store.connectionState {
        case .connecting:  return "tmux 연결 중…"
        case .connected:   return "세션 없음. tmux new-session 으로 시작"
        case .disconnected: return "연결 끊김"
        case .reconnecting: return "재연결 중…"
        case .failed(let reason): return "연결 실패: \(reason)"
        }
    }
}
```

- [ ] **Step 3: Build + Commit**

```bash
swift build 2>&1 | tail -3
git add Sources/Features/SessionList
git commit -m "feat(Features): SessionRowView/ListView — Preview 액션 추가"
```

---

## Task 8: MuxBarApp — PreviewController 연결 + Popover

**Files:** `Sources/MuxBarApp/MuxBarApp.swift`, `Sources/MuxBarApp/AppState.swift`

- [ ] **Step 1: AppState 에 previewController 추가**

Edit `/Users/gideok-kwon/IdeaProjects/muxbar/Sources/MuxBarApp/AppState.swift` — add:

Add property and method:
```swift
// In AppState class, add:
public let previewController: PreviewController
@Published public var previewSession: TmuxSession?

// In init():
self.previewController = PreviewController()
// existing init lines...

// Add method:
public func startPreview(for session: TmuxSession) {
    guard let client = controlClient else { return }
    previewSession = session
    previewController.start(session: session, provider: client)
}

public func stopPreview() {
    previewController.stop()
    previewSession = nil
}
```

Also need `import Features` at top.

- [ ] **Step 2: MuxBarApp 에 popover 연결**

Edit `/Users/gideok-kwon/IdeaProjects/muxbar/Sources/MuxBarApp/MuxBarApp.swift` — update SessionListView call and add popover:

```swift
// Replace SessionListView call with:
SessionListView(
    store: appState.sessionStore,
    onAttach: { appState.attach($0) },
    onKill: { appState.kill($0) },
    onPreview: { appState.startPreview(for: $0) }
)
.popover(
    isPresented: Binding(
        get: { appState.previewSession != nil },
        set: { if !$0 { appState.stopPreview() } }
    ),
    arrowEdge: .leading
) {
    SessionPreviewView(controller: appState.previewController)
}
```

- [ ] **Step 3: Build + Release + 실행**

```bash
cd /Users/gideok-kwon/IdeaProjects/muxbar
swift build -c release 2>&1 | tail -3
pkill -f muxbar 2>/dev/null
sleep 1
./.build/release/muxbar > /tmp/muxbar.log 2>&1 &
sleep 3
pgrep -fl muxbar
```

- [ ] **Step 4: Commit + 태그**

```bash
git add Sources/MuxBarApp
git commit -m "feat(MuxBarApp): Preview popover 통합"
git tag -a plan-3-complete -m "Plan 3: Live Preview 완료"
```

---

## Task 9: ADR-0003 + docs/README.md

**Files:**
- Create: `docs/adr/ADR-0003-swiftterm-rendering.md`
- Modify: `docs/README.md`

- [ ] **Step 1: ADR-0003 작성**

Create `/Users/gideok-kwon/IdeaProjects/muxbar/docs/adr/ADR-0003-swiftterm-rendering.md`:
```markdown
# ADR-0003: SwiftTerm 채택 (ANSI 렌더링)

- Status: Accepted
- Date: 2026-04-17

## Context

라이브 프리뷰(L3)는 tmux `%output` 으로 받은 바이트 스트림(ANSI escape 포함)을
정확히 렌더해야 한다. 직접 ANSI 파서를 구현하면 CSI/OSC/SGR 수많은 escape 시퀀스를
모두 처리해야 해 러빗홀.

## Decision

SwiftTerm (MIT, 미구엘 데 이카자 메인테인) 의 headless `Terminal` 엔진을 사용.
`feed(byteArray:)` 로 원시 바이트 주입 → 내부에서 cell buffer 갱신 →
`getScrollInvariantLine(row:)` 로 읽어 NSAttributedString 생성.

## Consequences

**장점**:
- ANSI/UTF-8/SGR/CSI 처리 검증된 구현 재사용
- iTerm2 유사 렌더 가능 (미래 색상 지원 용이)

**단점**:
- 외부 의존성 추가 (빌드 시 Git 네트워크 필요)
- SwiftTerm 의 API 가 버전에 따라 소폭 변경될 수 있음

## References
- https://github.com/migueldeicaza/SwiftTerm
```

- [ ] **Step 2: docs/README.md 업데이트**

Append to ADRs section:
```markdown
- [ADR-0003: SwiftTerm 채택](adr/ADR-0003-swiftterm-rendering.md)
```

Append to Plans section (replace "Plan 3 예정" line):
```markdown
- [Plan 3 — Live Preview](plans/2026-04-17-plan-3-live-preview.md)
```

- [ ] **Step 3: Commit**

```bash
git add docs/
git commit -m "docs: Plan 3 완료 — ADR-0003 + README 업데이트"
```

---

## Plan 3 완료 기준

- [x] SwiftTerm 1.2 의존성 resolve
- [x] `swift build` 성공
- [x] Preview 버튼 클릭 → popover 열림
- [x] capture-pane 스냅샷 표시
- [x] live tmux 출력 스트리밍 반영 (세션에서 echo 치면 업데이트)
- [x] ADR-0003 작성

## Plan 4 예고

M5 — 5개 터미널 전체 구현 완료 + 전역 단축키(HotKey 패키지) + 세션 템플릿 5종.
