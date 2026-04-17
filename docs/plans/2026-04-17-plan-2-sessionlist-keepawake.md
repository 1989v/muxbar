# muxbar Plan 2 — SessionList + KeepAwake Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development. Steps use checkbox (`- [ ]`) syntax.

**Goal:** Plan 1 의 TmuxKit 라이브러리 위에 사용자가 실제로 쓸 수 있는 MVP UI 를 얹는다. 세션 리스트 / Attach (Terminal.app) / Kill / KeepAwake 토글. 이 plan 완료 시 실사용 가능한 첫 버전.

**Architecture:** SessionStore (`@MainActor ObservableObject`) 가 ControlClient 를 감싸 SwiftUI 에 @Published 로 노출. MenuBarExtra 드롭다운에 리스트 + 액션 메뉴. AwakeStore 는 SessionStore 의 `_muxbar-awake` 존재 여부로 상태 도출.

**Tech Stack:** SwiftUI, Swift Concurrency, AppKit `NSWorkspace` + `osascript` for terminal launch.

---

## File Structure

```
muxbar/
├── Sources/
│   ├── Core/
│   │   ├── SessionStore.swift              (new) @MainActor ObservableObject
│   │   └── AwakeStore.swift                (new)
│   ├── TerminalLauncher/                   (new module)
│   │   ├── TerminalApp.swift               TerminalApp enum (Terminal.app only for now)
│   │   └── TerminalAdapter.swift           AppleScript 실행 + attach
│   ├── Features/                           (new)
│   │   ├── SessionList/
│   │   │   ├── SessionListView.swift
│   │   │   ├── SessionRowView.swift
│   │   │   └── KillConfirmation.swift
│   │   └── KeepAwake/
│   │       └── KeepAwakeMenuItem.swift
│   └── MuxBarApp/
│       ├── MuxBarApp.swift                 (modified)
│       └── AppState.swift                  (new) 전역 Store 컨테이너
└── Tests/
    ├── CoreTests/
    │   ├── SessionStoreTests.swift         단위 테스트 (모킹)
    │   └── AwakeStoreTests.swift
    └── TerminalLauncherTests/              (new test target)
        └── TerminalAppTests.swift
```

Package.swift 변경:
- 새 target `TerminalLauncher` (`Sources/TerminalLauncher/`)
- 새 target `Features` (`Sources/Features/`)
- `MuxBarApp` 에 `Features` 의존성 추가
- 새 test target `TerminalLauncherTests`

---

## Task 1: Package.swift — TerminalLauncher + Features 타겟 추가

**Files:** `Package.swift`

- [ ] **Step 1: Package.swift 수정**

Edit `/Users/gideok-kwon/IdeaProjects/muxbar/Package.swift` — add two new library targets and a test target. Insert these INSIDE the `targets:` array before the test targets:

```swift
.target(
    name: "TerminalLauncher",
    dependencies: ["Core", "MuxLogging", .product(name: "Logging", package: "swift-log")],
    swiftSettings: [.enableExperimentalFeature("StrictConcurrency")]
),
.target(
    name: "Features",
    dependencies: ["Core", "TmuxKit", "TerminalLauncher", "MuxLogging", .product(name: "Logging", package: "swift-log")],
    swiftSettings: [.enableExperimentalFeature("StrictConcurrency")]
),
```

Modify the `MuxBarApp` target's dependencies to include `"Features"` and `"TerminalLauncher"`:
```swift
.executableTarget(
    name: "MuxBarApp",
    dependencies: ["Core", "TmuxKit", "Features", "TerminalLauncher", "MuxLogging", .product(name: "Logging", package: "swift-log")],
    swiftSettings: [.enableExperimentalFeature("StrictConcurrency")]
),
```

Add to testTargets array:
```swift
.testTarget(name: "TerminalLauncherTests", dependencies: ["TerminalLauncher"]),
```

- [ ] **Step 2: Stub 파일 생성 (SPM 요구사항)**

Create `/Users/gideok-kwon/IdeaProjects/muxbar/Sources/TerminalLauncher/.gitkeep` — actually create a real stub:

Create `/Users/gideok-kwon/IdeaProjects/muxbar/Sources/TerminalLauncher/TerminalLauncher.swift`:
```swift
// Placeholder — filled in Task 4
import Foundation
```

Create `/Users/gideok-kwon/IdeaProjects/muxbar/Sources/Features/Features.swift`:
```swift
// Placeholder — filled in Tasks 7+
import Foundation
```

Create `/Users/gideok-kwon/IdeaProjects/muxbar/Tests/TerminalLauncherTests/TerminalLauncherTests.swift`:
```swift
import XCTest
@testable import TerminalLauncher

final class TerminalLauncherTestsPlaceholder: XCTestCase {
    func testPlaceholder() throws {
        throw XCTSkip("Populated in Task 4")
    }
}
```

