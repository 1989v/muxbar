# muxbar Plan 1 — Foundation + TmuxKit Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** SPM 프로젝트 스켈레톤을 세우고 tmux control mode 클라이언트 라이브러리(TmuxKit)를 단위 테스트와 함께 완성한다. 이 plan 완료 시점에 메뉴바 앱이 기동되고(빈 메뉴), TmuxKit 를 통해 tmux 서버와 통신·이벤트 수신·명령 실행이 가능하다.

**Architecture:** Swift Package Manager 단일 모노패키지. `MuxBarApp` executable + 여러 library 타겟(`Core`, `TmuxKit`). tmux control mode 프로토콜(`tmux -C`)을 `Process`/`Pipe`로 스폰하고, 라인 단위 파서가 `%begin/%end/%output` 등을 구조화된 이벤트로 변환. 명령 송신은 async/await + cmdId→Continuation 매핑으로 응답 매칭.

**Tech Stack:** Swift 5.9+, SwiftUI (MenuBarExtra), Swift Concurrency, swift-log, XCTest, SwiftPM.

---

## File Structure

생성될 파일 (Plan 1 범위):

```
muxbar/
├── Package.swift                                     # SPM manifest
├── .gitignore
├── .swiftlint.yml
├── README.md                                         # 기존 파일, 보강
├── Sources/
│   ├── MuxBarApp/
│   │   ├── MuxBarApp.swift                           # @main App
│   │   └── AppState.swift                            # 전역 상태 컨테이너
│   ├── Core/
│   │   ├── Model/
│   │   │   ├── TmuxSession.swift
│   │   │   ├── TmuxWindow.swift
│   │   │   ├── TmuxPane.swift
│   │   │   └── CaffeinateFlags.swift
│   │   └── ConnectionState.swift
│   ├── TmuxKit/
│   │   ├── TmuxPath.swift                            # 바이너리 경로 해석
│   │   ├── ControlEvent.swift                        # 이벤트 enum
│   │   ├── ControlProtocol.swift                     # 라인 파서
│   │   ├── ControlClient.swift                       # Process/Pipe + 이벤트 스트림
│   │   ├── Commands.swift                            # 타입 세이프 커맨드
│   │   └── OctalUnescape.swift                       # %output 디코딩
│   └── Logging/
│       └── Logger+muxbar.swift                       # swift-log 부트스트랩
└── Tests/
    ├── CoreTests/
    │   ├── CaffeinateFlagsTests.swift
    │   └── ModelEqualityTests.swift
    ├── TmuxKitTests/
    │   ├── ControlProtocolTests.swift
    │   ├── OctalUnescapeTests.swift
    │   ├── CommandsTests.swift
    │   └── TmuxPathTests.swift
    └── TmuxKitIntegrationTests/
        └── ControlClientLiveTests.swift              # 실제 tmux 바이너리 필요
```

---

## Task 1: SPM 프로젝트 골격

**Files:**
- Create: `Package.swift`
- Create: `.gitignore`
- Create: `Sources/MuxBarApp/MuxBarApp.swift`
- Create: `Sources/Core/ConnectionState.swift`

- [ ] **Step 1: Package.swift 작성**

Create `Package.swift`:
```swift
// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "muxbar",
    platforms: [.macOS(.v13)],
    products: [
        .executable(name: "muxbar", targets: ["MuxBarApp"]),
        .library(name: "TmuxKit", targets: ["TmuxKit"]),
        .library(name: "Core", targets: ["Core"]),
    ],
    dependencies: [
        .package(url: "https://github.com/apple/swift-log.git", from: "1.5.0"),
    ],
    targets: [
        .executableTarget(
            name: "MuxBarApp",
            dependencies: ["Core", "TmuxKit", .product(name: "Logging", package: "swift-log")],
            swiftSettings: [.enableExperimentalFeature("StrictConcurrency")]
        ),
        .target(
            name: "Core",
            dependencies: [.product(name: "Logging", package: "swift-log")],
            swiftSettings: [.enableExperimentalFeature("StrictConcurrency")]
        ),
        .target(
            name: "TmuxKit",
            dependencies: ["Core", .product(name: "Logging", package: "swift-log")],
            swiftSettings: [.enableExperimentalFeature("StrictConcurrency")]
        ),
        .testTarget(name: "CoreTests", dependencies: ["Core"]),
        .testTarget(name: "TmuxKitTests", dependencies: ["TmuxKit"]),
        .testTarget(name: "TmuxKitIntegrationTests", dependencies: ["TmuxKit"]),
    ]
)
```

- [ ] **Step 2: .gitignore 작성**

Create `.gitignore`:
```
.DS_Store
.build/
.swiftpm/
*.xcodeproj/
Package.resolved
.vscode/
DerivedData/
```

- [ ] **Step 3: 최소 MuxBarApp.swift 작성**

Create `Sources/MuxBarApp/MuxBarApp.swift`:
```swift
import SwiftUI

@main
struct MuxBarApp: App {
    var body: some Scene {
        MenuBarExtra("muxbar", systemImage: "terminal") {
            Text("muxbar 기동됨")
                .padding()
            Divider()
            Button("Quit") { NSApplication.shared.terminate(nil) }
                .keyboardShortcut("q")
        }
        .menuBarExtraStyle(.window)
    }
}
```

- [ ] **Step 4: Core/ConnectionState.swift 작성**

Create `Sources/Core/ConnectionState.swift`:
```swift
import Foundation

public enum ConnectionState: Sendable, Equatable {
    case disconnected
    case connecting(attempt: Int)
    case connected
    case reconnecting(nextAttemptIn: TimeInterval)
    case failed(reason: String)
}
```

- [ ] **Step 5: 빌드 확인**

Run: `cd /Users/gideok-kwon/IdeaProjects/muxbar && swift build`
Expected: `Build complete!` 메시지. `.build/` 디렉터리 생성.

- [ ] **Step 6: 실행 스모크 테스트**

Run: `swift run muxbar &`
Expected: 메뉴바 우측에 `terminal` 아이콘 표시. 클릭 시 "muxbar 기동됨" 문구 + Quit 버튼.
이후: `pkill -f muxbar` 로 종료.

- [ ] **Step 7: Commit**

```bash
cd /Users/gideok-kwon/IdeaProjects/muxbar
git add Package.swift .gitignore Sources/
git commit -m "feat: SPM 프로젝트 골격 + MenuBarExtra 스텁"
```

---

## Task 2: Logging 부트스트랩

**Files:**
- Create: `Sources/Logging/Logger+muxbar.swift`
- Modify: `Sources/MuxBarApp/MuxBarApp.swift`
- Modify: `Package.swift`

- [ ] **Step 1: Logging 타겟 추가**

Edit `Package.swift`, add to `targets` array (before `.testTarget`s):
```swift
.target(
    name: "MuxLogging",
    dependencies: [.product(name: "Logging", package: "swift-log")],
    swiftSettings: [.enableExperimentalFeature("StrictConcurrency")]
),
```

그리고 `MuxBarApp`, `Core`, `TmuxKit` 의 dependencies 에 `"MuxLogging"` 추가:
```swift
.executableTarget(
    name: "MuxBarApp",
    dependencies: ["Core", "TmuxKit", "MuxLogging", .product(name: "Logging", package: "swift-log")],
    // ...
),
.target(
    name: "Core",
    dependencies: ["MuxLogging", .product(name: "Logging", package: "swift-log")],
    // ...
),
.target(
    name: "TmuxKit",
    dependencies: ["Core", "MuxLogging", .product(name: "Logging", package: "swift-log")],
    // ...
),
```

- [ ] **Step 2: Logger+muxbar.swift 작성**

Create `Sources/MuxLogging/Logger+muxbar.swift`:
```swift
import Foundation
import Logging

public enum MuxLogging {
    private static let isBootstrapped = NSLock()
    nonisolated(unsafe) private static var didBootstrap = false

    public static func bootstrap() {
        isBootstrapped.lock()
        defer { isBootstrapped.unlock() }
        guard !didBootstrap else { return }

        LoggingSystem.bootstrap { label in
            var handler = StreamLogHandler.standardError(label: label)
            #if DEBUG
            handler.logLevel = .debug
            #else
            handler.logLevel = .info
            #endif
            return handler
        }
        didBootstrap = true
    }

    public static func logger(_ label: String) -> Logger {
        Logger(label: "muxbar.\(label)")
    }
}
```

