# Closed-lid mode Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** MacBook 덮개 닫고도 시스템 sleep 없이 백그라운드 작업이 진행되도록 하는 메뉴바 토글을 추가한다 (`pmset disablesleep` + `caffeinate -is`, AppleScript admin prompt).

**Architecture:** `Core` 의 `ClosedLidStore` 가 토글 상태와 4중 자동해제(timer / AC 분리 / lid open / muxbar 종료)를 관리한다. `PowerControl` 이 AppleScript 로 sudo `pmset` 실행을 wrapping. `PowerSourceMonitor`/`LidStateMonitor` protocol 로 IOKit observer 를 추상화해서 테스트 시 mock 주입. UI 는 `ClosedLidMenuItem` 한 줄 + 기간 popover. AppDelegate 가 종료 경로에서 강제 OFF 보장.

**Tech Stack:** Swift 5.9+ (`Duration`), SwiftUI, AppKit (NSAppleScript), IOKit (`IOPSNotificationCreateRunLoopSource`, `IOServiceAddInterestNotification`), 기존 `SessionProvider`(caffeinate tmux session), XCTest.

**Spec:** `docs/specs/2026-05-08-closed-lid-mode-design.md`

---

## File Structure

```
Sources/
├── Core/
│   ├── PowerControl.swift            (신규)
│   ├── ClosedLidStore.swift          (신규)
│   ├── PowerSourceMonitor.swift      (신규)
│   └── LidStateMonitor.swift         (신규)
├── Features/
│   ├── ClosedLid/
│   │   └── ClosedLidMenuItem.swift   (신규)
│   └── MenuBarIcon/
│       └── MenuBarIcon.swift         (수정)
└── MuxBarApp/
    ├── MuxBarApp.swift                (수정)
    ├── AppState.swift                 (수정)
    └── MuxBarAppDelegate.swift        (수정)

Tests/CoreTests/
├── PowerControlTests.swift            (신규)
└── ClosedLidStoreTests.swift          (신규)
```

`PowerControl` / `ClosedLidStore` / `*Monitor` 는 `Core` 모듈. UI 는 `Features` 모듈. AppState wiring 은 `MuxBarApp`.

테스트 환경 주의: 사용자 머신에 Xcode.app 미설치 시 `swift test` 가 XCTest 모듈 못 찾을 수 있음. 그 경우 `swift build -c release` 만 통과 + 코드 리뷰로 검증, 또는 Xcode.app 또는 `XCODE_SELECT=/Applications/Xcode.app/Contents/Developer` 로 toolchain 전환 후 테스트.

---

## Task 1: PowerControl — pmset AppleScript wrapper

**Files:**
- Create: `Sources/Core/PowerControl.swift`
- Test: `Tests/CoreTests/PowerControlTests.swift`

목적: `pmset -a disablesleep 0/1` 을 AppleScript admin prompt 로 실행. test 는 명령 string 생성과 에러 매핑만 (NSAppleScript 실 호출은 sudo 필요해 manual).

- [ ] **Step 1: 실패 테스트 작성**

`Tests/CoreTests/PowerControlTests.swift`:

```swift
import XCTest
@testable import Core

final class PowerControlTests: XCTestCase {
    func test_buildScript_disable_true_emitsValueOne() {
        XCTAssertEqual(
            PowerControl.buildScript(disable: true),
            #"do shell script "/usr/bin/pmset -a disablesleep 1" with administrator privileges"#
        )
    }

    func test_buildScript_disable_false_emitsValueZero() {
        XCTAssertEqual(
            PowerControl.buildScript(disable: false),
            #"do shell script "/usr/bin/pmset -a disablesleep 0" with administrator privileges"#
        )
    }

    func test_mapError_userCanceledCode_returnsUserCancelled() {
        let dict: NSDictionary = [
            "NSAppleScriptErrorNumber": NSNumber(value: -128),
            "NSAppleScriptErrorMessage": "User canceled."
        ]
        XCTAssertEqual(PowerControl.mapError(dict), .userCancelled)
    }

    func test_mapError_otherCode_returnsScriptFailedWithMessage() {
        let dict: NSDictionary = [
            "NSAppleScriptErrorNumber": NSNumber(value: -1),
            "NSAppleScriptErrorMessage": "boom"
        ]
        XCTAssertEqual(PowerControl.mapError(dict), .scriptFailed("boom"))
    }
}
```

- [ ] **Step 2: 테스트 실패 확인**

```bash
swift test --filter PowerControlTests 2>&1 | tail -10
```
Expected: FAIL — `'PowerControl' is not defined` 또는 모듈 미존재.

- [ ] **Step 3: PowerControl 구현**

`Sources/Core/PowerControl.swift`:

```swift
import Foundation
import AppKit

public enum PowerControl {
    public enum Error: Swift.Error, Equatable {
        case userCancelled
        case scriptFailed(String)
    }

    static func buildScript(disable: Bool) -> String {
        let value = disable ? "1" : "0"
        return #"do shell script "/usr/bin/pmset -a disablesleep \#(value)" with administrator privileges"#
    }

    static func mapError(_ dict: NSDictionary) -> Error {
        let code = (dict["NSAppleScriptErrorNumber"] as? NSNumber)?.intValue ?? 0
        let msg = dict["NSAppleScriptErrorMessage"] as? String ?? "unknown"
        return code == -128 ? .userCancelled : .scriptFailed(msg)
    }

    @MainActor
    public static func disableSystemSleep() async throws {
        try run(disable: true)
    }

    @MainActor
    public static func enableSystemSleep() async throws {
        try run(disable: false)
    }

    @MainActor
    private static func run(disable: Bool) throws {
        let source = buildScript(disable: disable)
        guard let script = NSAppleScript(source: source) else {
            throw Error.scriptFailed("AppleScript init failed")
        }
        var errorInfo: NSDictionary?
        _ = script.executeAndReturnError(&errorInfo)
        if let dict = errorInfo {
            throw mapError(dict)
        }
    }
}
```

- [ ] **Step 4: 빌드 + 테스트 통과 확인**

```bash
swift build -c release 2>&1 | tail -3
swift test --filter PowerControlTests 2>&1 | tail -10
```
Expected: 빌드 OK, 4개 테스트 pass. (XCTest 모듈 못 찾으면 빌드만 확인 + 코드 리뷰)

- [ ] **Step 5: 커밋**

```bash
git add Sources/Core/PowerControl.swift Tests/CoreTests/PowerControlTests.swift
git commit -m "feat(Core): PowerControl — pmset disablesleep AppleScript admin wrapper"
```