- [ ] **Step 3: Build 확인**

Run: `cd /Users/gideok-kwon/IdeaProjects/muxbar && swift build 2>&1 | tail -3`
Expected: `Build complete!`

- [ ] **Step 4: Commit**

```bash
git add Package.swift Sources/TerminalLauncher Sources/Features Tests/TerminalLauncherTests
git commit -m "chore(spm): TerminalLauncher + Features 타겟 스캐폴딩"
```

---

## Task 2: SessionStore — @MainActor ObservableObject 골격

**Files:**
- Create: `Sources/Core/SessionStore.swift`

SessionStore 는 UI 레이어(@MainActor) 에서 ControlClient(actor) 를 감싸는 reactive wrapper. @Published 프로퍼티로 SwiftUI 바인딩.

- [ ] **Step 1: SessionStore.swift 작성**

Create `/Users/gideok-kwon/IdeaProjects/muxbar/Sources/Core/SessionStore.swift`:
```swift
import Foundation
import Combine
import MuxLogging

@MainActor
public final class SessionStore: ObservableObject {
    @Published public private(set) var sessions: [TmuxSession] = []
    @Published public private(set) var connectionState: ConnectionState = .disconnected
    @Published public private(set) var lastError: String?

    private let logger = MuxLogging.logger("Core.SessionStore")

    public init() {}

    public var userVisibleSessions: [TmuxSession] {
        sessions.filter { !$0.isInternal }
    }

    public var awakeSessionExists: Bool {
        sessions.contains { $0.id == "_muxbar-awake" }
    }

    /// 외부에서 주입 (테스트용 / 실행 시 TmuxKit 연결)
    public func apply(sessions: [TmuxSession]) {
        self.sessions = sessions
    }

    public func apply(connectionState: ConnectionState) {
        self.connectionState = connectionState
    }

    public func apply(error: String?) {
        self.lastError = error
        if let error {
            logger.error("\(error)")
        }
    }
}
```

Note: TmuxSession은 이미 Core 모듈에 있음. 같은 모듈이라 import 불필요.

- [ ] **Step 2: 단위 테스트 작성**

Create `/Users/gideok-kwon/IdeaProjects/muxbar/Tests/CoreTests/SessionStoreTests.swift`:
```swift
import XCTest
@testable import Core

@MainActor
final class SessionStoreTests: XCTestCase {
    func test_userVisibleSessions_filtersInternal() async {
        let store = SessionStore()
        store.apply(sessions: [
            TmuxSession(id: "dev", isAttached: false, windowCount: 1, createdAt: .now, lastActivityAt: .now, workingDirectory: nil),
            TmuxSession(id: "_muxbar-ctl", isAttached: false, windowCount: 1, createdAt: .now, lastActivityAt: .now, workingDirectory: nil),
            TmuxSession(id: "_muxbar-awake", isAttached: false, windowCount: 1, createdAt: .now, lastActivityAt: .now, workingDirectory: nil),
        ])

        XCTAssertEqual(store.userVisibleSessions.map(\.id), ["dev"])
    }

    func test_awakeSessionExists_detectsAwakeSession() async {
        let store = SessionStore()
        XCTAssertFalse(store.awakeSessionExists)

        store.apply(sessions: [
            TmuxSession(id: "_muxbar-awake", isAttached: false, windowCount: 1, createdAt: .now, lastActivityAt: .now, workingDirectory: nil),
        ])
        XCTAssertTrue(store.awakeSessionExists)
    }
}
```

- [ ] **Step 3: Build + Commit**

```bash
swift build 2>&1 | tail -3
git add Sources/Core/SessionStore.swift Tests/CoreTests/SessionStoreTests.swift
git commit -m "feat(Core): SessionStore @MainActor ObservableObject + 필터"
```

---

## Task 3: SessionStore — ControlClient 연결 + 이벤트 스트림 구독

**Files:**
- Modify: `Sources/Core/SessionStore.swift`

⚠️ SessionStore 는 Core 모듈, ControlClient 는 TmuxKit 모듈. Core 가 TmuxKit 에 의존하면 안 됨 (역방향). 대신 **프로토콜을 Core 에 정의하고 TmuxKit 구현이 준수**하는 방식.

- [ ] **Step 1: SessionProvider 프로토콜 정의**

Append to `/Users/gideok-kwon/IdeaProjects/muxbar/Sources/Core/SessionStore.swift`:
```swift

/// Core 에서 TmuxKit 구현을 추상화하기 위한 프로토콜. TmuxKit.ControlClient 가 conformance 제공.
public protocol SessionProvider: Sendable {
    func listSessions() async throws -> [TmuxSession]
    func kill(sessionName: String) async throws
    func createSession(name: String, command: String?) async throws
    var events: AsyncStream<SessionProviderEvent> { get }
}

public enum SessionProviderEvent: Sendable, Equatable {
    case sessionsChanged
    case connectionLost
    case unknown
}
```