- [ ] **Step 3: MuxBarApp 에서 bootstrap 호출**

Edit `Sources/MuxBarApp/MuxBarApp.swift`:
```swift
import SwiftUI
import MuxLogging

@main
struct MuxBarApp: App {
    init() {
        MuxLogging.bootstrap()
        MuxLogging.logger("app").info("muxbar 기동")
    }

    var body: some Scene {
        MenuBarExtra("muxbar", systemImage: "terminal") {
            Text("muxbar 기동됨")
                .padding()
            Divider()
            Button("Quit") { NSApplication.shared.terminate(nil) }
                .keyboardShortcut("q")
        }
        .menuBarExtraStyle(.window)
    }
}
```

- [ ] **Step 4: 빌드 확인**

Run: `swift build`
Expected: `Build complete!`

- [ ] **Step 5: 실행 로그 확인**

Run: `swift run muxbar 2>&1 | head -5`
Expected: `info muxbar.app : muxbar 기동` 라인 포함 (stderr 로 출력).
종료: Ctrl-C 또는 `pkill -f muxbar`.

- [ ] **Step 6: Commit**

```bash
git add Package.swift Sources/MuxLogging Sources/MuxBarApp/MuxBarApp.swift
git commit -m "feat: swift-log 기반 로깅 부트스트랩"
```

---

## Task 3: Core 모델 — TmuxSession

**Files:**
- Create: `Sources/Core/Model/TmuxSession.swift`
- Create: `Tests/CoreTests/ModelEqualityTests.swift`

- [ ] **Step 1: 실패 테스트 작성**

Create `Tests/CoreTests/ModelEqualityTests.swift`:
```swift
import XCTest
@testable import Core

final class ModelEqualityTests: XCTestCase {
    func test_tmuxSession_equality_byAllFields() {
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        let a = TmuxSession(
            id: "dev",
            isAttached: true,
            windowCount: 3,
            createdAt: now,
            lastActivityAt: now,
            workingDirectory: "/Users/kgd/msa"
        )
        let b = TmuxSession(
            id: "dev",
            isAttached: true,
            windowCount: 3,
            createdAt: now,
            lastActivityAt: now,
            workingDirectory: "/Users/kgd/msa"
        )
        XCTAssertEqual(a, b)
    }

    func test_tmuxSession_isInternal_prefixUnderscoreMuxbar() {
        let internalSession = TmuxSession(
            id: "_muxbar-ctl", isAttached: false, windowCount: 1,
            createdAt: .now, lastActivityAt: .now, workingDirectory: nil
        )
        XCTAssertTrue(internalSession.isInternal)

        let userSession = TmuxSession(
            id: "dev", isAttached: false, windowCount: 1,
            createdAt: .now, lastActivityAt: .now, workingDirectory: nil
        )
        XCTAssertFalse(userSession.isInternal)
    }
}
```

- [ ] **Step 2: 테스트 실행 → 실패 확인**

Run: `swift test --filter ModelEqualityTests`
Expected: Compile error — `TmuxSession` 미정의.

- [ ] **Step 3: TmuxSession 구현**

Create `Sources/Core/Model/TmuxSession.swift`:
```swift
import Foundation

public struct TmuxSession: Identifiable, Sendable, Equatable, Hashable {
    public let id: String
    public let isAttached: Bool
    public let windowCount: Int
    public let createdAt: Date
    public let lastActivityAt: Date
    public let workingDirectory: String?

    public init(
        id: String,
        isAttached: Bool,
        windowCount: Int,
        createdAt: Date,
        lastActivityAt: Date,
        workingDirectory: String?
    ) {
        self.id = id
        self.isAttached = isAttached
        self.windowCount = windowCount
        self.createdAt = createdAt
        self.lastActivityAt = lastActivityAt
        self.workingDirectory = workingDirectory
    }

    public var isInternal: Bool {
        id.hasPrefix("_muxbar-")
    }
}
```

- [ ] **Step 4: 테스트 통과 확인**

Run: `swift test --filter ModelEqualityTests`
Expected: `Test Suite 'ModelEqualityTests' passed`. 2 tests passed.

- [ ] **Step 5: Commit**

```bash
git add Sources/Core/Model/TmuxSession.swift Tests/CoreTests/ModelEqualityTests.swift
git commit -m "feat: TmuxSession 모델 + isInternal 판정"
```

---

## Task 4: Core 모델 — TmuxWindow, TmuxPane

**Files:**
- Create: `Sources/Core/Model/TmuxWindow.swift`
- Create: `Sources/Core/Model/TmuxPane.swift`
- Modify: `Tests/CoreTests/ModelEqualityTests.swift`

- [ ] **Step 1: 실패 테스트 추가**

Append to `Tests/CoreTests/ModelEqualityTests.swift`:
```swift
    func test_tmuxWindow_equality() {
        let a = TmuxWindow(id: "@1", sessionId: "dev", index: 0, name: "edit", paneCount: 2, isActive: true)
        let b = TmuxWindow(id: "@1", sessionId: "dev", index: 0, name: "edit", paneCount: 2, isActive: true)
        XCTAssertEqual(a, b)
    }

    func test_tmuxPane_equality() {
        let a = TmuxPane(id: "%5", windowId: "@1", command: "nvim", pid: 1234, isActive: true)
        let b = TmuxPane(id: "%5", windowId: "@1", command: "nvim", pid: 1234, isActive: true)
        XCTAssertEqual(a, b)
    }
```

- [ ] **Step 2: 테스트 실행 → 실패 확인**

Run: `swift test --filter ModelEqualityTests`
Expected: Compile error — `TmuxWindow`, `TmuxPane` 미정의.

- [ ] **Step 3: TmuxWindow 구현**

Create `Sources/Core/Model/TmuxWindow.swift`:
```swift
import Foundation

public struct TmuxWindow: Identifiable, Sendable, Equatable, Hashable {
    public let id: String          // "@<n>"
    public let sessionId: String
    public let index: Int
    public let name: String
    public let paneCount: Int
    public let isActive: Bool

    public init(id: String, sessionId: String, index: Int, name: String, paneCount: Int, isActive: Bool) {
        self.id = id
        self.sessionId = sessionId
        self.index = index
        self.name = name
        self.paneCount = paneCount
        self.isActive = isActive
    }
}
```

- [ ] **Step 4: TmuxPane 구현**

Create `Sources/Core/Model/TmuxPane.swift`:
```swift
import Foundation

public struct TmuxPane: Identifiable, Sendable, Equatable, Hashable {
    public let id: String          // "%<n>"
    public let windowId: String
    public let command: String?
    public let pid: pid_t?
    public let isActive: Bool

    public init(id: String, windowId: String, command: String?, pid: pid_t?, isActive: Bool) {
        self.id = id
        self.windowId = windowId
        self.command = command
        self.pid = pid
        self.isActive = isActive
    }
}
```

- [ ] **Step 5: 테스트 통과 확인**

Run: `swift test --filter ModelEqualityTests`
Expected: 4 tests passed.

- [ ] **Step 6: Commit**

```bash
git add Sources/Core/Model/TmuxWindow.swift Sources/Core/Model/TmuxPane.swift Tests/CoreTests/ModelEqualityTests.swift
git commit -m "feat: TmuxWindow, TmuxPane 모델"
```

---

## Task 5: CaffeinateFlags 모델

**Files:**
- Create: `Sources/Core/Model/CaffeinateFlags.swift`
- Create: `Tests/CoreTests/CaffeinateFlagsTests.swift`

- [ ] **Step 1: 실패 테스트 작성**

Create `Tests/CoreTests/CaffeinateFlagsTests.swift`:
```swift
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
```

- [ ] **Step 2: 테스트 실행 → 실패 확인**

Run: `swift test --filter CaffeinateFlagsTests`
Expected: Compile error — `CaffeinateFlags` 미정의.

- [ ] **Step 3: CaffeinateFlags 구현**