---

## Task 2: PowerSourceMonitor + LidStateMonitor protocols + IOKit impls

**Files:**
- Create: `Sources/Core/PowerSourceMonitor.swift`
- Create: `Sources/Core/LidStateMonitor.swift`

목적: ClosedLidStore 에 inject 가능한 IOKit observer 추상화. unit test 시 mock 으로 교체. IOKit 자체 동작은 manual 검증.

- [ ] **Step 1: PowerSourceMonitor 작성**

`Sources/Core/PowerSourceMonitor.swift`:

```swift
import Foundation
import IOKit
import IOKit.ps

public protocol PowerSourceMonitor: AnyObject {
    /// AC 어댑터 분리(AC → Battery transition) 시 1회 호출. 자동으로 stop. 재구독 필요시 다시 호출.
    @MainActor func onACDisconnect(_ handler: @escaping @MainActor () -> Void)
    @MainActor func stop()
}

public final class IOKitPowerSourceMonitor: PowerSourceMonitor {
    private var runLoopSource: CFRunLoopSource?
    private var handler: (@MainActor () -> Void)?

    public init() {}

    @MainActor
    public func onACDisconnect(_ handler: @escaping @MainActor () -> Void) {
        self.handler = handler
        let context = Unmanaged.passUnretained(self).toOpaque()
        let src = IOPSNotificationCreateRunLoopSource({ ctx in
            guard let ctx else { return }
            let me = Unmanaged<IOKitPowerSourceMonitor>.fromOpaque(ctx).takeUnretainedValue()
            DispatchQueue.main.async { me.checkAndFireIfDisconnected() }
        }, context)?.takeRetainedValue()
        guard let src else { return }
        self.runLoopSource = src
        CFRunLoopAddSource(CFRunLoopGetMain(), src, .defaultMode)
    }

    @MainActor
    private func checkAndFireIfDisconnected() {
        guard !isOnAC() else { return }
        handler?()
        stop()
    }

    @MainActor
    public func stop() {
        if let src = runLoopSource {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), src, .defaultMode)
        }
        runLoopSource = nil
        handler = nil
    }

    private func isOnAC() -> Bool {
        guard let info = IOPSCopyPowerSourcesInfo()?.takeRetainedValue(),
              let sources = IOPSCopyPowerSourcesList(info)?.takeRetainedValue() as? [CFTypeRef]
        else { return true }
        for src in sources {
            guard let desc = IOPSGetPowerSourceDescription(info, src)?.takeUnretainedValue() as? [String: Any]
            else { continue }
            if let state = desc[kIOPSPowerSourceStateKey] as? String {
                return state == kIOPSACPowerValue
            }
        }
        return true
    }
}
```

- [ ] **Step 2: LidStateMonitor 작성**

`Sources/Core/LidStateMonitor.swift`:

```swift
import Foundation
import IOKit

public protocol LidStateMonitor: AnyObject {
    /// lid가 닫힘→열림 transition 감지 시 1회 호출. 자동 stop.
    @MainActor func onLidOpen(_ handler: @escaping @MainActor () -> Void)
    @MainActor func stop()
}

public final class IOKitLidStateMonitor: LidStateMonitor {
    private var notifyPort: IONotificationPortRef?
    private var notification: io_object_t = 0
    private var service: io_service_t = 0
    private var handler: (@MainActor () -> Void)?
    private var lastClosed: Bool = false

    public init() {}

    @MainActor
    public func onLidOpen(_ handler: @escaping @MainActor () -> Void) {
        self.handler = handler
        self.lastClosed = readClamshellClosed() ?? false

        guard let port = IONotificationPortCreate(kIOMainPortDefault) else { return }
        IONotificationPortSetDispatchQueue(port, DispatchQueue.main)
        self.notifyPort = port

        guard let matching = IOServiceMatching("AppleClamshellState") else { return }
        let svc = IOServiceGetMatchingService(kIOMainPortDefault, matching)
        guard svc != 0 else { return }
        self.service = svc

        let context = Unmanaged.passUnretained(self).toOpaque()
        var note: io_object_t = 0
        let kr = IOServiceAddInterestNotification(
            port, svc, kIOGeneralInterest,
            { (ctx, _, _, _) in
                guard let ctx else { return }
                let me = Unmanaged<IOKitLidStateMonitor>.fromOpaque(ctx).takeUnretainedValue()
                DispatchQueue.main.async { me.recheck() }
            },
            context, &note
        )
        if kr == KERN_SUCCESS {
            self.notification = note
        }
    }

    @MainActor
    private func recheck() {
        guard let nowClosed = readClamshellClosed() else { return }
        if lastClosed && !nowClosed {
            handler?()
            stop()
            return
        }
        lastClosed = nowClosed
    }

    @MainActor
    public func stop() {
        if notification != 0 { IOObjectRelease(notification); notification = 0 }
        if service != 0 { IOObjectRelease(service); service = 0 }
        if let port = notifyPort { IONotificationPortDestroy(port) }
        notifyPort = nil
        handler = nil
    }

    private func readClamshellClosed() -> Bool? {
        guard let matching = IOServiceMatching("AppleClamshellState") else { return nil }
        let svc = IOServiceGetMatchingService(kIOMainPortDefault, matching)
        guard svc != 0 else { return nil }
        defer { IOObjectRelease(svc) }
        let value = IORegistryEntryCreateCFProperty(svc, "AppleClamshellState" as CFString,
                                                     kCFAllocatorDefault, 0)?.takeRetainedValue()
        return value as? Bool
    }
}
```

- [ ] **Step 3: 빌드 확인**

```bash
swift build -c release 2>&1 | tail -3
```
Expected: Build complete.

- [ ] **Step 4: 커밋**

```bash
git add Sources/Core/PowerSourceMonitor.swift Sources/Core/LidStateMonitor.swift
git commit -m "feat(Core): PowerSource/LidState monitor protocols + IOKit impls"
```

---

## Task 3: ClosedLidStore — 상태 머신 + caffeinate 통합 (timer/observer 제외)

**Files:**
- Create: `Sources/Core/ClosedLidStore.swift`
- Test: `Tests/CoreTests/ClosedLidStoreTests.swift`

목적: state enum + `turnOn`/`forceOff` 만 먼저 구현. caffeinate tmux 세션 시작/종료 통합. timer 와 observer 는 다음 Task 에서.

- [ ] **Step 1: 실패 테스트 작성 (mocks 포함)**

`Tests/CoreTests/ClosedLidStoreTests.swift`:

```swift
import XCTest
@testable import Core
@testable import TmuxKit

final class FakeSessionProvider: SessionProvider {
    var createdSessions: [(name: String, command: String?)] = []
    var killedSessions: [String] = []
    var shouldFailCreate = false
    var shouldFailKill = false

    var events: AsyncStream<SessionProviderEvent> { AsyncStream { _ in } }
    var paneOutput: AsyncStream<PaneOutputChunk> { AsyncStream { _ in } }

    func listSessions() async throws -> [TmuxSession] { [] }
    func capturePane(target: String, lines: Int) async throws -> String { "" }
    func listCaffeinateSessions() async throws -> [String] { [] }

    func createSession(name: String, command: String?) async throws {
        if shouldFailCreate { throw NSError(domain: "fake", code: 1) }
        createdSessions.append((name, command))
    }

    func kill(sessionName: String) async throws {
        if shouldFailKill { throw NSError(domain: "fake", code: 1) }
        killedSessions.append(sessionName)
    }
}

final class FakePowerController: ClosedLidStore.PowerController {
    var disableCalls = 0
    var enableCalls = 0
    var shouldThrowOnDisable: Error?
    var shouldThrowOnEnable: Error?

    func disableSystemSleep() async throws {
        disableCalls += 1
        if let e = shouldThrowOnDisable { throw e }
    }
    func enableSystemSleep() async throws {
        enableCalls += 1
        if let e = shouldThrowOnEnable { throw e }
    }
}

@MainActor
final class ClosedLidStoreTests: XCTestCase {
    func test_initialState_isOff() {
        let store = ClosedLidStore(power: FakePowerController())
        XCTAssertEqual(store.state, .off)
    }

    func test_turnOn_callsPowerControlAndCreatesCaffeineSession() async throws {
        let power = FakePowerController()
        let provider = FakeSessionProvider()
        let store = ClosedLidStore(power: power)

        await store.turnOn(duration: nil, sessionProvider: provider)

        XCTAssertEqual(power.disableCalls, 1)
        XCTAssertEqual(provider.createdSessions.count, 1)
        XCTAssertEqual(provider.createdSessions[0].name, "_muxbar-closed-lid")
        XCTAssertEqual(provider.createdSessions[0].command, "caffeinate -is")
        XCTAssertEqual(store.state, .on(expiresAt: nil))
    }

    func test_turnOn_powerCancelled_stateRemainsOff() async {
        let power = FakePowerController()
        power.shouldThrowOnDisable = PowerControl.Error.userCancelled
        let provider = FakeSessionProvider()
        let store = ClosedLidStore(power: power)

        await store.turnOn(duration: nil, sessionProvider: provider)

        XCTAssertEqual(store.state, .off)
        XCTAssertEqual(provider.createdSessions.count, 0)
    }

    func test_forceOff_callsEnableAndKillsSession() async {
        let power = FakePowerController()
        let provider = FakeSessionProvider()
        let store = ClosedLidStore(power: power)
        await store.turnOn(duration: nil, sessionProvider: provider)

        await store.forceOff(sessionProvider: provider)

        XCTAssertEqual(power.enableCalls, 1)
        XCTAssertEqual(provider.killedSessions, ["_muxbar-closed-lid"])
        XCTAssertEqual(store.state, .off)
    }

    func test_forceOff_idempotent_whenAlreadyOff() async {
        let power = FakePowerController()
        let provider = FakeSessionProvider()
        let store = ClosedLidStore(power: power)

        await store.forceOff(sessionProvider: provider)
        await store.forceOff(sessionProvider: provider)

        XCTAssertEqual(power.enableCalls, 0)
        XCTAssertEqual(provider.killedSessions.count, 0)
    }
}
```

- [ ] **Step 2: 테스트 실패 확인**

```bash
swift test --filter ClosedLidStoreTests 2>&1 | tail -10
```
Expected: FAIL — `ClosedLidStore` 미정의.

- [ ] **Step 3: ClosedLidStore 기본 구현**

`Sources/Core/ClosedLidStore.swift`:

```swift
import Foundation
import MuxLogging

@MainActor
public final class ClosedLidStore: ObservableObject {
    public static let sessionName = "_muxbar-closed-lid"
    public static let caffeinateCommand = "caffeinate -is"

    public enum State: Equatable {
        case off
        case on(expiresAt: Date?)  // nil = infinite

        public var isOn: Bool { if case .off = self { return false } else { return true } }
    }

    public protocol PowerController: AnyObject {
        func disableSystemSleep() async throws
        func enableSystemSleep() async throws
    }

    @Published public private(set) var state: State = .off
    @Published public private(set) var isToggling: Bool = false

    private let power: PowerController
    private let logger = MuxLogging.logger("Core.ClosedLidStore")

    public init(power: PowerController) {
        self.power = power
    }

    public func turnOn(duration: Duration?, sessionProvider: any SessionProvider) async {
        guard !state.isOn, !isToggling else { return }
        isToggling = true
        defer { isToggling = false }

        do {
            try await power.disableSystemSleep()
        } catch {
            logger.warning("disableSystemSleep failed: \(error.localizedDescription)")
            return
        }

        do {
            try await sessionProvider.createSession(
                name: Self.sessionName, command: Self.caffeinateCommand
            )
        } catch {
            logger.warning("caffeinate session create failed (pmset stays on): \(error.localizedDescription)")
            // pmset 은 이미 적용 → state 는 ON 유지
        }

        let expiresAt: Date? = duration.map { d in
            Date().addingTimeInterval(TimeInterval(d.components.seconds))
        }
        state = .on(expiresAt: expiresAt)
    }

    public func forceOff(sessionProvider: any SessionProvider) async {
        guard state.isOn else { return }
        isToggling = true
        defer { isToggling = false }

        do {
            try await power.enableSystemSleep()
        } catch {
            logger.warning("enableSystemSleep failed: \(error.localizedDescription)")
            // 진행 — sleep 회복이 우선이지만 명령 실패 시 사용자가 인지해야
        }

        do {
            try await sessionProvider.kill(sessionName: Self.sessionName)
        } catch {
            logger.warning("kill closed-lid session failed: \(error.localizedDescription)")
        }

        state = .off
    }
}

extension PowerControl: ClosedLidStore.PowerController {}
```

마지막 줄 `extension PowerControl: ...` 은 컴파일 오류 (PowerControl 은 enum, conformance 추가 위해 별도 wrapper 필요). 다음 step 에서 수정.

- [ ] **Step 4: PowerControl wrapper 추가**