- [ ] **Step 2: SessionStore.bind(to:) 추가**

Append to SessionStore class (inside, before closing `}`):
```swift
    private var bindingTask: Task<Void, Never>?

    public func bind(to provider: any SessionProvider) {
        bindingTask?.cancel()
        bindingTask = Task { [weak self] in
            await self?.initialLoad(from: provider)
            for await event in provider.events {
                guard let self else { break }
                switch event {
                case .sessionsChanged:
                    await self.refresh(from: provider)
                case .connectionLost:
                    self.apply(connectionState: .disconnected)
                case .unknown:
                    break
                }
            }
        }
    }

    public func unbind() {
        bindingTask?.cancel()
        bindingTask = nil
    }

    private func initialLoad(from provider: any SessionProvider) async {
        do {
            self.connectionState = .connecting(attempt: 1)
            let fetched = try await provider.listSessions()
            self.sessions = fetched
            self.connectionState = .connected
        } catch {
            self.apply(error: "initial load failed: \(error.localizedDescription)")
            self.connectionState = .failed(reason: error.localizedDescription)
        }
    }

    private func refresh(from provider: any SessionProvider) async {
        do {
            self.sessions = try await provider.listSessions()
        } catch {
            self.apply(error: "refresh failed: \(error.localizedDescription)")
        }
    }

    public func kill(_ session: TmuxSession, via provider: any SessionProvider) async {
        do {
            try await provider.kill(sessionName: session.id)
        } catch {
            self.apply(error: "kill failed: \(error.localizedDescription)")
        }
    }

    public func createSession(name: String, command: String?, via provider: any SessionProvider) async {
        do {
            try await provider.createSession(name: name, command: command)
        } catch {
            self.apply(error: "create failed: \(error.localizedDescription)")
        }
    }
```

- [ ] **Step 3: Build + Commit**

```bash
swift build 2>&1 | tail -3
git add Sources/Core/SessionStore.swift
git commit -m "feat(Core): SessionProvider 프로토콜 + SessionStore bind/unbind/refresh"
```

---

## Task 4: TerminalLauncher — TerminalApp enum + Terminal.app adapter

**Files:**
- Create: `Sources/TerminalLauncher/TerminalApp.swift`
- Create: `Sources/TerminalLauncher/TerminalAdapter.swift`
- Modify: `Sources/TerminalLauncher/TerminalLauncher.swift` (delete 내용, re-export 정도만)

- [ ] **Step 1: TerminalApp enum**

Create `/Users/gideok-kwon/IdeaProjects/muxbar/Sources/TerminalLauncher/TerminalApp.swift`:
```swift
import Foundation

public enum TerminalApp: String, Sendable, CaseIterable, Identifiable {
    case terminal  = "com.apple.Terminal"
    case iterm2    = "com.googlecode.iterm2"
    case warp      = "dev.warp.Warp-Stable"
    case alacritty = "org.alacritty"
    case kitty     = "net.kovidgoyal.kitty"

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .terminal: return "Terminal"
        case .iterm2:   return "iTerm2"
        case .warp:     return "Warp"
        case .alacritty: return "Alacritty"
        case .kitty:    return "kitty"
        }
    }

    public func isInstalled() -> Bool {
        NSWorkspace.shared.urlForApplication(withBundleIdentifier: rawValue) != nil
    }
}

#if canImport(AppKit)
import AppKit
#endif
```

- [ ] **Step 2: TerminalAdapter**