Create `Sources/Core/Model/CaffeinateFlags.swift`:
```swift
import Foundation

public struct CaffeinateFlags: Sendable, Equatable, Hashable, Codable {
    public var preventDisplaySleep: Bool      // -d
    public var preventIdleSleep: Bool         // -i
    public var preventDiskIdleSleep: Bool     // -m
    public var preventSystemSleep: Bool       // -s
    public var preventUserIdleSleep: Bool     // -u

    public init(d: Bool, i: Bool, m: Bool, s: Bool, u: Bool) {
        self.preventDisplaySleep = d
        self.preventIdleSleep = i
        self.preventDiskIdleSleep = m
        self.preventSystemSleep = s
        self.preventUserIdleSleep = u
    }

    public static let `default` = CaffeinateFlags(d: true, i: true, m: true, s: true, u: false)

    public var cliArgs: String {
        var chars = ""
        if preventDisplaySleep   { chars += "d" }
        if preventIdleSleep      { chars += "i" }
        if preventDiskIdleSleep  { chars += "m" }
        if preventSystemSleep    { chars += "s" }
        if preventUserIdleSleep  { chars += "u" }
        return chars.isEmpty ? "" : "-\(chars)"
    }

    public var isValid: Bool {
        preventDisplaySleep || preventIdleSleep || preventDiskIdleSleep
            || preventSystemSleep || preventUserIdleSleep
    }
}
```

- [ ] **Step 4: 테스트 통과 확인**

Run: `swift test --filter CaffeinateFlagsTests`
Expected: 5 tests passed.

- [ ] **Step 5: Commit**

```bash
git add Sources/Core/Model/CaffeinateFlags.swift Tests/CoreTests/CaffeinateFlagsTests.swift
git commit -m "feat: CaffeinateFlags 모델 + cliArgs 변환"
```

---

## Task 6: TmuxKit — Octal unescape

**Files:**
- Create: `Sources/TmuxKit/OctalUnescape.swift`
- Create: `Tests/TmuxKitTests/OctalUnescapeTests.swift`

tmux `%output` 은 `<ASCII 32` 및 `\` 을 `\ooo` (3자리 8진수) 로 이스케이프함. 이를 복원하는 유틸.

- [ ] **Step 1: 실패 테스트 작성**

Create `Tests/TmuxKitTests/OctalUnescapeTests.swift`:
```swift
import XCTest
@testable import TmuxKit

final class OctalUnescapeTests: XCTestCase {
    func test_plainAscii_unchanged() {
        XCTAssertEqual(OctalUnescape.decode("hello world"), "hello world".data(using: .utf8)!)
    }

    func test_singleEscape_newline() {
        // \012 = \n = 0x0A
        let result = OctalUnescape.decode("line1\\012line2")
        XCTAssertEqual(result, "line1\nline2".data(using: .utf8)!)
    }

    func test_escapedBackslash() {
        // \134 = \ = 0x5C
        let result = OctalUnescape.decode("a\\134b")
        XCTAssertEqual(result, "a\\b".data(using: .utf8)!)
    }

    func test_tab() {
        // \011 = \t
        let result = OctalUnescape.decode("col1\\011col2")
        XCTAssertEqual(result, "col1\tcol2".data(using: .utf8)!)
    }

    func test_escapeAtEnd() {
        let result = OctalUnescape.decode("trailing\\015")
        XCTAssertEqual(result, "trailing\r".data(using: .utf8)!)
    }

    func test_malformedEscape_passthrough() {
        // less than 3 digits or non-octal → keep as-is
        let result = OctalUnescape.decode("bad\\9")
        XCTAssertEqual(result, "bad\\9".data(using: .utf8)!)
    }

    func test_multipleEscapes_inRow() {
        let result = OctalUnescape.decode("\\033\\133")
        // \033 = ESC (0x1B), \133 = [ (0x5B)
        XCTAssertEqual(result, Data([0x1B, 0x5B]))
    }
}
```

- [ ] **Step 2: 테스트 실행 → 실패 확인**

Run: `swift test --filter OctalUnescapeTests`
Expected: Compile error — `OctalUnescape` 미정의.

- [ ] **Step 3: OctalUnescape 구현**

Create `Sources/TmuxKit/OctalUnescape.swift`:
```swift
import Foundation

public enum OctalUnescape {
    /// tmux control mode `%output` payload 를 디코딩.
    /// `\ooo` (3자리 8진수) 를 해당 바이트로 치환. 형식 불량이면 그대로 둠.
    public static func decode(_ input: String) -> Data {
        var output = Data()
        output.reserveCapacity(input.utf8.count)

        let bytes = Array(input.utf8)
        var i = 0
        while i < bytes.count {
            let b = bytes[i]
            if b == 0x5C /* backslash */,
               i + 3 < bytes.count,
               let d1 = octalDigit(bytes[i + 1]),
               let d2 = octalDigit(bytes[i + 2]),
               let d3 = octalDigit(bytes[i + 3])
            {
                let value = UInt8(d1 * 64 + d2 * 8 + d3)
                output.append(value)
                i += 4
            } else {
                output.append(b)
                i += 1
            }
        }
        return output
    }

    private static func octalDigit(_ b: UInt8) -> Int? {
        guard b >= 0x30, b <= 0x37 else { return nil }
        return Int(b - 0x30)
    }
}
```

- [ ] **Step 4: 테스트 통과 확인**

Run: `swift test --filter OctalUnescapeTests`
Expected: 7 tests passed.

- [ ] **Step 5: Commit**

```bash
git add Sources/TmuxKit/OctalUnescape.swift Tests/TmuxKitTests/OctalUnescapeTests.swift
git commit -m "feat(TmuxKit): %output octal escape 디코더"
```

---

## Task 7: TmuxKit — ControlEvent enum

**Files:**
- Create: `Sources/TmuxKit/ControlEvent.swift`

이벤트 데이터 구조만 정의. 파서는 다음 Task.

- [ ] **Step 1: ControlEvent.swift 작성**

Create `Sources/TmuxKit/ControlEvent.swift`:
```swift
import Foundation

public enum ControlEvent: Sendable, Equatable {
    case commandBegin(time: Int, cmdId: Int, flags: Int)
    case commandEnd(time: Int, cmdId: Int, flags: Int)
    case commandError(time: Int, cmdId: Int, flags: Int)

    /// Guard 라인 사이의 응답 본문 (파서가 하나로 합쳐서 전달)
    case commandOutput(cmdId: Int, body: String)

    case paneOutput(paneId: String, data: Data)

    case sessionChanged(sessionId: String, name: String)
    case sessionRenamed(sessionId: String, name: String)
    case sessionsChanged

    case windowAdd(windowId: String)
    case windowClose(windowId: String)
    case windowRenamed(windowId: String, name: String)
    case windowPaneChanged(windowId: String, paneId: String)

    case paneModeChanged(paneId: String)

    case pause(paneId: String)
    case continueFlow(paneId: String)

    case exit

    /// 알 수 없는/미지원 라인 (로깅용)
    case unknown(line: String)
}
```

- [ ] **Step 2: 빌드 확인**

Run: `swift build --target TmuxKit`
Expected: `Build complete!`

- [ ] **Step 3: Commit**

```bash
git add Sources/TmuxKit/ControlEvent.swift
git commit -m "feat(TmuxKit): ControlEvent enum 정의"
```

---

## Task 8: TmuxKit — ControlProtocol 파서 (guard 라인)

**Files:**
- Create: `Sources/TmuxKit/ControlProtocol.swift`
- Create: `Tests/TmuxKitTests/ControlProtocolTests.swift`

- [ ] **Step 1: 실패 테스트 작성 (guard 라인)**

Create `Tests/TmuxKitTests/ControlProtocolTests.swift`:
```swift
import XCTest
@testable import TmuxKit

final class ControlProtocolTests: XCTestCase {
    func test_beginLine() {
        let parser = ControlProtocol()
        let events = parser.feed("%begin 1700000000 42 1\n")
        XCTAssertEqual(events, [.commandBegin(time: 1_700_000_000, cmdId: 42, flags: 1)])
    }

    func test_endLine_withBody_emitsOutputThenEnd() {
        let parser = ControlProtocol()
        let input = """
        %begin 1700000000 42 1
        hello
        world
        %end 1700000000 42 1

        """
        let events = parser.feed(input)
        XCTAssertEqual(events.count, 3)
        XCTAssertEqual(events[0], .commandBegin(time: 1_700_000_000, cmdId: 42, flags: 1))
        XCTAssertEqual(events[1], .commandOutput(cmdId: 42, body: "hello\nworld"))
        XCTAssertEqual(events[2], .commandEnd(time: 1_700_000_000, cmdId: 42, flags: 1))
    }