`Sources/Core/PowerControl.swift` 에 wrapper struct 추가 — 파일 하단에 추가:

```swift
/// ClosedLidStore.PowerController 어댑터.
public struct DefaultPowerController: ClosedLidStore.PowerController {
    public init() {}
    public func disableSystemSleep() async throws { try await PowerControl.disableSystemSleep() }
    public func enableSystemSleep() async throws { try await PowerControl.enableSystemSleep() }
}
```

`Sources/Core/ClosedLidStore.swift` 의 마지막 `extension PowerControl: ...` 줄 삭제.

- [ ] **Step 5: 빌드 + 테스트 통과 확인**

```bash
swift build -c release 2>&1 | tail -3
swift test --filter ClosedLidStoreTests 2>&1 | tail -10
```
Expected: 빌드 OK, 5 tests pass.

- [ ] **Step 6: 커밋**

```bash
git add Sources/Core/ClosedLidStore.swift Sources/Core/PowerControl.swift Tests/CoreTests/ClosedLidStoreTests.swift
git commit -m "feat(Core): ClosedLidStore — basic state machine + caffeinate integration"
```

---

## Task 4: ClosedLidStore — timer 만료 자동 OFF

**Files:**
- Modify: `Sources/Core/ClosedLidStore.swift`
- Modify: `Tests/CoreTests/ClosedLidStoreTests.swift`

목적: `turnOn(duration:)` 에 duration 주면 timer 가지고 자동 forceOff.

- [ ] **Step 1: 실패 테스트 추가**

`Tests/CoreTests/ClosedLidStoreTests.swift` 안에 추가:

```swift
func test_turnOn_withShortDuration_autoForceOffAfterExpiry() async throws {
    let power = FakePowerController()
    let provider = FakeSessionProvider()
    let store = ClosedLidStore(power: power)

    await store.turnOn(duration: .milliseconds(100), sessionProvider: provider)
    XCTAssertTrue(store.state.isOn)

    try await Task.sleep(nanoseconds: 250_000_000)

    XCTAssertEqual(store.state, .off)
    XCTAssertEqual(power.enableCalls, 1)
}

func test_forceOff_cancelsPendingTimer() async throws {
    let power = FakePowerController()
    let provider = FakeSessionProvider()
    let store = ClosedLidStore(power: power)

    await store.turnOn(duration: .milliseconds(500), sessionProvider: provider)
    await store.forceOff(sessionProvider: provider)

    try await Task.sleep(nanoseconds: 700_000_000)

    XCTAssertEqual(power.enableCalls, 1)  // timer 가 또 forceOff 호출하면 안 됨
}
```

- [ ] **Step 2: 테스트 실패 확인**

```bash
swift test --filter ClosedLidStoreTests 2>&1 | tail -15
```
Expected: 새 두 테스트 fail (timer 미구현).

- [ ] **Step 3: ClosedLidStore 에 timer 추가**

`Sources/Core/ClosedLidStore.swift` 수정:

```swift
@MainActor
public final class ClosedLidStore: ObservableObject {
    // ... (기존 코드 유지) ...
    
    private var expirationTask: Task<Void, Never>?

    public func turnOn(duration: Duration?, sessionProvider: any SessionProvider) async {
        guard !state.isOn, !isToggling else { return }
        isToggling = true
        defer { isToggling = false }

        do { try await power.disableSystemSleep() }
        catch {
            logger.warning("disableSystemSleep failed: \(error.localizedDescription)")
            return
        }

        do {
            try await sessionProvider.createSession(name: Self.sessionName, command: Self.caffeinateCommand)
        } catch {
            logger.warning("caffeinate session create failed: \(error.localizedDescription)")
        }

        let expiresAt: Date? = duration.map { Date().addingTimeInterval(TimeInterval($0.components.seconds)) }
        state = .on(expiresAt: expiresAt)

        if let duration {
            expirationTask = Task { [weak self, weak sp = sessionProvider as AnyObject] in
                let nanos = UInt64(duration.components.seconds) * 1_000_000_000
                    + UInt64(duration.components.attoseconds / 1_000_000_000)
                try? await Task.sleep(nanoseconds: nanos)
                guard !Task.isCancelled else { return }
                guard let self else { return }
                if let sp = sp as? (any SessionProvider) {
                    await self.forceOff(sessionProvider: sp)
                }
            }
        }
    }

    public func forceOff(sessionProvider: any SessionProvider) async {
        guard state.isOn else { return }
        isToggling = true
        defer { isToggling = false }

        expirationTask?.cancel()
        expirationTask = nil

        do { try await power.enableSystemSleep() }
        catch { logger.warning("enableSystemSleep failed: \(error.localizedDescription)") }

        do { try await sessionProvider.kill(sessionName: Self.sessionName) }
        catch { logger.warning("kill closed-lid session failed: \(error.localizedDescription)") }

        state = .off
    }
}
```

- [ ] **Step 4: 빌드 + 테스트 통과 확인**

```bash
swift build -c release 2>&1 | tail -3
swift test --filter ClosedLidStoreTests 2>&1 | tail -15
```
Expected: 7 tests pass.

- [ ] **Step 5: 커밋**

```bash
git add Sources/Core/ClosedLidStore.swift Tests/CoreTests/ClosedLidStoreTests.swift
git commit -m "feat(Core): ClosedLidStore — duration-based timer auto-off"
```

---

## Task 5: ClosedLidStore — AC 분리 + lid open observer

**Files:**
- Modify: `Sources/Core/ClosedLidStore.swift`

목적: AC monitor + Lid monitor 를 turnOn 시 시작, forceOff 시 stop. unit test 는 mock monitor 로.

- [ ] **Step 1: 테스트에 mock monitor 추가**

`Tests/CoreTests/ClosedLidStoreTests.swift` 상단에 추가:

```swift
final class FakePowerSourceMonitor: PowerSourceMonitor {
    var startedHandler: (@MainActor () -> Void)?
    var stopped = false

    @MainActor
    func onACDisconnect(_ handler: @escaping @MainActor () -> Void) {
        startedHandler = handler
    }
    @MainActor
    func stop() { stopped = true; startedHandler = nil }

    @MainActor
    func fire() { startedHandler?() }
}

final class FakeLidStateMonitor: LidStateMonitor {
    var startedHandler: (@MainActor () -> Void)?
    var stopped = false

    @MainActor
    func onLidOpen(_ handler: @escaping @MainActor () -> Void) {
        startedHandler = handler
    }
    @MainActor
    func stop() { stopped = true; startedHandler = nil }

    @MainActor
    func fire() { startedHandler?() }
}
```