Create `/Users/gideok-kwon/IdeaProjects/muxbar/Sources/TerminalLauncher/TerminalAdapter.swift`:
```swift
import Foundation
#if canImport(AppKit)
import AppKit
#endif
import MuxLogging

public enum TerminalLaunchError: Error, Equatable {
    case notInstalled(TerminalApp)
    case scriptFailed(String)
    case tmuxNotFound
}

public struct TerminalAdapter: Sendable {
    private let logger = MuxLogging.logger("TerminalLauncher.Adapter")
    private let tmuxPath: String

    public init(tmuxPath: String) {
        self.tmuxPath = tmuxPath
    }

    public func attach(sessionName: String, using app: TerminalApp) async throws {
        guard app.isInstalled() else { throw TerminalLaunchError.notInstalled(app) }

        let tmuxCommand = "\(tmuxPath) attach -t \(shellQuote(sessionName))"
        logger.info("attach \(sessionName, privacy: .public) via \(app.displayName, privacy: .public)")

        switch app {
        case .terminal:
            try runOsascript(#"""
            tell application "Terminal"
                activate
                do script "\#(escapeForAppleScript(tmuxCommand))"
            end tell
            """#)
        case .iterm2:
            try runOsascript(#"""
            tell application "iTerm"
                activate
                if (count of windows) = 0 then
                    create window with default profile
                end if
                tell current window
                    tell current session to write text "\#(escapeForAppleScript(tmuxCommand))"
                end tell
            end tell
            """#)
        case .warp, .alacritty, .kitty:
            // Generic: open terminal with -e <cmd>
            try runOpenNewInstance(bundleId: app.rawValue, args: ["-e", tmuxPath, "attach", "-t", sessionName])
        }
    }

    private func runOsascript(_ script: String) throws {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
        p.arguments = ["-e", script]
        let errPipe = Pipe()
        p.standardError = errPipe
        p.standardOutput = Pipe()
        do {
            try p.run()
            p.waitUntilExit()
        } catch {
            throw TerminalLaunchError.scriptFailed(error.localizedDescription)
        }
        if p.terminationStatus != 0 {
            let err = String(data: errPipe.fileHandleForReading.availableData, encoding: .utf8) ?? ""
            throw TerminalLaunchError.scriptFailed("osascript exit=\(p.terminationStatus): \(err)")
        }
    }

    private func runOpenNewInstance(bundleId: String, args: [String]) throws {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/usr/bin/open")
        p.arguments = ["-na", "-b", bundleId, "--args"] + args
        let errPipe = Pipe()
        p.standardError = errPipe
        do {
            try p.run()
            p.waitUntilExit()
        } catch {
            throw TerminalLaunchError.scriptFailed(error.localizedDescription)
        }
        if p.terminationStatus != 0 {
            let err = String(data: errPipe.fileHandleForReading.availableData, encoding: .utf8) ?? ""
            throw TerminalLaunchError.scriptFailed("open exit=\(p.terminationStatus): \(err)")
        }
    }

    private func shellQuote(_ s: String) -> String {
        "'" + s.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }

    private func escapeForAppleScript(_ s: String) -> String {
        s.replacingOccurrences(of: "\\", with: "\\\\")
         .replacingOccurrences(of: "\"", with: "\\\"")
    }
}
```

- [ ] **Step 3: TerminalLauncher.swift 비우기**

Overwrite `/Users/gideok-kwon/IdeaProjects/muxbar/Sources/TerminalLauncher/TerminalLauncher.swift`:
```swift
// Umbrella file — public API re-exported from TerminalApp.swift and TerminalAdapter.swift
```

- [ ] **Step 4: 단위 테스트 작성 (enum 속성 검증)**

Overwrite `/Users/gideok-kwon/IdeaProjects/muxbar/Tests/TerminalLauncherTests/TerminalLauncherTests.swift`:
```swift
import XCTest
@testable import TerminalLauncher

final class TerminalAppTests: XCTestCase {
    func test_bundleIds_areUnique() {
        let ids = TerminalApp.allCases.map(\.rawValue)
        XCTAssertEqual(Set(ids).count, ids.count)
    }

    func test_displayNames() {
        XCTAssertEqual(TerminalApp.terminal.displayName, "Terminal")
        XCTAssertEqual(TerminalApp.iterm2.displayName, "iTerm2")
    }

    func test_isInstalled_terminalApp_shouldReturnTrueOnMac() {
        // Terminal.app 은 macOS 기본 제공
        XCTAssertTrue(TerminalApp.terminal.isInstalled())
    }
}
```

- [ ] **Step 5: Build + Commit**

```bash
swift build 2>&1 | tail -3
git add Sources/TerminalLauncher Tests/TerminalLauncherTests
git commit -m "feat(TerminalLauncher): 5개 터미널 adapter + AppleScript attach (Terminal/iTerm2 우선)"
```

---

## Task 5: Features/SessionList — SessionRowView + SessionListView

**Files:**
- Create: `Sources/Features/SessionList/SessionRowView.swift`
- Create: `Sources/Features/SessionList/SessionListView.swift`
- Modify: `Sources/Features/Features.swift` (keep as placeholder)

- [ ] **Step 1: SessionRowView**

Create `/Users/gideok-kwon/IdeaProjects/muxbar/Sources/Features/SessionList/SessionRowView.swift`:
```swift
import SwiftUI
import Core

public struct SessionRowView: View {
    public let session: TmuxSession
    public let onAttach: () -> Void
    public let onKill: () -> Void

    public init(session: TmuxSession, onAttach: @escaping () -> Void, onKill: @escaping () -> Void) {
        self.session = session
        self.onAttach = onAttach
        self.onKill = onKill
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

            Spacer(minLength: 8)

            Text("\(session.windowCount)w")
                .font(.caption)
                .foregroundStyle(.secondary)

            Menu {
                Button("Attach") { onAttach() }
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

- [ ] **Step 2: SessionListView**

Create `/Users/gideok-kwon/IdeaProjects/muxbar/Sources/Features/SessionList/SessionListView.swift`:
```swift
import SwiftUI
import Core

public struct SessionListView: View {
    @ObservedObject public var store: SessionStore
    public let onAttach: (TmuxSession) -> Void
    public let onKill: (TmuxSession) -> Void