    func test_errorLine_withBody() {
        let parser = ControlProtocol()
        let input = """
        %begin 1700000000 43 1
        unknown command
        %error 1700000000 43 1

        """
        let events = parser.feed(input)
        XCTAssertEqual(events.count, 3)
        XCTAssertEqual(events[0], .commandBegin(time: 1_700_000_000, cmdId: 43, flags: 1))
        XCTAssertEqual(events[1], .commandOutput(cmdId: 43, body: "unknown command"))
        XCTAssertEqual(events[2], .commandError(time: 1_700_000_000, cmdId: 43, flags: 1))
    }

    func test_partialBuffer_crossesFeeds() {
        let parser = ControlProtocol()
        let first = parser.feed("%begin 1700000000 42 ")
        XCTAssertEqual(first, [])
        let second = parser.feed("1\n")
        XCTAssertEqual(second, [.commandBegin(time: 1_700_000_000, cmdId: 42, flags: 1)])
    }
}
```

- [ ] **Step 2: 테스트 실행 → 실패 확인**

Run: `swift test --filter ControlProtocolTests`
Expected: Compile error — `ControlProtocol` 미정의.

- [ ] **Step 3: ControlProtocol (guard 라인 + 버퍼링) 구현**

Create `Sources/TmuxKit/ControlProtocol.swift`:
```swift
import Foundation

public final class ControlProtocol {
    private var buffer = ""

    // %begin 직후부터 %end/%error 전까지의 본문 누적
    private var inCommand: Bool = false
    private var commandCmdId: Int = -1
    private var commandBody: [String] = []

    public init() {}

    /// 바이트 스트림을 라인 단위로 파싱. 남은 부분 라인은 내부 버퍼에 유지.
    public func feed(_ chunk: String) -> [ControlEvent] {
        buffer += chunk
        var events: [ControlEvent] = []

        while let newlineRange = buffer.range(of: "\n") {
            let line = String(buffer[buffer.startIndex..<newlineRange.lowerBound])
            buffer.removeSubrange(buffer.startIndex...newlineRange.lowerBound)
            events.append(contentsOf: parseLine(line))
        }

        return events
    }

    private func parseLine(_ line: String) -> [ControlEvent] {
        if line.isEmpty {
            return inCommand ? [] : []
        }

        // guard lines
        if line.hasPrefix("%begin ") {
            return handleBegin(line)
        } else if line.hasPrefix("%end ") {
            return handleEnd(line, isError: false)
        } else if line.hasPrefix("%error ") {
            return handleEnd(line, isError: true)
        }

        // 커맨드 응답 본문 누적
        if inCommand {
            commandBody.append(line)
            return []
        }

        // 비동기 이벤트 (다음 Task 에서 확장)
        return parseAsyncEvent(line)
    }

    private func handleBegin(_ line: String) -> [ControlEvent] {
        guard let (time, cmdId, flags) = parseGuardArgs(line, prefix: "%begin ") else {
            return [.unknown(line: line)]
        }
        inCommand = true
        commandCmdId = cmdId
        commandBody = []
        return [.commandBegin(time: time, cmdId: cmdId, flags: flags)]
    }

    private func handleEnd(_ line: String, isError: Bool) -> [ControlEvent] {
        let prefix = isError ? "%error " : "%end "
        guard let (time, cmdId, flags) = parseGuardArgs(line, prefix: prefix) else {
            return [.unknown(line: line)]
        }
        var events: [ControlEvent] = []
        if !commandBody.isEmpty {
            let body = commandBody.joined(separator: "\n")
            events.append(.commandOutput(cmdId: cmdId, body: body))
        }
        events.append(isError
            ? .commandError(time: time, cmdId: cmdId, flags: flags)
            : .commandEnd(time: time, cmdId: cmdId, flags: flags))
        inCommand = false
        commandBody = []
        return events
    }

    private func parseGuardArgs(_ line: String, prefix: String) -> (Int, Int, Int)? {
        let rest = line.dropFirst(prefix.count)
        let parts = rest.split(separator: " ", maxSplits: 3).map(String.init)
        guard parts.count >= 3,
              let t = Int(parts[0]),
              let c = Int(parts[1]),
              let f = Int(parts[2]) else { return nil }
        return (t, c, f)
    }

    // 다음 Task 에서 구현
    fileprivate func parseAsyncEvent(_ line: String) -> [ControlEvent] {
        [.unknown(line: line)]
    }
}
```

- [ ] **Step 4: 테스트 통과 확인**

Run: `swift test --filter ControlProtocolTests`
Expected: 4 tests passed.

- [ ] **Step 5: Commit**

```bash
git add Sources/TmuxKit/ControlProtocol.swift Tests/TmuxKitTests/ControlProtocolTests.swift
git commit -m "feat(TmuxKit): guard line (%begin/%end/%error) 파서 + 라인 버퍼링"
```

---

## Task 9: TmuxKit — ControlProtocol 비동기 이벤트 파싱

**Files:**
- Modify: `Sources/TmuxKit/ControlProtocol.swift`
- Modify: `Tests/TmuxKitTests/ControlProtocolTests.swift`

- [ ] **Step 1: 비동기 이벤트 테스트 추가**

Append to `Tests/TmuxKitTests/ControlProtocolTests.swift`:
```swift
    func test_paneOutput_decoded() {
        let parser = ControlProtocol()
        let events = parser.feed("%output %5 hello\\012world\n")
        guard case .paneOutput(let paneId, let data) = events.first else {
            return XCTFail("expected paneOutput, got \(events)")
        }
        XCTAssertEqual(paneId, "%5")
        XCTAssertEqual(String(data: data, encoding: .utf8), "hello\nworld")
    }

    func test_sessionsChanged() {
        let parser = ControlProtocol()
        XCTAssertEqual(parser.feed("%sessions-changed\n"), [.sessionsChanged])
    }

    func test_sessionChanged() {
        let parser = ControlProtocol()
        XCTAssertEqual(
            parser.feed("%session-changed $2 dev\n"),
            [.sessionChanged(sessionId: "$2", name: "dev")]
        )
    }

    func test_sessionRenamed() {
        let parser = ControlProtocol()
        XCTAssertEqual(
            parser.feed("%session-renamed $2 newname\n"),
            [.sessionRenamed(sessionId: "$2", name: "newname")]
        )
    }

    func test_windowAddClose() {
        let parser = ControlProtocol()
        XCTAssertEqual(parser.feed("%window-add @7\n"), [.windowAdd(windowId: "@7")])
        XCTAssertEqual(parser.feed("%window-close @7\n"), [.windowClose(windowId: "@7")])
    }

    func test_windowRenamed() {
        let parser = ControlProtocol()
        XCTAssertEqual(
            parser.feed("%window-renamed @7 logs\n"),
            [.windowRenamed(windowId: "@7", name: "logs")]
        )
    }

    func test_paneModeChanged() {
        let parser = ControlProtocol()
        XCTAssertEqual(
            parser.feed("%pane-mode-changed %5\n"),
            [.paneModeChanged(paneId: "%5")]
        )
    }

    func test_pauseContinue() {
        let parser = ControlProtocol()
        XCTAssertEqual(parser.feed("%pause %5\n"), [.pause(paneId: "%5")])
        XCTAssertEqual(parser.feed("%continue %5\n"), [.continueFlow(paneId: "%5")])
    }

    func test_exit() {
        let parser = ControlProtocol()
        XCTAssertEqual(parser.feed("%exit\n"), [.exit])
    }

    func test_unknown_pctLine() {
        let parser = ControlProtocol()
        let events = parser.feed("%future-event foo bar\n")
        XCTAssertEqual(events, [.unknown(line: "%future-event foo bar")])
    }