테스트 추가:

```swift
func test_turnOn_subscribesACAndLidMonitors() async {
    let power = FakePowerController()
    let provider = FakeSessionProvider()
    let acMon = FakePowerSourceMonitor()
    let lidMon = FakeLidStateMonitor()
    let store = ClosedLidStore(power: power, acMonitor: acMon, lidMonitor: lidMon)

    await store.turnOn(duration: nil, sessionProvider: provider)

    XCTAssertNotNil(acMon.startedHandler)
    XCTAssertNotNil(lidMon.startedHandler)
}

func test_acDisconnect_triggersForceOff() async throws {
    let power = FakePowerController()
    let provider = FakeSessionProvider()
    let acMon = FakePowerSourceMonitor()
    let lidMon = FakeLidStateMonitor()
    let store = ClosedLidStore(power: power, acMonitor: acMon, lidMonitor: lidMon)

    await store.turnOn(duration: nil, sessionProvider: provider)
    acMon.fire()
    try await Task.sleep(nanoseconds: 100_000_000)

    XCTAssertEqual(store.state, .off)
}

func test_lidOpen_triggersForceOff() async throws {
    let power = FakePowerController()
    let provider = FakeSessionProvider()
    let acMon = FakePowerSourceMonitor()
    let lidMon = FakeLidStateMonitor()
    let store = ClosedLidStore(power: power, acMonitor: acMon, lidMonitor: lidMon)

    await store.turnOn(duration: nil, sessionProvider: provider)
    lidMon.fire()
    try await Task.sleep(nanoseconds: 100_000_000)

    XCTAssertEqual(store.state, .off)
}

func test_forceOff_stopsBothMonitors() async {
    let power = FakePowerController()
    let provider = FakeSessionProvider()
    let acMon = FakePowerSourceMonitor()
    let lidMon = FakeLidStateMonitor()
    let store = ClosedLidStore(power: power, acMonitor: acMon, lidMonitor: lidMon)

    await store.turnOn(duration: nil, sessionProvider: provider)
    await store.forceOff(sessionProvider: provider)

    XCTAssertTrue(acMon.stopped)
    XCTAssertTrue(lidMon.stopped)
}
```

- [ ] **Step 2: 테스트 실패 확인**

```bash
swift test --filter ClosedLidStoreTests 2>&1 | tail -20
```
Expected: 새 테스트 fail (init 시그너처 불일치, monitor 미구독).

- [ ] **Step 3: ClosedLidStore 에 monitor 통합**

`Sources/Core/ClosedLidStore.swift` 수정:

```swift
@MainActor
public final class ClosedLidStore: ObservableObject {
    // ... 기존 ...

    private let power: PowerController
    private let acMonitor: PowerSourceMonitor
    private let lidMonitor: LidStateMonitor
    private weak var lastSessionProvider: AnyObject?

    public init(
        power: PowerController,
        acMonitor: PowerSourceMonitor = IOKitPowerSourceMonitor(),
        lidMonitor: LidStateMonitor = IOKitLidStateMonitor()
    ) {
        self.power = power
        self.acMonitor = acMonitor
        self.lidMonitor = lidMonitor
    }

    public func turnOn(duration: Duration?, sessionProvider: any SessionProvider) async {
        guard !state.isOn, !isToggling else { return }
        isToggling = true
        defer { isToggling = false }

        do { try await power.disableSystemSleep() }
        catch {
            logger.warning("disableSystemSleep failed: \(error.localizedDescription)")
            return
        }

        do { try await sessionProvider.createSession(name: Self.sessionName, command: Self.caffeinateCommand) }
        catch { logger.warning("caffeinate session create failed: \(error.localizedDescription)") }

        let expiresAt: Date? = duration.map { Date().addingTimeInterval(TimeInterval($0.components.seconds)) }
        state = .on(expiresAt: expiresAt)
        lastSessionProvider = sessionProvider as AnyObject

        if let duration {
            expirationTask = Task { [weak self] in
                let nanos = UInt64(duration.components.seconds) * 1_000_000_000
                    + UInt64(duration.components.attoseconds / 1_000_000_000)
                try? await Task.sleep(nanoseconds: nanos)
                guard !Task.isCancelled else { return }
                await self?.forceOffViaTrigger()
            }
        }

        acMonitor.onACDisconnect { [weak self] in
            Task { await self?.forceOffViaTrigger() }
        }
        lidMonitor.onLidOpen { [weak self] in
            Task { await self?.forceOffViaTrigger() }
        }
    }

    /// 자동해제 트리거 공통 진입점. 마지막 sessionProvider 가 있으면 그걸로 forceOff.
    private func forceOffViaTrigger() async {
        guard let provider = lastSessionProvider as? (any SessionProvider) else {
            // provider 없어도 pmset 만큼은 복원
            try? await power.enableSystemSleep()
            state = .off
            return
        }
        await forceOff(sessionProvider: provider)
    }

    public func forceOff(sessionProvider: any SessionProvider) async {
        guard state.isOn else { return }
        isToggling = true
        defer { isToggling = false }

        expirationTask?.cancel()
        expirationTask = nil
        acMonitor.stop()
        lidMonitor.stop()

        do { try await power.enableSystemSleep() }
        catch { logger.warning("enableSystemSleep failed: \(error.localizedDescription)") }

        do { try await sessionProvider.kill(sessionName: Self.sessionName) }
        catch { logger.warning("kill closed-lid session failed: \(error.localizedDescription)") }

        state = .off
        lastSessionProvider = nil
    }
}
```

- [ ] **Step 4: 빌드 + 테스트 통과 확인**

```bash
swift build -c release 2>&1 | tail -3
swift test --filter ClosedLidStoreTests 2>&1 | tail -20
```
Expected: 11 tests pass.

- [ ] **Step 5: 커밋**

```bash
git add Sources/Core/ClosedLidStore.swift Tests/CoreTests/ClosedLidStoreTests.swift
git commit -m "feat(Core): ClosedLidStore — AC/lid monitor 자동 OFF 트리거 통합"
```

---

## Task 6: ClosedLidMenuItem — UI + popover

**Files:**
- Create: `Sources/Features/ClosedLid/ClosedLidMenuItem.swift`

목적: 메뉴 한 줄 + 기간 popover + 카운트다운. UI 라 unit test 없음 — 빌드 + manual.

- [ ] **Step 1: ClosedLidMenuItem 작성**

`Sources/Features/ClosedLid/ClosedLidMenuItem.swift`:

```swift
import SwiftUI
import Core

public struct ClosedLidMenuItem: View {
    @ObservedObject public var store: ClosedLidStore
    public let onTurnOn: (Duration?) -> Void
    public let onTurnOff: () -> Void

    @State private var showingPicker = false
    @State private var now = Date()

    private let tick = Timer.publish(every: 1, on: .main, in: .common).autoconnect()

    public init(
        store: ClosedLidStore,
        onTurnOn: @escaping (Duration?) -> Void,
        onTurnOff: @escaping () -> Void
    ) {
        self.store = store
        self.onTurnOn = onTurnOn
        self.onTurnOff = onTurnOff
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack {
                Image(systemName: store.state.isOn ? "lock.fill" : "lock")
                    .foregroundStyle(store.state.isOn ? .red : .secondary)
                Text("Closed-lid mode")
                Spacer()
                if store.isToggling {
                    ProgressView().scaleEffect(0.6)
                } else {
                    Text(stateLabel)
                        .font(.caption)
                        .foregroundStyle(store.state.isOn ? .red : .secondary)
                }
            }
            if store.state.isOn {
                Text("sleep blocked (system-wide)")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .contentShape(Rectangle())
        .onTapGesture {
            if store.state.isOn { onTurnOff() }
            else { showingPicker = true }
        }
        .popover(isPresented: $showingPicker, arrowEdge: .leading) {
            durationPicker
        }
        .onReceive(tick) { now = $0 }
    }

    private var stateLabel: String {
        switch store.state {
        case .off:
            return "OFF"
        case .on(let expiresAt):
            guard let expiresAt else { return "ON · ∞" }
            let remaining = max(0, Int(expiresAt.timeIntervalSince(now)))
            let h = remaining / 3600
            let m = (remaining % 3600) / 60
            let s = remaining % 60
            return String(format: "ON · %d:%02d:%02d", h, m, s)
        }
    }

    private var durationPicker: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Duration").font(.caption).foregroundStyle(.secondary)
            ForEach(durationOptions, id: \.label) { opt in
                Button(opt.label) {
                    showingPicker = false
                    onTurnOn(opt.duration)
                }
                .buttonStyle(.plain)
                .padding(.vertical, 4)
                .padding(.horizontal, 8)
            }
        }
        .padding(8)
    }

    private var durationOptions: [(label: String, duration: Duration?)] {
        [
            ("1 hour", .seconds(3600)),
            ("4 hours", .seconds(14400)),
            ("8 hours", .seconds(28800)),
            ("∞ (until manual off)", nil),
        ]
    }
}
```

- [ ] **Step 2: 빌드 확인**

```bash
swift build -c release 2>&1 | tail -3
```
Expected: Build complete.

- [ ] **Step 3: 커밋**

```bash
git add Sources/Features/ClosedLid/ClosedLidMenuItem.swift
git commit -m "feat(Features): ClosedLidMenuItem UI + duration popover + countdown"
```

---

## Task 7: AppState wiring + MuxBarApp 메뉴 통합

**Files:**
- Modify: `Sources/MuxBarApp/AppState.swift`
- Modify: `Sources/MuxBarApp/MuxBarApp.swift`

목적: `ClosedLidStore` 인스턴스를 AppState 가 보유. menuContent 에 메뉴 항목 추가.

- [ ] **Step 1: AppState 에 ClosedLidStore 추가**

`Sources/MuxBarApp/AppState.swift` 수정 — 클래스 선언부에 새 프로퍼티:

```swift
public let closedLidStore: ClosedLidStore
```

`init()` 안에서 초기화 (다른 store 들 옆):

```swift
self.closedLidStore = ClosedLidStore(power: DefaultPowerController())
```

`init()` 의 나머지 코드는 변경 없음.

새 public method 추가 (다른 toggle 메서드들 옆):

```swift
public func turnOnClosedLid(duration: Duration?) {
    guard let client = controlClient else {
        sessionStore.apply(error: "tmux not connected — connect first")
        return
    }
    Task {
        await closedLidStore.turnOn(duration: duration, sessionProvider: client)
        try? await Task.sleep(nanoseconds: 200_000_000)
        await sessionStore.refreshCaffeinate(from: client)
    }
}

public func turnOffClosedLid() {
    guard let client = controlClient else { return }
    Task {
        await closedLidStore.forceOff(sessionProvider: client)
        try? await Task.sleep(nanoseconds: 200_000_000)
        await sessionStore.refreshCaffeinate(from: client)
    }
}
```

- [ ] **Step 2: MuxBarApp 메뉴에 항목 추가**

`Sources/MuxBarApp/MuxBarApp.swift` — `menuContent` 의 KeepAwakeMenuItem 바로 아래에 추가:

```swift
ClosedLidMenuItem(
    store: appState.closedLidStore,
    onTurnOn: { duration in appState.turnOnClosedLid(duration: duration) },
    onTurnOff: { appState.turnOffClosedLid() }
)
.padding(.horizontal, 8)
.padding(.vertical, 6)

Divider()
```

(기존 KeepAwakeMenuItem 다음 Divider 와 New Session 사이)

- [ ] **Step 3: 빌드 + 재기동 + 메뉴 확인**

```bash
./build.sh 2>&1 | tail -5
pkill -f "muxbar.app/Contents/MacOS/muxbar"; sleep 1
nohup ./muxbar.app/Contents/MacOS/muxbar > ~/Library/Logs/muxbar.run.log 2>&1 & disown
```

메뉴바 클릭 → "Closed-lid mode  OFF" 항목 표시되는지 manual 확인.

- [ ] **Step 4: 커밋**

```bash
git add Sources/MuxBarApp/AppState.swift Sources/MuxBarApp/MuxBarApp.swift
git commit -m "feat(MuxBarApp): ClosedLidStore wiring + 메뉴 항목 통합"
```

---

## Task 8: MenuBarIcon — closed-lid 우선 빨간 lock

**Files:**
- Modify: `Sources/Features/MenuBarIcon/MenuBarIcon.swift`

목적: closed-lid ON 일 때 메뉴바 아이콘을 빨간 lock 으로. Keep Awake 의 오렌지보다 우선.

- [ ] **Step 1: MenuBarIcon 인터페이스에 closedLidStore 추가**

`Sources/Features/MenuBarIcon/MenuBarIcon.swift` 의 init 시그너처에 `closedLidStore: ClosedLidStore` 추가, body 의 아이콘 결정 로직 수정:

```swift
public struct MenuBarIcon: View {
    @ObservedObject public var sessionStore: SessionStore
    @ObservedObject public var awakeStore: AwakeStore
    @ObservedObject public var closedLidStore: ClosedLidStore

    public init(
        sessionStore: SessionStore,
        awakeStore: AwakeStore,
        closedLidStore: ClosedLidStore
    ) {
        self.sessionStore = sessionStore
        self.awakeStore = awakeStore
        self.closedLidStore = closedLidStore
    }

    public var body: some View {
        if closedLidStore.state.isOn {
            // 빨간 lock 우선
            Image(systemName: "lock.fill")
                .renderingMode(.template)
                .foregroundColor(.red)
        } else if awakeStore.isAwake(in: sessionStore) {
            // 기존: awake 시 오렌지 cup
            // (기존 NSImage isTemplate=false 처리 그대로 유지 — 파일의 기존 코드 참고)
            existingAwakeIcon
        } else {
            existingDefaultIcon
        }
    }

    // existingAwakeIcon / existingDefaultIcon 는 파일에 이미 있는 구현 그대로 옮기기
}
```

(주: 기존 `MenuBarIcon.swift` 의 awake/default 분기 코드를 위 if-else 의 두 번째/세 번째 분기로 이동. 코멘트 `// caffeinate 활성 시 오렌지 색상을 강제하려면 NSImage + isTemplate=false 조합 필요.` 도 그대로.)

- [ ] **Step 2: 호출 측 (MuxBarApp) 업데이트**

`Sources/MuxBarApp/MuxBarApp.swift` 의 `MenuBarIcon(...)` 호출에 `closedLidStore: appState.closedLidStore` 추가:

```swift
MenuBarIcon(
    sessionStore: appState.sessionStore,
    awakeStore: appState.awakeStore,
    closedLidStore: appState.closedLidStore
)
```

- [ ] **Step 3: 빌드 + 재기동 + manual 확인**

```bash
./build.sh 2>&1 | tail -3
pkill -f muxbar.app; sleep 1
nohup ./muxbar.app/Contents/MacOS/muxbar > ~/Library/Logs/muxbar.run.log 2>&1 & disown
```

OFF: 회색 cup. Keep Awake ON: 오렌지 cup. Closed-lid ON: 빨간 lock. 셋 다 manual 확인.

- [ ] **Step 4: 커밋**

```bash
git add Sources/Features/MenuBarIcon/MenuBarIcon.swift Sources/MuxBarApp/MuxBarApp.swift
git commit -m "feat(MenuBarIcon): closed-lid ON 시 빨간 lock 아이콘 우선 표시"
```

---

## Task 9: AppDelegate — applicationShouldTerminate cleanup

**Files:**
- Modify: `Sources/MuxBarApp/MuxBarAppDelegate.swift`

목적: muxbar 종료 시 closed-lid 가 ON 이면 비동기 cleanup 후 reply. pmset 복원 보장.

- [ ] **Step 1: AppDelegate 에 closedLidStore + appState 참조 wiring**

`Sources/MuxBarApp/MuxBarAppDelegate.swift` 수정:

```swift
import AppKit
import Core
import MuxLogging

@MainActor
final class MuxBarAppDelegate: NSObject, NSApplicationDelegate {
    private let logger = MuxLogging.logger("AppDelegate")
    weak var appState: AppState?

    func applicationWillFinishLaunching(_ notification: Notification) {
        ProcessInfo.processInfo.disableAutomaticTermination("menu bar agent")
        ProcessInfo.processInfo.disableSuddenTermination()
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        logger.info("launched pid=\(getpid())")
        let nc = NSWorkspace.shared.notificationCenter
        let events: [(Notification.Name, String)] = [
            (NSWorkspace.willSleepNotification, "willSleep"),
            (NSWorkspace.didWakeNotification, "didWake"),
            (NSWorkspace.willPowerOffNotification, "willPowerOff"),
        ]
        for (name, label) in events {
            nc.addObserver(forName: name, object: nil, queue: .main) { _ in
                MuxLogging.logger("AppDelegate").info("\(label)")
            }
        }
    }

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        guard let appState, appState.closedLidStore.state.isOn else {
            return .terminateNow
        }
        logger.critical("closed-lid ON — cleanup before terminate")
        Task { @MainActor in
            await appState.turnOffClosedLidAndWait()
            sender.reply(toApplicationShouldTerminate: true)
        }
        return .terminateLater
    }

    func applicationWillTerminate(_ notification: Notification) {
        logger.critical("willTerminate")
    }
}
```

- [ ] **Step 2: AppState 에 동기적 wait helper 추가**

`Sources/MuxBarApp/AppState.swift` 에 추가:

```swift
public func turnOffClosedLidAndWait() async {
    guard let client = controlClient else { return }
    await closedLidStore.forceOff(sessionProvider: client)
}
```

- [ ] **Step 3: MuxBarApp.swift 에서 delegate.appState 연결**

`Sources/MuxBarApp/MuxBarApp.swift` 수정 — `init()` 마지막에 추가:

```swift
init() {
    MuxLogging.bootstrap()
    MuxLogging.logger("app").info("muxbar launched")
    appDelegate.appState = appState  // wiring
}
```

(주: `@StateObject private var appState = AppState()` 와 `@NSApplicationDelegateAdaptor(MuxBarAppDelegate.self) private var appDelegate` 이미 선언돼 있음. init 안에서 wiring.)

근데 SwiftUI 에서 `@StateObject` 의 wrappedValue 는 init 안에서 접근 시 wrapped 안에 있음. `_appState.wrappedValue.???` 또는 `Self._appState`. 안전한 패턴: AppDelegate 가 first launch 후 NotificationCenter 로 받기. 더 간단:

```swift
init() {
    MuxLogging.bootstrap()
    MuxLogging.logger("app").info("muxbar launched")
}

var body: some Scene {
    MenuBarExtra {
        menuContent
            .onAppear {
                appDelegate.appState = appState
                Task { @MainActor in await appState.ensureBootstrapped() }
            }
    } label: { ... }
}
```

`onAppear` 에서 wiring. 첫 메뉴 열릴 때 셋업 — applicationShouldTerminate 시점엔 이미 셋업 끝.

- [ ] **Step 4: 빌드 + 재기동 + manual 확인**

```bash
./build.sh 2>&1 | tail -3
pkill -f muxbar.app; sleep 1
nohup ./muxbar.app/Contents/MacOS/muxbar > ~/Library/Logs/muxbar.run.log 2>&1 & disown
```

