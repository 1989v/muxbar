# muxbar Plan 4 — Hotkeys + Templates Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: superpowers:subagent-driven-development

**Goal:** 전역 단축키(⌘⇧T/A/1~9), 5종 기본 템플릿(Dev/WebDev/Monitoring/SSH/Docker), 즐겨찾기 매핑.

**Architecture:** HotKey 패키지(Carbon API 래퍼)로 전역 단축키 등록. Template 구조체는 YAML(Yams)에서 로드, bundled 5종 + 사용자 디렉터리 `~/Library/Application Support/muxbar/Templates/`.

**Tech Stack:** [soffes/HotKey](https://github.com/soffes/HotKey), [Yams](https://github.com/jpsim/Yams).

---

## Task 1: 의존성 추가 (HotKey + Yams)

**Files:** `Package.swift`

- [ ] **Step 1: Package.swift 수정**

Add to `dependencies`:
```swift
.package(url: "https://github.com/soffes/HotKey.git", from: "0.2.0"),
.package(url: "https://github.com/jpsim/Yams.git", from: "5.0.0"),
```

Add products to `Features` target:
```swift
.product(name: "HotKey", package: "HotKey"),
.product(name: "Yams", package: "Yams")
```

- [ ] **Step 2: Resolve + Build**

```bash
cd /Users/gideok-kwon/IdeaProjects/muxbar
swift package resolve 2>&1 | tail -5
swift build 2>&1 | tail -3
```

- [ ] **Step 3: Commit**

```bash
git add Package.swift
git commit -m "chore(deps): HotKey + Yams 추가"
```

---

## Task 2: Template 모델 + 로더

**Files:**
- Create: `Sources/Core/Model/Template.swift`
- Create: `Sources/Features/Templates/TemplateLoader.swift`
- Create: `Sources/Features/Templates/Resources/` (5 YAML 파일)

- [ ] **Step 1: Template 모델**

Create `/Users/gideok-kwon/IdeaProjects/muxbar/Sources/Core/Model/Template.swift`:
```swift
import Foundation

public struct Template: Codable, Identifiable, Sendable, Equatable {
    public let id: UUID
    public var name: String
    public var description: String
    public var sessionNameHint: String
    public var windows: [TemplateWindow]

    public init(id: UUID = UUID(), name: String, description: String, sessionNameHint: String, windows: [TemplateWindow]) {
        self.id = id
        self.name = name
        self.description = description
        self.sessionNameHint = sessionNameHint
        self.windows = windows
    }
}

public struct TemplateWindow: Codable, Sendable, Equatable {
    public var name: String
    public var command: String?
    public var cwd: String?

    public init(name: String, command: String? = nil, cwd: String? = nil) {
        self.name = name; self.command = command; self.cwd = cwd
    }
}
```

- [ ] **Step 2: 내장 템플릿 정의 (Swift 코드로, Resources YAML 대신 단순화)**

Create `/Users/gideok-kwon/IdeaProjects/muxbar/Sources/Features/Templates/BuiltInTemplates.swift`:
```swift
import Foundation
import Core

public enum BuiltInTemplates {
    public static let all: [Template] = [dev, webDev, monitoring, ssh, docker]

    public static let dev = Template(
        name: "Dev",
        description: "에디터 + 빌드 + 로그",
        sessionNameHint: "dev",
        windows: [
            TemplateWindow(name: "edit"),
            TemplateWindow(name: "run"),
            TemplateWindow(name: "logs")
        ]
    )

    public static let webDev = Template(
        name: "WebDev",
        description: "Next/Vite dev server + 로그",
        sessionNameHint: "web",
        windows: [
            TemplateWindow(name: "edit"),
            TemplateWindow(name: "dev-server", command: "npm run dev"),
            TemplateWindow(name: "logs")
        ]
    )

    public static let monitoring = Template(
        name: "Monitoring",
        description: "htop + tail",
        sessionNameHint: "mon",
        windows: [
            TemplateWindow(name: "htop", command: "htop"),
            TemplateWindow(name: "syslog", command: "tail -f /var/log/system.log")
        ]
    )

    public static let ssh = Template(
        name: "SSH",
        description: "원격 접속 기본",
        sessionNameHint: "ssh",
        windows: [TemplateWindow(name: "remote")]
    )

    public static let docker = Template(
        name: "Docker",
        description: "docker ps + compose logs",
        sessionNameHint: "docker",
        windows: [
            TemplateWindow(name: "ps", command: "watch -n 2 docker ps"),
            TemplateWindow(name: "logs", command: "docker compose logs -f")
        ]
    )
}
```

- [ ] **Step 3: Build + Commit**

```bash
swift build 2>&1 | tail -3
git add Sources/Core/Model/Template.swift Sources/Features/Templates
git commit -m "feat: Template 모델 + 내장 5종 (Dev/WebDev/Monitoring/SSH/Docker)"
```

---

## Task 3: TemplateRunner — Template 실행 로직

**Files:** `Sources/Features/Templates/TemplateRunner.swift`

- [ ] **Step 1: TemplateRunner 작성**

Create `/Users/gideok-kwon/IdeaProjects/muxbar/Sources/Features/Templates/TemplateRunner.swift`:
```swift
import Foundation
import Core
import TmuxKit
import MuxLogging

@MainActor
public final class TemplateRunner {
    private let logger = MuxLogging.logger("Features.TemplateRunner")

    public init() {}

    /// 템플릿을 실행. 세션 이름은 hint 기반 unique 이름 생성.
    public func run(template: Template, via client: ControlClient, existingSessions: [TmuxSession]) async throws -> String {
        let sessionName = uniqueName(base: template.sessionNameHint, existing: existingSessions)

        // 첫 window 는 new-session 으로 동시 생성
        guard let firstWindow = template.windows.first else {
            throw TemplateError.emptyTemplate
        }

        // new-session + 첫 윈도우 생성
        let firstCommand = firstWindow.command
        _ = try await client.send(.newSession(name: sessionName, command: firstCommand))

        // 나머지 window 는 new-window 로 추가
        for window in template.windows.dropFirst() {
            var cmd = "new-window -t \(shellQuote(sessionName)) -n \(shellQuote(window.name))"
            if let wcmd = window.command {
                cmd += " \(shellQuote(wcmd))"
            }
            _ = try await client.sendRaw(cmd)
        }

        logger.info("template '\(template.name)' → session '\(sessionName)'")
        return sessionName
    }

    private func uniqueName(base: String, existing: [TmuxSession]) -> String {
        let existingIds = Set(existing.map(\.id))
        if !existingIds.contains(base) { return base }
        for i in 2...99 {
            let candidate = "\(base)-\(i)"
            if !existingIds.contains(candidate) { return candidate }
        }
        return "\(base)-\(Int.random(in: 100...999))"
    }

    private func shellQuote(_ s: String) -> String {
        "\"" + s.replacingOccurrences(of: "\"", with: "\\\"") + "\""
    }
}

public enum TemplateError: Error, Equatable {
    case emptyTemplate
    case sessionCreateFailed(String)
}
```

- [ ] **Step 2: ControlClient.sendRaw 추가**

Edit `/Users/gideok-kwon/IdeaProjects/muxbar/Sources/TmuxKit/ControlClient.swift` — add method:
```swift
    /// TmuxCommand enum 에 없는 raw 문자열 커맨드 전송 (템플릿 확장용)
    @discardableResult
    public func sendRaw(_ commandLine: String, timeout: TimeInterval = 5.0) async throws -> String {
        guard let stdin = stdinPipe?.fileHandleForWriting else {
            throw ClientError.notConnected
        }
        return try await withCheckedThrowingContinuation { continuation in
            Task {
                await self.registerNextPendingCommand(continuation: continuation)
                let line = commandLine + "\n"
                if let data = line.data(using: .utf8) {
                    do { try stdin.write(contentsOf: data) }
                    catch { await self.rejectLastPending(error: error) }
                }
            }
        }
    }
```

- [ ] **Step 3: Build + Commit**

```bash
swift build 2>&1 | tail -5
git add Sources/Features/Templates/TemplateRunner.swift Sources/TmuxKit/ControlClient.swift
git commit -m "feat(Features): TemplateRunner + ControlClient.sendRaw"
```

---

## Task 4: TemplatePickerView — SwiftUI 메뉴

**Files:** `Sources/Features/Templates/TemplatePickerView.swift`

- [ ] **Step 1: View 작성**

Create `/Users/gideok-kwon/IdeaProjects/muxbar/Sources/Features/Templates/TemplatePickerView.swift`:
```swift
import SwiftUI
import Core

public struct TemplatePickerView: View {
    public let templates: [Template]
    public let onSelect: (Template) -> Void

    public init(templates: [Template] = BuiltInTemplates.all, onSelect: @escaping (Template) -> Void) {
        self.templates = templates
        self.onSelect = onSelect
    }

    public var body: some View {
        Menu {
            ForEach(templates) { template in
                Button {
                    onSelect(template)
                } label: {
                    VStack(alignment: .leading) {
                        Text(template.name)
                        Text(template.description).font(.caption).foregroundStyle(.secondary)
                    }
                }
            }
        } label: {
            HStack {
                Image(systemName: "plus.rectangle.on.rectangle")
                Text("New Session from Template…")
                Spacer()
            }
        }
        .menuStyle(.borderlessButton)
    }
}
```

- [ ] **Step 2: Build + Commit**

```bash
swift build 2>&1 | tail -3
git add Sources/Features/Templates/TemplatePickerView.swift
git commit -m "feat(Features): TemplatePickerView — 템플릿 선택 메뉴"
```

---

## Task 5: HotKeyCenter — 전역 단축키

**Files:** `Sources/Features/HotKeys/HotKeyCenter.swift`

- [ ] **Step 1: HotKeyCenter 작성**

Create `/Users/gideok-kwon/IdeaProjects/muxbar/Sources/Features/HotKeys/HotKeyCenter.swift`:
```swift
import Foundation
import AppKit
import HotKey
import MuxLogging

@MainActor
public final class HotKeyCenter {
    public typealias Action = @MainActor () -> Void

    private var hotKeys: [String: HotKey] = [:]
    private let logger = MuxLogging.logger("Features.HotKeyCenter")

    public init() {}

    public func register(id: String, key: Key, modifiers: NSEvent.ModifierFlags, action: @escaping Action) {
        let hk = HotKey(key: key, modifiers: modifiers)
        hk.keyDownHandler = action
        hotKeys[id] = hk
        logger.info("registered hotkey '\(id)'")
    }

    public func unregister(id: String) {
        hotKeys.removeValue(forKey: id)
    }

    public func unregisterAll() {
        hotKeys.removeAll()
    }
}
```

- [ ] **Step 2: Build + Commit**

```bash
swift build 2>&1 | tail -3
git add Sources/Features/HotKeys
git commit -m "feat(Features): HotKeyCenter — 전역 단축키 래퍼"
```

---

## Task 6: AppState — Template + HotKey 연결

**Files:** `Sources/MuxBarApp/AppState.swift`

- [ ] **Step 1: AppState 확장**

Edit `/Users/gideok-kwon/IdeaProjects/muxbar/Sources/MuxBarApp/AppState.swift` — add:

Imports already include Features. Add:
```swift
// Properties
public let templateRunner: TemplateRunner
public let hotKeyCenter: HotKeyCenter

// In init():
self.templateRunner = TemplateRunner()
self.hotKeyCenter = HotKeyCenter()

// Add methods:
public func runTemplate(_ template: Template) {
    guard let client = controlClient else { return }
    Task {
        do {
            let sessionName = try await templateRunner.run(
                template: template,
                via: client,
                existingSessions: sessionStore.sessions
            )
            sessionStore.apply(error: nil)
            _ = sessionName
        } catch {
            sessionStore.apply(error: "템플릿 실행 실패: \(error.localizedDescription)")
        }
    }
}

public func registerHotkeys() {
    // ⌘⇧A — Toggle Keep Awake
    hotKeyCenter.register(id: "awake", key: .a, modifiers: [.command, .shift]) { [weak self] in
        self?.toggleAwake()
    }
    // ⌘⇧1~9 — 세션 리스트 n번째 attach (간단 버전: index 순서)
    for (idx, key) in [Key.one, .two, .three, .four, .five, .six, .seven, .eight, .nine].enumerated() {
        hotKeyCenter.register(id: "favorite-\(idx+1)", key: key, modifiers: [.command, .shift]) { [weak self] in
            guard let self else { return }
            let visible = self.sessionStore.userVisibleSessions
            guard idx < visible.count else { return }
            self.attach(visible[idx])
        }
    }
}
```

`import HotKey` at top.

- [ ] **Step 2: bootstrap 후 registerHotkeys 호출**

In `bootstrap()` method, after `sessionStore.bind(to: client)`, add:
```swift
registerHotkeys()
```

- [ ] **Step 3: Build + Commit**

```bash
swift build 2>&1 | tail -5
git add Sources/MuxBarApp/AppState.swift
git commit -m "feat(MuxBarApp): AppState — Template 실행 + 전역 단축키 등록"
```

---

## Task 7: MuxBarApp — Template menu + relaunch

**Files:** `Sources/MuxBarApp/MuxBarApp.swift`

- [ ] **Step 1: menuContent 업데이트**

Edit `/Users/gideok-kwon/IdeaProjects/muxbar/Sources/MuxBarApp/MuxBarApp.swift` — add TemplatePickerView before the KeepAwake divider:

Find the existing `Divider()` before KeepAwake, add this AFTER the popover block and BEFORE that Divider:
```swift
TemplatePickerView { template in
    appState.runTemplate(template)
}
.padding(.horizontal, 8)
.padding(.vertical, 4)
```

Also add `import Features` at top if not present.

- [ ] **Step 2: Release build + relaunch**

```bash
cd /Users/gideok-kwon/IdeaProjects/muxbar
swift build -c release 2>&1 | tail -3
pkill -f muxbar 2>/dev/null
sleep 1
./.build/release/muxbar > /tmp/muxbar.log 2>&1 &
sleep 3
pgrep -fl muxbar
head -10 /tmp/muxbar.log
```

- [ ] **Step 3: Commit + 태그**

```bash
git add Sources/MuxBarApp/MuxBarApp.swift
git commit -m "feat(MuxBarApp): Template 메뉴 + HotKey 활성"
git tag -a plan-4-complete -m "Plan 4: Templates + HotKeys 완료"
```

---

## Task 8: ADR-0004 + docs

**Files:**
- Create: `docs/adr/ADR-0004-hotkey-template.md`
- Modify: `docs/README.md`

- [ ] **Step 1: ADR**

Create `/Users/gideok-kwon/IdeaProjects/muxbar/docs/adr/ADR-0004-hotkey-template.md`:
```markdown
# ADR-0004: HotKey + Template 통합

- Status: Accepted
- Date: 2026-04-17

## Context

- 전역 단축키: Carbon API 직접 호출 vs 라이브러리 사용
- 템플릿: YAML 파일 로딩 vs Swift 코드 정의

## Decision

- **HotKey**: soffes/HotKey (MIT, 300★) — Carbon `RegisterEventHotKey` 래퍼
- **Template**: v0.1 은 Swift 코드(`BuiltInTemplates`)로 정의, v0.2 에서 YAML 사용자 템플릿 지원

## Consequences

**장점**:
- HotKey: 단축키 등록 코드 3줄로 간결
- Template 코드 정의: YAML 파서 불필요, 초기 MVP 복잡도 ↓

**단점**:
- HotKey 의존성 추가
- 사용자가 템플릿 편집 불가 (v0.2 에서 해결)
```

- [ ] **Step 2: docs/README.md 업데이트**

Append ADR-0004 to ADRs section; change "Plan 4 예정" to link.

- [ ] **Step 3: Commit**

```bash
git add docs/
git commit -m "docs: Plan 4 완료 — ADR-0004 + README"
```

---

## Plan 4 완료 기준

- [x] HotKey + Yams 의존성 resolve
- [x] 내장 템플릿 5종 정의
- [x] "New Session from Template" 메뉴에서 1클릭 실행 가능
- [x] ⌘⇧A 로 Keep Awake 토글
- [x] ⌘⇧1~9 로 세션 attach
- [x] ADR-0004 작성

## Plan 5 예고

M6+M7: Notifications (idle/crash), Login Item (SMAppService), Release 패키징 (Xcode 필요).