```

- [ ] **Step 2: 테스트 실행 → 실패 확인**

Run: `swift test --filter ControlProtocolTests`
Expected: 새 10개 테스트 실패 (`paneOutput`, `sessionsChanged` 등이 `.unknown` 으로 반환됨).

- [ ] **Step 3: parseAsyncEvent 구현**

Replace the `parseAsyncEvent` body in `Sources/TmuxKit/ControlProtocol.swift`:
```swift
    fileprivate func parseAsyncEvent(_ line: String) -> [ControlEvent] {
        guard line.hasPrefix("%") else { return [.unknown(line: line)] }

        // 공백으로 토큰 분리
        let firstSpace = line.firstIndex(of: " ")
        let keyword = firstSpace.map { String(line[line.startIndex..<$0]) } ?? line
        let rest: String = firstSpace.map { String(line[line.index(after: $0)...]) } ?? ""

        switch keyword {
        case "%output":
            // "%5 hello\\012world"
            let parts = rest.split(separator: " ", maxSplits: 1).map(String.init)
            guard parts.count == 2 else { return [.unknown(line: line)] }
            return [.paneOutput(paneId: parts[0], data: OctalUnescape.decode(parts[1]))]

        case "%sessions-changed":
            return [.sessionsChanged]

        case "%session-changed":
            let parts = rest.split(separator: " ", maxSplits: 1).map(String.init)
            guard parts.count == 2 else { return [.unknown(line: line)] }
            return [.sessionChanged(sessionId: parts[0], name: parts[1])]

        case "%session-renamed":
            let parts = rest.split(separator: " ", maxSplits: 1).map(String.init)
            guard parts.count == 2 else { return [.unknown(line: line)] }
            return [.sessionRenamed(sessionId: parts[0], name: parts[1])]

        case "%window-add":
            return [.windowAdd(windowId: rest)]

        case "%window-close":
            return [.windowClose(windowId: rest)]

        case "%window-renamed":
            let parts = rest.split(separator: " ", maxSplits: 1).map(String.init)
            guard parts.count == 2 else { return [.unknown(line: line)] }
            return [.windowRenamed(windowId: parts[0], name: parts[1])]

        case "%window-pane-changed":
            let parts = rest.split(separator: " ", maxSplits: 1).map(String.init)
            guard parts.count == 2 else { return [.unknown(line: line)] }
            return [.windowPaneChanged(windowId: parts[0], paneId: parts[1])]

        case "%pane-mode-changed":
            return [.paneModeChanged(paneId: rest)]

        case "%pause":
            return [.pause(paneId: rest)]

        case "%continue":
            return [.continueFlow(paneId: rest)]

        case "%exit":
            return [.exit]

        default:
            return [.unknown(line: line)]
        }
    }
```

- [ ] **Step 4: 테스트 통과 확인**

Run: `swift test --filter ControlProtocolTests`
Expected: 총 14 tests passed.

- [ ] **Step 5: Commit**

```bash
git add Sources/TmuxKit/ControlProtocol.swift Tests/TmuxKitTests/ControlProtocolTests.swift
git commit -m "feat(TmuxKit): 비동기 이벤트 파서 (%output, session/window 이벤트 등)"
```

---

## Task 10: TmuxKit — TmuxPath 바이너리 해석

**Files:**
- Create: `Sources/TmuxKit/TmuxPath.swift`
- Create: `Tests/TmuxKitTests/TmuxPathTests.swift`

- [ ] **Step 1: 실패 테스트 작성**

Create `Tests/TmuxKitTests/TmuxPathTests.swift`:
```swift
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
```

- [ ] **Step 2: 테스트 실행 → 실패 확인**

Run: `swift test --filter TmuxPathTests`
Expected: Compile error — `TmuxPath` 미정의.

- [ ] **Step 3: TmuxPath 구현**

Create `Sources/TmuxKit/TmuxPath.swift`:
```swift
import Foundation

public enum TmuxPath {
    public static let defaultCandidates: [String] = [
        "/opt/homebrew/bin/tmux",     // Apple Silicon Homebrew
        "/usr/local/bin/tmux",        // Intel Homebrew
        "/usr/bin/tmux",              // 시스템 기본 (없을 수도)
        "/opt/local/bin/tmux",        // MacPorts
    ]

    public static func resolve(from candidates: [String] = defaultCandidates) -> String? {
        let fm = FileManager.default
        return candidates.first { fm.isExecutableFile(atPath: $0) || fm.fileExists(atPath: $0) }
    }
}
```

- [ ] **Step 4: 테스트 통과 확인**

Run: `swift test --filter TmuxPathTests`
Expected: 3 tests passed.

- [ ] **Step 5: Commit**

```bash
git add Sources/TmuxKit/TmuxPath.swift Tests/TmuxKitTests/TmuxPathTests.swift
git commit -m "feat(TmuxKit): tmux 바이너리 경로 해석"
```

---

## Task 11: TmuxKit — TmuxCommand 타입 세이프 래퍼

**Files:**
- Create: `Sources/TmuxKit/Commands.swift`
- Create: `Tests/TmuxKitTests/CommandsTests.swift`

- [ ] **Step 1: 실패 테스트 작성**

Create `Tests/TmuxKitTests/CommandsTests.swift`:
```swift
import XCTest
@testable import TmuxKit

final class CommandsTests: XCTestCase {
    func test_listSessions_cliString() {
        XCTAssertEqual(
            TmuxCommand.listSessions.cliString,
            #"list-sessions -F "#{session_name}\t#{session_attached}\t#{session_windows}\t#{session_created}\t#{session_activity}\t#{session_path}""#
        )
    }

    func test_killSession_quotesName() {
        XCTAssertEqual(
            TmuxCommand.killSession(name: "dev").cliString,
            #"kill-session -t "dev""#
        )
    }

    func test_killSession_escapesQuotes() {
        XCTAssertEqual(
            TmuxCommand.killSession(name: "a\"b").cliString,
            #"kill-session -t "a\"b""#
        )
    }

    func test_newSession_detached() {
        XCTAssertEqual(
            TmuxCommand.newSession(name: "dev", command: nil).cliString,
            #"new-session -d -s "dev""#
        )
    }

    func test_newSession_withCommand() {
        XCTAssertEqual(
            TmuxCommand.newSession(name: "awake", command: "caffeinate -dims").cliString,
            #"new-session -d -s "awake" "caffeinate -dims""#
        )
    }

    func test_hasSession() {
        XCTAssertEqual(
            TmuxCommand.hasSession(name: "dev").cliString,
            #"has-session -t "dev""#
        )
    }

    func test_capturePane() {
        XCTAssertEqual(
            TmuxCommand.capturePane(target: "dev", lines: 200, withEscapes: true).cliString,
            #"capture-pane -pt "dev" -J -e -S -200"#
        )
    }
}
```

- [ ] **Step 2: 테스트 실행 → 실패 확인**

Run: `swift test --filter CommandsTests`
Expected: Compile error — `TmuxCommand` 미정의.

- [ ] **Step 3: TmuxCommand 구현**

Create `Sources/TmuxKit/Commands.swift`:
```swift
import Foundation

public enum TmuxCommand: Sendable, Equatable {
    case listSessions
    case listWindows(session: String)
    case killSession(name: String)
    case newSession(name: String, command: String?)
    case hasSession(name: String)
    case capturePane(target: String, lines: Int, withEscapes: Bool)
    case renameSession(from: String, to: String)

    public var cliString: String {
        switch self {
        case .listSessions:
            let fields = #"#{session_name}\t#{session_attached}\t#{session_windows}\t#{session_created}\t#{session_activity}\t#{session_path}"#
            return #"list-sessions -F "\#(fields)""#

        case .listWindows(let session):
            let fields = #"#{window_id}\t#{window_index}\t#{window_name}\t#{window_panes}\t#{window_active}"#
            return #"list-windows -t \#(quote(session)) -F "\#(fields)""#

        case .killSession(let name):
            return #"kill-session -t \#(quote(name))"#

        case .newSession(let name, let command):
            if let command {
                return #"new-session -d -s \#(quote(name)) \#(quote(command))"#
            } else {
                return #"new-session -d -s \#(quote(name))"#
            }

        case .hasSession(let name):
            return #"has-session -t \#(quote(name))"#

        case .capturePane(let target, let lines, let withEscapes):
            let e = withEscapes ? " -e" : ""
            return #"capture-pane -pt \#(quote(target)) -J\#(e) -S -\#(lines)"#

        case .renameSession(let from, let to):
            return #"rename-session -t \#(quote(from)) \#(quote(to))"#
        }
    }