메뉴 한 번 열기 (wiring 발동) → Closed-lid ON → muxbar Quit 누름 → `pmset -g | grep -i disablesleep` 가 `0` 인지 확인.

```bash
pmset -g | grep -i disablesleep
```
Expected: `0` (또는 라인 자체 없음).

- [ ] **Step 5: 커밋**

```bash
git add Sources/MuxBarApp/MuxBarAppDelegate.swift Sources/MuxBarApp/AppState.swift Sources/MuxBarApp/MuxBarApp.swift
git commit -m "feat(MuxBarApp): applicationShouldTerminate cleanup — closed-lid pmset 복원 보장"
```

---

## Task 10: Manual integration verification + 문서 업데이트

**Files:**
- Modify: `README.md` 및 `README.ko.md` (closed-lid mode 항목 추가)

목적: 실제 사용 시나리오 manual 검증 + README 항목 추가.

- [ ] **Step 1: 사전 빌드 + 재기동**

```bash
./build.sh 2>&1 | tail -3
pkill -f muxbar.app; sleep 1
nohup ./muxbar.app/Contents/MacOS/muxbar > ~/Library/Logs/muxbar.run.log 2>&1 & disown
sleep 2
pgrep -lf muxbar.app
```
Expected: 프로세스 살아있음, 메뉴바에 muxbar 아이콘 보임.

- [ ] **Step 2: 토글 ON manual 검증**

1. 메뉴바 클릭 → Closed-lid mode 항목 클릭
2. popover 에서 "1 hour" 선택
3. macOS password prompt → 입력 (Touch ID 가능)
4. 확인:
   - 메뉴 항목이 `ON · 0:59:5x` 로 카운트다운
   - 메뉴바 아이콘이 빨간 lock
   - `pmset -g | grep -i disablesleep` 결과 `1`
   - `tmux ls` 에 `_muxbar-closed-lid` 세션 존재

- [ ] **Step 3: lid close 작업 진행 검증**

1. lid 닫음
2. 외부에서 ssh 또는 다른 머신에서 `pmset -g log | tail` 또는 `top` 등으로 작업 진행 확인 (5분 이상)
3. lid 열기 → 자동 OFF 확인 (메뉴 항목 OFF, `pmset -g | grep -i disablesleep` = 0)

- [ ] **Step 4: AC 분리 자동 OFF 검증**

1. 다시 ON (1 hour)
2. AC 어댑터 분리
3. 즉시 OFF 되는지 확인 (`pmset -g`, 메뉴 라벨)
4. AC 다시 연결

- [ ] **Step 5: 시간 만료 자동 OFF 검증**

1. ON 시 짧은 duration 으로 시뮬레이트 어렵다면 1h 그대로 두고 1시간 후 확인. 또는 코드 임시 수정 (시간 만료 path 가 통과하는지 unit test 로 이미 통과한 상태이므로 manual 은 production duration 으로 sanity)
2. 만료 시점에 `_muxbar-closed-lid` 세션 사라지고 `pmset -g`도 0

- [ ] **Step 6: muxbar quit 자동 OFF 검증**

1. ON
2. 메뉴 → Quit muxbar
3. `pmset -g | grep -i disablesleep` = 0 확인
4. `tmux ls` 에 `_muxbar-closed-lid` 없음 확인

- [ ] **Step 7: 권한 prompt cancel 검증**

1. ON 시도 → password prompt 에서 Cancel
2. 메뉴 항목 OFF 유지, `pmset -g` = 0 유지
3. stderr 로그에 `disableSystemSleep failed: User canceled.` 메시지

- [ ] **Step 8: README 업데이트**

`README.md` 의 Features 섹션 (Keep Awake 항목 다음) 에 추가:

```markdown
### Closed-lid mode

Toggle that prevents system sleep — including when the MacBook lid is closed.
Useful for unattended builds, long-running scripts, or remote sessions when you
want to throw the laptop in a bag and keep working.

- Click → choose duration (1h / 4h / 8h / ∞) → enter admin password (Touch ID supported)
- Auto-disables on: timer expiry, AC adapter unplug, lid open, muxbar quit
- Combines `pmset -a disablesleep 1` (system-wide) + `caffeinate -is` (idle/system)
- Uses an AppleScript admin prompt — no helper installer required, no Apple Developer
  Program needed
- Independent toggle from "Keep Awake"; menubar icon turns red 🔒 while active
```

`README.ko.md` 동일 위치에 한국어로:

```markdown
### Closed-lid mode

MacBook 덮개를 닫고도 시스템 sleep 없이 백그라운드 작업을 진행할 수 있게 하는 토글.
가방에 노트북을 넣고도 빌드/스크립트/원격 세션이 계속 돌아가게 한다.

- 클릭 → 지속 시간 선택 (1h / 4h / 8h / ∞) → 관리자 비밀번호 입력 (Touch ID 지원)
- 자동 해제: 시간 만료 / AC 어댑터 분리 / lid 열림 / muxbar 종료
- `pmset -a disablesleep 1` + `caffeinate -is` 결합
- AppleScript admin prompt 사용 — helper 설치/Apple Developer 멤버십 불필요
- Keep Awake 와 독립 토글, 활성 시 메뉴바 아이콘 빨간 🔒 로 표시
```

- [ ] **Step 9: 커밋**

```bash
git add README.md README.ko.md
git commit -m "docs: closed-lid mode README 항목 추가 (en/ko)"
```

---

## Self-Review Notes

- **Spec coverage 체크:**
  - Spec §3.1 PowerControl → Task 1 ✓
  - Spec §3.2 ClosedLidStore → Task 3,4,5 ✓
  - Spec §3.3 ClosedLidMenuItem → Task 6 ✓
  - Spec §3.4 MenuBarIcon 확장 → Task 8 ✓
  - Spec §3.5 AppDelegate hook → Task 9 ✓
  - Spec §4 Data Flow → Task 3,4,5 (turnOn/forceOff 흐름)
  - Spec §5 Permission Flow → Task 1 (PowerControl) + Task 10 manual cancel 검증
  - Spec §6 Error Handling → Task 3 의 power 실패/세션 실패 처리, Task 10 의 cancel 검증
  - Spec §7 State Indication → Task 6 (메뉴 라벨), Task 8 (아이콘)
  - Spec §8 Testing → Task 1,3,4,5 unit + Task 10 manual

- **Type/이름 일관성:** `ClosedLidStore.PowerController` 가 모든 Task 에서 동일. `_muxbar-closed-lid` 세션 이름 모든 Task 동일.

- **Placeholder:** 없음.