    public init(store: SessionStore, onAttach: @escaping (TmuxSession) -> Void, onKill: @escaping (TmuxSession) -> Void) {
        self.store = store
        self.onAttach = onAttach
        self.onKill = onKill
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
                        onKill: { onKill(session) }
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
git commit -m "feat(Features): SessionRowView + SessionListView"
```

---

## Task 6: AwakeStore — KeepAwake 토글 로직

**Files:**
- Create: `Sources/Core/AwakeStore.swift`
- Create: `Tests/CoreTests/AwakeStoreTests.swift`

- [ ] **Step 1: AwakeStore 구현**

Create `/Users/gideok-kwon/IdeaProjects/muxbar/Sources/Core/AwakeStore.swift`:
```swift
import Foundation
import MuxLogging

@MainActor
public final class AwakeStore: ObservableObject {
    public static let awakeSessionName = "_muxbar-awake"

    @Published public private(set) var flags: CaffeinateFlags = .default
    @Published public private(set) var isToggling: Bool = false

    private let logger = MuxLogging.logger("Core.AwakeStore")

    public init(flags: CaffeinateFlags = .default) {
        self.flags = flags
    }

    public func setFlags(_ new: CaffeinateFlags) {
        guard new.isValid else { return }
        self.flags = new
    }

    /// SessionStore 의 awake 세션 존재 여부 참조.
    public func isAwake(in store: SessionStore) -> Bool {
        store.awakeSessionExists
    }

    /// 토글 수행. SessionStore 가 awake 세션 변경을 감지해 UI 자동 갱신.
    public func toggle(in store: SessionStore, via provider: any SessionProvider) async {
        isToggling = true
        defer { isToggling = false }

        if store.awakeSessionExists {
            await store.kill(
                TmuxSession(id: Self.awakeSessionName, isAttached: false, windowCount: 1,
                            createdAt: .now, lastActivityAt: .now, workingDirectory: nil),
                via: provider
            )
            logger.info("Keep Awake OFF")
        } else {
            let cmd = "caffeinate \(flags.cliArgs)"
            await store.createSession(name: Self.awakeSessionName, command: cmd, via: provider)
            logger.info("Keep Awake ON (caffeinate \(flags.cliArgs, privacy: .public))")
        }
    }
}
```

- [ ] **Step 2: 단위 테스트**

Create `/Users/gideok-kwon/IdeaProjects/muxbar/Tests/CoreTests/AwakeStoreTests.swift`:
```swift
import XCTest
@testable import Core

@MainActor
final class AwakeStoreTests: XCTestCase {
    func test_isAwake_delegatesToSessionStore() async {
        let sessions = SessionStore()
        let awake = AwakeStore()

        XCTAssertFalse(awake.isAwake(in: sessions))

        sessions.apply(sessions: [
            TmuxSession(id: "_muxbar-awake", isAttached: false, windowCount: 1,
                        createdAt: .now, lastActivityAt: .now, workingDirectory: nil)
        ])
        XCTAssertTrue(awake.isAwake(in: sessions))
    }

    func test_setFlags_rejectsInvalid() async {
        let awake = AwakeStore()
        let original = awake.flags

        let empty = CaffeinateFlags(d: false, i: false, m: false, s: false, u: false)
        awake.setFlags(empty)
        XCTAssertEqual(awake.flags, original, "invalid flags should be rejected")
    }
}
```

- [ ] **Step 3: Build + Commit**

```bash
swift build 2>&1 | tail -3
git add Sources/Core/AwakeStore.swift Tests/CoreTests/AwakeStoreTests.swift
git commit -m "feat(Core): AwakeStore — _muxbar-awake 세션 토글 로직"
```

---

## Task 7: Features/KeepAwake — 메뉴 아이템 뷰

**Files:**
- Create: `Sources/Features/KeepAwake/KeepAwakeMenuItem.swift`

- [ ] **Step 1: KeepAwakeMenuItem 작성**

Create `/Users/gideok-kwon/IdeaProjects/muxbar/Sources/Features/KeepAwake/KeepAwakeMenuItem.swift`:
```swift
import SwiftUI
import Core

public struct KeepAwakeMenuItem: View {
    @ObservedObject public var sessionStore: SessionStore
    @ObservedObject public var awakeStore: AwakeStore
    public let onToggle: () -> Void

    public init(sessionStore: SessionStore, awakeStore: AwakeStore, onToggle: @escaping () -> Void) {
        self.sessionStore = sessionStore
        self.awakeStore = awakeStore
        self.onToggle = onToggle
    }

    public var body: some View {
        HStack {
            Image(systemName: isAwake ? "cup.and.saucer.fill" : "cup.and.saucer")
                .foregroundStyle(isAwake ? .yellow : .secondary)
            Text("Keep Awake")
            Spacer()
            if awakeStore.isToggling {
                ProgressView().scaleEffect(0.6)
            } else {
                Text(isAwake ? "ON" : "OFF")
                    .font(.caption)
                    .foregroundStyle(isAwake ? .green : .secondary)
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .contentShape(Rectangle())
        .onTapGesture { onToggle() }
    }

    private var isAwake: Bool {
        awakeStore.isAwake(in: sessionStore)
    }
}
```

- [ ] **Step 2: Build + Commit**

```bash
swift build 2>&1 | tail -3
git add Sources/Features/KeepAwake
git commit -m "feat(Features): KeepAwakeMenuItem 뷰"
```

---

## Task 8: TmuxKit — ControlClient의 SessionProvider conformance

**Files:**
- Create: `Sources/TmuxKit/ControlClient+SessionProvider.swift`

TmuxKit 이 Core 에 의존하므로 ControlClient 에 SessionProvider 준수 구현을 추가할 수 있음.

- [ ] **Step 1: Adapter 파일 작성**

Create `/Users/gideok-kwon/IdeaProjects/muxbar/Sources/TmuxKit/ControlClient+SessionProvider.swift`:
```swift
import Foundation
import Core

extension ControlClient: SessionProvider {
    public var events: AsyncStream<SessionProviderEvent> {
        AsyncStream { continuation in
            let task = Task {
                for await raw in self.events {
                    switch raw {
                    case .sessionsChanged:
                        continuation.yield(.sessionsChanged)
                    case .exit:
                        continuation.yield(.connectionLost)
                    default:
                        break
                    }
                }
                continuation.finish()
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    public func kill(sessionName: String) async throws {
        _ = try await send(.killSession(name: sessionName))
    }

    public func createSession(name: String, command: String?) async throws {
        _ = try await send(.newSession(name: name, command: command))
    }
}
```

⚠️ Compilation 이슈 가능성: `self.events` 가 `AsyncStream<ControlEvent>` 이고 확장 프로퍼티 `events` 가 `AsyncStream<SessionProviderEvent>` 로 충돌. 해결책은 내부용 프로퍼티명 분리. 아래로 대체:

Actually the issue: `events` property of ControlClient is `AsyncStream<ControlEvent>` and we're adding another `events` with different type — **conflict**. Fix by renaming extension property:

Use this version instead:
```swift
import Foundation
import Core

extension ControlClient: SessionProvider {
    public var events: AsyncStream<SessionProviderEvent> {
        let rawEvents = self.events as AsyncStream<ControlEvent>
        return AsyncStream { continuation in
            let task = Task {
                for await raw in rawEvents {
                    switch raw {
                    case .sessionsChanged:
                        continuation.yield(.sessionsChanged)
                    case .exit:
                        continuation.yield(.connectionLost)
                    default:
                        break
                    }
                }
                continuation.finish()
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    public func kill(sessionName: String) async throws {
        _ = try await send(.killSession(name: sessionName))
    }

    public func createSession(name: String, command: String?) async throws {
        _ = try await send(.newSession(name: name, command: command))
    }
}
```

**If naming conflict persists at compile time**, rename ControlClient's raw events to `rawEvents`:
- Modify `Sources/TmuxKit/ControlClient.swift` line with `public nonisolated let events: AsyncStream<ControlEvent>` → rename to `public nonisolated let rawEvents: AsyncStream<ControlEvent>` and update `eventStreamContinuation` yield sites (they already yield to `eventStreamContinuation`, so only the public property name changes).

Do this rename if Step 1 build fails.

- [ ] **Step 2: Build 확인**

Run: `swift build 2>&1 | tail -10`
If naming conflict error → do the `rawEvents` rename fix.

- [ ] **Step 3: Commit**

```bash
git add Sources/TmuxKit
git commit -m "feat(TmuxKit): ControlClient → SessionProvider conformance"
```

---

## Task 9: AppState — 전역 Store 컨테이너 + 바인딩

**Files:**
- Create: `Sources/MuxBarApp/AppState.swift`

- [ ] **Step 1: AppState 작성**

Create `/Users/gideok-kwon/IdeaProjects/muxbar/Sources/MuxBarApp/AppState.swift`:
```swift
import Foundation
import SwiftUI
import Core
import TmuxKit
import TerminalLauncher
import MuxLogging

@MainActor
public final class AppState: ObservableObject {
    public let sessionStore: SessionStore
    public let awakeStore: AwakeStore
    public let terminalAdapter: TerminalAdapter?
    public private(set) var controlClient: ControlClient?

    private let logger = MuxLogging.logger("MuxBarApp.AppState")

    public init() {
        self.sessionStore = SessionStore()
        self.awakeStore = AwakeStore()

        if let tmuxPath = TmuxPath.resolve() {
            self.terminalAdapter = TerminalAdapter(tmuxPath: tmuxPath)
        } else {
            self.terminalAdapter = nil
        }
    }

    public func bootstrap() async {
        do {
            let client = try ControlClient()
            self.controlClient = client
            try await client.bootstrap()
            sessionStore.bind(to: client)
            logger.info("Bootstrap 완료")
        } catch {
            sessionStore.apply(error: "bootstrap 실패: \(error.localizedDescription)")
            sessionStore.apply(connectionState: .failed(reason: error.localizedDescription))
            logger.error("Bootstrap 실패: \(error.localizedDescription)")
        }
    }

    public func attach(_ session: TmuxSession, using app: TerminalApp = .terminal) {
        guard let adapter = terminalAdapter else {
            sessionStore.apply(error: "tmux 바이너리 없음")
            return
        }
        Task {
            do {
                try await adapter.attach(sessionName: session.id, using: app)
            } catch {
                sessionStore.apply(error: "attach 실패: \(error.localizedDescription)")
            }
        }
    }

    public func kill(_ session: TmuxSession) {
        guard let client = controlClient else { return }
        Task {
            await sessionStore.kill(session, via: client)
        }
    }

    public func toggleAwake() {
        guard let client = controlClient else { return }
        Task {
            await awakeStore.toggle(in: sessionStore, via: client)
        }
    }
}
```

- [ ] **Step 2: Build**

Run: `swift build 2>&1 | tail -5`
Expected: Build complete.

- [ ] **Step 3: Commit**

```bash
git add Sources/MuxBarApp/AppState.swift
git commit -m "feat(MuxBarApp): AppState — Store 컨테이너 + bootstrap/attach/kill/toggleAwake"
```

---

## Task 10: MuxBarApp — MenuBarExtra UI 조립

**Files:**
- Modify: `Sources/MuxBarApp/MuxBarApp.swift`

- [ ] **Step 1: MuxBarApp.swift 재작성**

Overwrite `/Users/gideok-kwon/IdeaProjects/muxbar/Sources/MuxBarApp/MuxBarApp.swift`:
```swift
import SwiftUI
import Core
import Features
import TerminalLauncher
import MuxLogging

@main
struct MuxBarApp: App {
    @StateObject private var appState = AppState()

    init() {
        MuxLogging.bootstrap()
        MuxLogging.logger("app").info("muxbar 기동")
    }

    var body: some Scene {
        MenuBarExtra {
            menuContent
                .task {
                    await appState.bootstrap()
                }
        } label: {
            Image(systemName: iconName)
        }
        .menuBarExtraStyle(.window)
    }

    private var iconName: String {
        if appState.awakeStore.isAwake(in: appState.sessionStore) {
            return "terminal.fill"
        }
        return "terminal"
    }

    @ViewBuilder
    private var menuContent: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            Divider()
            SessionListView(
                store: appState.sessionStore,
                onAttach: { appState.attach($0) },
                onKill: { appState.kill($0) }
            )
            Divider()
            KeepAwakeMenuItem(
                sessionStore: appState.sessionStore,
                awakeStore: appState.awakeStore,
                onToggle: { appState.toggleAwake() }
            )
            Divider()
            Button("Quit muxbar") { NSApplication.shared.terminate(nil) }
                .keyboardShortcut("q")
                .padding(.horizontal, 8)
                .padding(.vertical, 6)
        }
        .frame(width: 320)
    }

    private var header: some View {
        HStack {
            Image(systemName: "terminal.fill")
            Text("muxbar")
                .font(.headline)
            Spacer()
            if case .connected = appState.sessionStore.connectionState {
                Circle().fill(.green).frame(width: 8, height: 8)
            } else {
                Circle().fill(.orange).frame(width: 8, height: 8)
            }
        }
        .padding(8)
    }
}
```

- [ ] **Step 2: Build + 실행 검증**

```bash
cd /Users/gideok-kwon/IdeaProjects/muxbar
swift build -c release 2>&1 | tail -3
pkill -f muxbar 2>/dev/null
sleep 1
./.build/release/muxbar > /tmp/muxbar.log 2>&1 &
sleep 3
pgrep -fl muxbar
cat /tmp/muxbar.log | head -10
```

기대:
- 프로세스 PID 출력
- 로그 라인 `muxbar 기동` + `Bootstrap 완료` 표시
- 메뉴바 아이콘 클릭 시 세션 리스트 (없으면 "세션 없음" 표시) + Keep Awake 토글 + Quit

- [ ] **Step 3: 수동 기능 테스트**

먼저 tmux 로 세션 만들어두고 다시 테스트:
```bash
tmux new-session -d -s test-dev -c /tmp
tmux new-session -d -s test-api -c /Users
# 2초 이내 메뉴 재열기 → 두 세션 보여야 함
```

Keep Awake 클릭:
```bash
# 토글 전
tmux ls | grep muxbar-awake  # 없음
# (클릭)
# 토글 후
tmux ls | grep muxbar-awake  # _muxbar-awake 세션 보임
pmset -g assertions | grep -i caffeinate  # caffeinate 프로세스 확인
```

테스트 세션 정리:
```bash
tmux kill-session -t test-dev
tmux kill-session -t test-api
```

- [ ] **Step 4: Commit**

```bash
git add Sources/MuxBarApp/MuxBarApp.swift
git commit -m "feat(MuxBarApp): SessionList + KeepAwake + Connection 상태 통합 UI"
```

---

## Task 11: README 업데이트 + ADR-0002

**Files:**
- Modify: `README.md`
- Create: `docs/adr/ADR-0002-sessionprovider-protocol.md`
- Modify: `docs/README.md`

- [ ] **Step 1: README "현재 상태" 업데이트**

Edit `/Users/gideok-kwon/IdeaProjects/muxbar/README.md` — replace the `> 상태:` line and "빌드 & 실행" block:

```markdown
> **상태**: 개발 중 (v0.1 MVP). Plan 2 (SessionList + KeepAwake) 완료.

## 사전 요구사항

- macOS 13 (Ventura) 이상
- Swift 5.9+
- `tmux` (Homebrew: `brew install tmux`)

## 빌드 & 실행

```bash
swift build -c release
./.build/release/muxbar
```

메뉴바에서:
- tmux 세션 리스트 표시
- 각 세션 우측 `⋯` 메뉴 → Attach / Kill
- Keep Awake 토글 — caffeinate 세션 `_muxbar-awake` 생성/제거
- Quit 으로 종료
```

- [ ] **Step 2: ADR-0002 작성**

Create `/Users/gideok-kwon/IdeaProjects/muxbar/docs/adr/ADR-0002-sessionprovider-protocol.md`:
```markdown
# ADR-0002: SessionProvider 프로토콜 기반 UI-TmuxKit 분리

- Status: Accepted
- Date: 2026-04-17

## Context

SessionStore(@MainActor, Core 모듈) 가 ControlClient(actor, TmuxKit 모듈) 에 직접 의존하면
Core → TmuxKit 역방향 의존이 생겨 Clean Architecture 원칙 위배.

## Decision

- Core 에 `SessionProvider` 프로토콜 정의 (listSessions/kill/createSession/events)
- TmuxKit 에서 `extension ControlClient: SessionProvider` 로 conformance 제공
- SessionStore 는 프로토콜만 알고 구현체는 외부에서 주입

## Consequences

**장점**:
- Core ← TmuxKit 한 방향 의존 유지
- 테스트에서 Mock provider 주입 가능
- 미래에 remote tmux 지원 시 프로토콜 재구현만 하면 됨

**단점**:
- existential `any SessionProvider` 사용 (Swift 5.7+ 에서 성능 영향 크지 않음)
```

- [ ] **Step 3: docs/README.md 업데이트**

Edit `/Users/gideok-kwon/IdeaProjects/muxbar/docs/README.md` — replace the `## Plans` and `## ADRs` sections:

```markdown
## Plans
- [Plan 1 — Foundation + TmuxKit](plans/2026-04-17-plan-1-foundation-tmuxkit.md)
- [Plan 2 — SessionList + KeepAwake](plans/2026-04-17-plan-2-sessionlist-keepawake.md)
- Plan 3 — Live Preview *(예정)*
- Plan 4 — Terminals + Hotkeys + Templates *(예정)*
- Plan 5 — Notifications + Distribution *(예정)*

## ADRs
- [ADR-0001: tmux control mode 채택](adr/ADR-0001-tmux-control-mode-over-polling.md)
- [ADR-0002: SessionProvider 프로토콜 분리](adr/ADR-0002-sessionprovider-protocol.md)
```

- [ ] **Step 4: Commit + 태그**

```bash
git add README.md docs/
git commit -m "docs: Plan 2 완료 — README + ADR-0002"
git tag -a plan-2-complete -m "Plan 2: SessionList + KeepAwake 완료"
```

---

## Plan 2 완료 기준

- [x] `swift build` 성공
- [x] 메뉴바에서 tmux 세션 리스트 확인 가능
- [x] Attach → Terminal.app 에서 tmux 세션 열림
- [x] Kill → 세션 사라짐
- [x] Keep Awake 토글 → `_muxbar-awake` 세션 생성/제거, `pmset -g assertions` 로 caffeinate 확인
- [x] ADR-0002 작성

## Plan 3 예고

**범위**: M4 — L2 (마지막 출력 스냅샷) + L3 (라이브 프리뷰)

**주요 Task**:
1. SwiftTerm 의존성 추가
2. PaneRenderer (headless Terminal + NSAttributedString)
3. Session hover 팝오버
4. %output 실시간 스트리밍 → SwiftTerm.feed
5. 50 FPS throttle + dirty-line 최적화