    /// 큰따옴표로 감싸고 내부 `"` 만 이스케이프.
    private func quote(_ s: String) -> String {
        let escaped = s.replacingOccurrences(of: "\"", with: "\\\"")
        return "\"\(escaped)\""
    }
}
```

- [ ] **Step 4: 테스트 통과 확인**

Run: `swift test --filter CommandsTests`
Expected: 7 tests passed.

- [ ] **Step 5: Commit**

```bash
git add Sources/TmuxKit/Commands.swift Tests/TmuxKitTests/CommandsTests.swift
git commit -m "feat(TmuxKit): TmuxCommand 타입 세이프 래퍼"
```

---

## Task 12: TmuxKit — ControlClient 기본 스켈레톤

**Files:**
- Create: `Sources/TmuxKit/ControlClient.swift`

외부 인터페이스와 Process 관리 골격만. Bootstrap + 명령 응답은 Task 13, 14.

- [ ] **Step 1: ControlClient.swift 기본 골격 작성**

Create `Sources/TmuxKit/ControlClient.swift`:
```swift
import Foundation
import Logging
import MuxLogging
import Core

public actor ControlClient {
    public enum ClientError: Error, Equatable {
        case tmuxBinaryNotFound
        case processFailedToStart(String)
        case notConnected
        case commandTimeout(cmdId: Int)
        case serverExited
    }

    private let logger = MuxLogging.logger("TmuxKit.ControlClient")
    private let tmuxPath: String
    private var process: Process?
    private var stdinPipe: Pipe?
    private var stdoutPipe: Pipe?
    private var stderrPipe: Pipe?
    private let protocolParser = ControlProtocol()

    private var nextCmdId: Int = 0
    private var pendingCommands: [Int: CheckedContinuation<String, Error>] = [:]

    private var eventStreamContinuation: AsyncStream<ControlEvent>.Continuation?
    public nonisolated let events: AsyncStream<ControlEvent>

    public init(tmuxPath: String? = TmuxPath.resolve()) throws {
        guard let path = tmuxPath else { throw ClientError.tmuxBinaryNotFound }
        self.tmuxPath = path

        // AsyncStream 의 빌더 클로저는 동기 실행되므로 init 리턴 전에 continuation 확보 완료.
        var localContinuation: AsyncStream<ControlEvent>.Continuation!
        self.events = AsyncStream<ControlEvent> { continuation in
            localContinuation = continuation
        }
        self.eventStreamContinuation = localContinuation
    }

    public func connectionState() -> ConnectionState {
        process?.isRunning == true ? .connected : .disconnected
    }

    public func disconnect() {
        process?.terminate()
        process = nil
        stdinPipe = nil
        stdoutPipe = nil
        stderrPipe = nil

        for (_, cont) in pendingCommands {
            cont.resume(throwing: ClientError.serverExited)
        }
        pendingCommands.removeAll()

        eventStreamContinuation?.finish()
        logger.info("ControlClient disconnected")
    }
}
```

- [ ] **Step 2: 빌드 확인**

Run: `swift build --target TmuxKit`
Expected: `Build complete!`

- [ ] **Step 3: Commit**

```bash
git add Sources/TmuxKit/ControlClient.swift
git commit -m "feat(TmuxKit): ControlClient 골격 (Process/Pipe 필드, 이벤트 스트림)"
```

---

## Task 13: TmuxKit — ControlClient bootstrap + stdout pump

**Files:**
- Modify: `Sources/TmuxKit/ControlClient.swift`

- [ ] **Step 1: bootstrap/pump 메서드 추가**

Append methods inside the `ControlClient` actor in `Sources/TmuxKit/ControlClient.swift`:
```swift
    public func bootstrap() async throws {
        try ensureServerRunning()
        try spawnControlProcess()
        startStdoutPump()
        logger.info("ControlClient bootstrapped")
    }

    private func ensureServerRunning() throws {
        // 서버 없으면 detached 관리 세션으로 서버 기동
        let check = Process()
        check.executableURL = URL(fileURLWithPath: tmuxPath)
        check.arguments = ["has-session", "-t", "_muxbar-ctl"]
        check.standardError = Pipe()
        check.standardOutput = Pipe()
        do {
            try check.run()
            check.waitUntilExit()
        } catch {
            throw ClientError.processFailedToStart("tmux has-session 실패: \(error.localizedDescription)")
        }

        if check.terminationStatus != 0 {
            // _muxbar-ctl 없음 → 생성 (서버도 같이 뜸)
            let make = Process()
            make.executableURL = URL(fileURLWithPath: tmuxPath)
            make.arguments = ["new-session", "-d", "-s", "_muxbar-ctl"]
            make.standardError = Pipe()
            make.standardOutput = Pipe()
            try make.run()
            make.waitUntilExit()
            guard make.terminationStatus == 0 else {
                throw ClientError.processFailedToStart("tmux new-session _muxbar-ctl 실패 (exit=\(make.terminationStatus))")
            }
        }
    }

    private func spawnControlProcess() throws {
        let p = Process()
        let inPipe = Pipe()
        let outPipe = Pipe()
        let errPipe = Pipe()

        p.executableURL = URL(fileURLWithPath: tmuxPath)
        p.arguments = ["-C", "attach", "-t", "_muxbar-ctl"]
        p.standardInput = inPipe
        p.standardOutput = outPipe
        p.standardError = errPipe

        p.terminationHandler = { [weak self] proc in
            Task { [weak self] in
                await self?.handleProcessTermination(status: proc.terminationStatus)
            }
        }

        do {
            try p.run()
        } catch {
            throw ClientError.processFailedToStart("tmux -C 실행 실패: \(error.localizedDescription)")
        }

        self.process = p
        self.stdinPipe = inPipe
        self.stdoutPipe = outPipe
        self.stderrPipe = errPipe
    }

    private func startStdoutPump() {
        guard let outPipe = stdoutPipe else { return }
        let handle = outPipe.fileHandleForReading

        handle.readabilityHandler = { [weak self] fh in
            let data = fh.availableData
            guard !data.isEmpty else { return }
            guard let chunk = String(data: data, encoding: .utf8) else { return }
            Task { [weak self] in
                await self?.ingest(chunk)
            }
        }
    }

    private func ingest(_ chunk: String) {
        let events = protocolParser.feed(chunk)
        for event in events {
            handleEvent(event)
        }
    }

    private func handleEvent(_ event: ControlEvent) {
        switch event {
        case .commandOutput(let cmdId, let body):
            // pending 명령의 응답으로 보관. 최종 end/error 에서 resolve.
            pendingBodies[cmdId] = body
        case .commandEnd(_, let cmdId, _):
            if let body = pendingBodies.removeValue(forKey: cmdId) ?? Optional("") {
                pendingCommands.removeValue(forKey: cmdId)?.resume(returning: body)
            }
        case .commandError(_, let cmdId, _):
            let body = pendingBodies.removeValue(forKey: cmdId) ?? ""
            pendingCommands.removeValue(forKey: cmdId)?
                .resume(throwing: ClientError.processFailedToStart("tmux error: \(body)"))
        case .exit:
            disconnect()
        default:
            break
        }
        eventStreamContinuation?.yield(event)
    }

    private func handleProcessTermination(status: Int32) {
        logger.warning("tmux -C process terminated (status=\(status))")
        disconnect()
    }

    private var pendingBodies: [Int: String] = [:]
```

- [ ] **Step 2: 빌드 확인**

Run: `swift build --target TmuxKit`
Expected: `Build complete!`

- [ ] **Step 3: Commit**

```bash
git add Sources/TmuxKit/ControlClient.swift
git commit -m "feat(TmuxKit): ControlClient bootstrap + stdout 펌프 + 이벤트 디스패치"
```

---

## Task 14: TmuxKit — send command (async response)

**Files:**
- Modify: `Sources/TmuxKit/ControlClient.swift`

- [ ] **Step 1: send(_:) 메서드 추가**

Append to `ControlClient` actor (before the closing `}`):
```swift
    /// tmux 커맨드를 전송하고 응답 본문(raw string)을 반환. %end 수신 시 resolve.
    @discardableResult
    public func send(_ command: TmuxCommand, timeout: TimeInterval = 5.0) async throws -> String {
        guard let stdin = stdinPipe?.fileHandleForWriting else {
            throw ClientError.notConnected
        }

        nextCmdId += 1
        let _ = nextCmdId // cmdId 는 tmux 가 붙이는 것. 우리는 응답 매칭을 body carry 순서로 처리.

        // tmux control mode 는 명령을 라인으로 받고, 본인이 cmdId 를 할당해 %begin 에 실음.
        // 클라이언트 측에서는 "다음 %begin 의 cmdId" 를 예약 대기로 처리해야 함.
        return try await withCheckedThrowingContinuation { continuation in
            Task {
                await self.registerNextPendingCommand(continuation: continuation)
                let line = command.cliString + "\n"
                if let data = line.data(using: .utf8) {
                    do {
                        try stdin.write(contentsOf: data)
                    } catch {
                        await self.rejectLastPending(error: error)
                    }
                }
            }
        }
    }

    // 다음 %begin 이 붙일 cmdId 가 아직 미정이므로, 큐로 보관 → 첫 %begin 수신 시 바인딩.
    private var awaitingBegin: [CheckedContinuation<String, Error>] = []

    private func registerNextPendingCommand(continuation: CheckedContinuation<String, Error>) {
        awaitingBegin.append(continuation)
    }

    private func rejectLastPending(error: Error) {
        if let cont = awaitingBegin.popLast() {
            cont.resume(throwing: error)
        }
    }
```

그리고 `handleEvent(_:)` 의 `.commandBegin` 케이스를 아래로 교체 (기존엔 없음, 추가):
```swift
    // handleEvent 내부에 추가
    case .commandBegin(_, let cmdId, _):
        if !awaitingBegin.isEmpty {
            let cont = awaitingBegin.removeFirst()
            pendingCommands[cmdId] = cont
        }
```

최종 `handleEvent` 모습 (전체 교체):
```swift
    private func handleEvent(_ event: ControlEvent) {
        switch event {
        case .commandBegin(_, let cmdId, _):
            if !awaitingBegin.isEmpty {
                let cont = awaitingBegin.removeFirst()
                pendingCommands[cmdId] = cont
            }
        case .commandOutput(let cmdId, let body):
            pendingBodies[cmdId] = body
        case .commandEnd(_, let cmdId, _):
            let body = pendingBodies.removeValue(forKey: cmdId) ?? ""
            pendingCommands.removeValue(forKey: cmdId)?.resume(returning: body)
        case .commandError(_, let cmdId, _):
            let body = pendingBodies.removeValue(forKey: cmdId) ?? ""
            pendingCommands.removeValue(forKey: cmdId)?
                .resume(throwing: ClientError.processFailedToStart("tmux error: \(body)"))
        case .exit:
            disconnect()
        default:
            break
        }
        eventStreamContinuation?.yield(event)
    }
```

- [ ] **Step 2: 빌드 확인**

Run: `swift build --target TmuxKit`
Expected: `Build complete!`

- [ ] **Step 3: Commit**

```bash
git add Sources/TmuxKit/ControlClient.swift
git commit -m "feat(TmuxKit): ControlClient.send 비동기 커맨드 + %begin FIFO 매핑"
```

---

## Task 15: TmuxKit 통합 테스트 — 실제 tmux 바이너리

**Files:**
- Create: `Tests/TmuxKitIntegrationTests/ControlClientLiveTests.swift`

실제 `tmux` 바이너리가 설치된 환경에서만 실행. CI 에서는 `brew install tmux` 먼저.

- [ ] **Step 1: 전제 확인**

Run: `which tmux && tmux -V`
Expected: 경로 출력 (`/opt/homebrew/bin/tmux` 등) 및 버전.
없으면 `brew install tmux` 설치 후 진행.

- [ ] **Step 2: 통합 테스트 작성**

Create `Tests/TmuxKitIntegrationTests/ControlClientLiveTests.swift`:
```swift
import XCTest
@testable import TmuxKit

final class ControlClientLiveTests: XCTestCase {
    /// 테스트 격리를 위해 각 테스트마다 `muxbar-test-<UUID>` 세션을 만들고 tear down.
    private var testSessionName: String = ""
    private var client: ControlClient!

    override func setUp() async throws {
        testSessionName = "muxbar-test-\(UUID().uuidString.prefix(8))"
        client = try ControlClient()
        try await client.bootstrap()
    }

    override func tearDown() async throws {
        // 생성된 세션 정리 (실패해도 무시)
        _ = try? await client.send(.killSession(name: testSessionName), timeout: 2.0)
        await client.disconnect()
    }

    func test_listSessions_includesCtl() async throws {
        let body = try await client.send(.listSessions)
        XCTAssertTrue(
            body.contains("_muxbar-ctl"),
            "list-sessions 결과에 _muxbar-ctl 포함되어야 함. actual:\n\(body)"
        )
    }

    func test_newSession_thenKill() async throws {
        try await client.send(.newSession(name: testSessionName, command: nil))

        let listAfterCreate = try await client.send(.listSessions)
        XCTAssertTrue(listAfterCreate.contains(testSessionName))

        try await client.send(.killSession(name: testSessionName))

        let listAfterKill = try await client.send(.listSessions)
        XCTAssertFalse(listAfterKill.contains(testSessionName))
    }

    func test_sessionsChanged_eventFires_onNewSession() async throws {
        let expectation = expectation(description: "sessions-changed received")

        let listenTask = Task {
            for await event in await client.events {
                if case .sessionsChanged = event {
                    expectation.fulfill()
                    return
                }
            }
        }

        try await client.send(.newSession(name: testSessionName, command: nil))
        await fulfillment(of: [expectation], timeout: 3.0)
        listenTask.cancel()
    }
}
```

- [ ] **Step 3: 통합 테스트 실행**

Run: `swift test --filter ControlClientLiveTests`
Expected: 3 tests passed.
실패 시: `tmux kill-server` 로 상태 리셋 후 재시도.

- [ ] **Step 4: Commit**

```bash
git add Tests/TmuxKitIntegrationTests/ControlClientLiveTests.swift
git commit -m "test(TmuxKit): ControlClient 실환경 통합 테스트"
```

---

## Task 16: TmuxKit — list-sessions 응답 파서

**Files:**
- Create: `Sources/TmuxKit/SessionListParser.swift`
- Create: `Tests/TmuxKitTests/SessionListParserTests.swift`

Task 11 에서 `list-sessions` 포맷을 `#{name}\t#{attached}\t#{windows}\t#{created}\t#{activity}\t#{path}` 로 정의. 응답 본문을 `[TmuxSession]` 으로 변환.

- [ ] **Step 1: 실패 테스트 작성**

Create `Tests/TmuxKitTests/SessionListParserTests.swift`:
```swift
import XCTest
@testable import TmuxKit
import Core

final class SessionListParserTests: XCTestCase {
    func test_singleLine_parsedCorrectly() throws {
        let body = "dev\t1\t3\t1700000000\t1700001234\t/Users/kgd/msa"
        let sessions = try SessionListParser.parse(body)
        XCTAssertEqual(sessions.count, 1)

        let s = sessions[0]
        XCTAssertEqual(s.id, "dev")
        XCTAssertTrue(s.isAttached)
        XCTAssertEqual(s.windowCount, 3)
        XCTAssertEqual(s.createdAt, Date(timeIntervalSince1970: 1_700_000_000))
        XCTAssertEqual(s.lastActivityAt, Date(timeIntervalSince1970: 1_700_001_234))
        XCTAssertEqual(s.workingDirectory, "/Users/kgd/msa")
    }

    func test_multipleLines() throws {
        let body = """
        dev\t1\t3\t1700000000\t1700001234\t/Users/kgd/msa
        api-test\t0\t1\t1700002000\t1700002500\t/Users/kgd/msa/api
        """
        let sessions = try SessionListParser.parse(body)
        XCTAssertEqual(sessions.map(\.id), ["dev", "api-test"])
        XCTAssertEqual(sessions[1].isAttached, false)
    }

    func test_emptyBody_returnsEmpty() throws {
        XCTAssertEqual(try SessionListParser.parse(""), [])
    }

    func test_malformedLine_throws() {
        let body = "malformed\tline"
        XCTAssertThrowsError(try SessionListParser.parse(body))
    }
}
```

- [ ] **Step 2: 테스트 실행 → 실패 확인**

Run: `swift test --filter SessionListParserTests`
Expected: Compile error — `SessionListParser` 미정의.

- [ ] **Step 3: SessionListParser 구현**

Create `Sources/TmuxKit/SessionListParser.swift`:
```swift
import Foundation
import Core

public enum SessionListParser {
    public enum ParseError: Error, Equatable {
        case malformedLine(String)
    }

    public static func parse(_ body: String) throws -> [TmuxSession] {
        let trimmed = body.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return [] }

        return try trimmed.split(separator: "\n").map { line in
            let parts = line.split(separator: "\t", omittingEmptySubsequences: false).map(String.init)
            guard parts.count == 6 else {
                throw ParseError.malformedLine(String(line))
            }
            guard let attached = Int(parts[1]),
                  let windows = Int(parts[2]),
                  let created = TimeInterval(parts[3]),
                  let activity = TimeInterval(parts[4]) else {
                throw ParseError.malformedLine(String(line))
            }
            let cwd = parts[5].isEmpty ? nil : parts[5]
            return TmuxSession(
                id: parts[0],
                isAttached: attached != 0,
                windowCount: windows,
                createdAt: Date(timeIntervalSince1970: created),
                lastActivityAt: Date(timeIntervalSince1970: activity),
                workingDirectory: cwd
            )
        }
    }
}
```

- [ ] **Step 4: 테스트 통과 확인**

Run: `swift test --filter SessionListParserTests`
Expected: 4 tests passed.

- [ ] **Step 5: Commit**

```bash
git add Sources/TmuxKit/SessionListParser.swift Tests/TmuxKitTests/SessionListParserTests.swift
git commit -m "feat(TmuxKit): list-sessions 응답 파서 → [TmuxSession]"
```

---

## Task 17: ControlClient — 고수준 helper `listSessions()`

**Files:**
- Modify: `Sources/TmuxKit/ControlClient.swift`
- Modify: `Tests/TmuxKitIntegrationTests/ControlClientLiveTests.swift`

- [ ] **Step 1: 통합 테스트 추가**

Append to `ControlClientLiveTests`:
```swift
    func test_listSessionsTyped_returnsArray() async throws {
        let sessions = try await client.listSessions()
        XCTAssertTrue(sessions.contains(where: { $0.id == "_muxbar-ctl" }))
        XCTAssertEqual(sessions.filter { $0.id == "_muxbar-ctl" }.count, 1)
    }

    func test_listSessionsTyped_includesNewSession() async throws {
        try await client.send(.newSession(name: testSessionName, command: nil))
        let sessions = try await client.listSessions()
        XCTAssertTrue(sessions.contains(where: { $0.id == testSessionName }))
    }
```

- [ ] **Step 2: listSessions() 메서드 추가**

Append to `ControlClient` actor in `Sources/TmuxKit/ControlClient.swift`:
```swift
    public func listSessions() async throws -> [TmuxSession] {
        let body = try await send(.listSessions)
        return try SessionListParser.parse(body)
    }
```

- [ ] **Step 3: 테스트 실행**

Run: `swift test --filter ControlClientLiveTests`
Expected: 5 tests passed (기존 3 + 추가 2).

- [ ] **Step 4: Commit**

```bash
git add Sources/TmuxKit/ControlClient.swift Tests/TmuxKitIntegrationTests/ControlClientLiveTests.swift
git commit -m "feat(TmuxKit): ControlClient.listSessions 고수준 helper"
```

---

## Task 18: README 보강 + docs/plan 인덱스

**Files:**
- Modify: `README.md`
- Create: `docs/README.md`

- [ ] **Step 1: README.md 업데이트**

Overwrite `README.md`:
```markdown
# muxbar

tmux session manager + caffeinate toggle — macOS menu bar app.

> **상태**: 개발 중 (v0.1 MVP 준비). Plan 1 (Foundation + TmuxKit) 진행.

## 사전 요구사항

- macOS 13 (Ventura) 이상
- Swift 5.9+
- `tmux` (Homebrew: `brew install tmux`)

## 빌드 & 실행

```bash
swift build
swift run muxbar
```

메뉴바 우측에 `terminal` 아이콘이 생깁니다. Quit 으로 종료.

## 테스트

```bash
swift test
# 통합 테스트는 tmux 바이너리 필요
swift test --filter ControlClientLiveTests
```

## 문서

- [v0.1 디자인 스펙](docs/specs/2026-04-17-v0.1-design.md)
- [Plan 1 — Foundation + TmuxKit](docs/plans/2026-04-17-plan-1-foundation-tmuxkit.md)

## 라이선스

MIT © 2026 kgd
```

- [ ] **Step 2: docs/README.md 작성**

Create `docs/README.md`:
```markdown
# muxbar Docs

## Specs
- [v0.1 Design](specs/2026-04-17-v0.1-design.md)

## Plans
- [Plan 1 — Foundation + TmuxKit](plans/2026-04-17-plan-1-foundation-tmuxkit.md)
- Plan 2 — SessionList UI + KeepAwake *(예정)*
- Plan 3 — Live Preview *(예정)*
- Plan 4 — Terminals + Hotkeys + Templates *(예정)*
- Plan 5 — Notifications + Distribution *(예정)*

## ADRs
*(미작성)*
```

- [ ] **Step 3: Commit**

```bash
git add README.md docs/README.md
git commit -m "docs: README 보강 + docs 인덱스"
```

---

## Task 19: Plan 1 회고 & Plan 2 준비

**Files:**
- Create: `docs/adr/ADR-0001-tmux-control-mode-over-polling.md`

- [ ] **Step 1: ADR 작성 (첫 번째 아키텍처 결정 기록)**

Create `docs/adr/ADR-0001-tmux-control-mode-over-polling.md`:
```markdown
# ADR-0001: tmux control mode 채택 (폴링 대신)

- Status: Accepted
- Date: 2026-04-17

## Context

muxbar 는 tmux 세션 상태를 실시간으로 표시해야 한다. 두 가지 옵션:

- **폴링**: `tmux list-sessions` 를 1~2초 주기로 반복 실행
- **Control mode** (`tmux -C`): 단일 영구 연결로 이벤트 푸시 수신

## Decision

Control mode 채택.

## Consequences

**장점**:
- 지연 없는 상태 반영 (%sessions-changed 즉시 수신)
- CPU 사용량 최소 (idle 시 실질 0)
- 라이브 프리뷰(Plan 3)의 전제. %output 을 푸시로 받아야 30+ FPS 달성 가능

**단점**:
- 프로토콜 파서 필요 (구현 완료: `ControlProtocol`)
- 프로세스 연결 끊김 시 재연결 로직 필요 (TBD: Plan 2)
- 테스트 복잡도 증가 (통합 테스트에 실제 tmux 바이너리 필요)

## References

- [tmux Control Mode Wiki](https://github.com/tmux/tmux/wiki/Control-Mode)
- [iTerm2 tmux integration](https://iterm2.com/documentation-tmux-integration.html)
- Design spec §3.1
```

- [ ] **Step 2: Plan 1 종료 검증 체크리스트**

Run and verify:
```bash
swift build 2>&1 | tail -3
swift test 2>&1 | tail -5
```
Expected: 모든 빌드/테스트 통과.

수동 스모크 테스트:
```bash
swift run muxbar &
sleep 2
pgrep -f muxbar  # PID 출력되어야 함
osascript -e 'tell application "System Events" to click menu bar item 1 of menu bar 1 of process "muxbar"' 2>&1 | head -1
pkill -f muxbar
```

- [ ] **Step 3: Commit**

```bash
git add docs/adr/
git commit -m "docs(adr): ADR-0001 tmux control mode 채택"
```

- [ ] **Step 4: Plan 1 완료 태그 (옵션)**

```bash
git tag -a plan-1-complete -m "Plan 1: Foundation + TmuxKit 완료"
```

---

## Plan 1 완료 기준 (Acceptance Criteria)

- [x] `swift build` 성공
- [x] `swift test` (단위) 전 테스트 통과
- [x] `swift test --filter ControlClientLiveTests` (통합) 전 테스트 통과
- [x] `swift run muxbar` 실행 시 메뉴바 아이콘 표시
- [x] `ControlClient.listSessions()` 호출 가능한 상태
- [x] ADR-0001 작성
- [x] README / docs 인덱스 업데이트

## Plan 2 예고

**범위**: SessionList UI + Terminal.app Attach + Kill + KeepAwake

**Task 개요**:
1. SessionStore (@MainActor ObservableObject) — ControlClient 구독, 내부 세션 필터
2. SessionListView / SessionRowView (SwiftUI)
3. TerminalAppAdapter (osascript via Process)
4. Kill 확인 다이얼로그
5. AwakeStore + KeepAwake 메뉴 아이템
6. 통합 스모크 테스트

예상 분량: 15~18 Task.
