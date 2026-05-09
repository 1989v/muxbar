# muxbar — Closed-lid mode Design

- **Date**: 2026-05-08
- **Status**: Draft (awaiting user review)
- **Author**: kgd
- **Related**: Keep Awake (caffeinate, v0.1), `Sources/Core/AwakeStore.swift`, `Sources/Features/KeepAwake/KeepAwakeMenuItem.swift`

---

## 1. Overview

사용자가 MacBook 덮개를 닫고도 백그라운드 작업(빌드/CI/원격 컴파일/장시간 스크립트)이 sleep 없이 계속 진행되도록 하는 **시스템 sleep 차단 토글**. macOS 표준 클램쉘 모드(외부 디스플레이 자동 감지)와 다른, 외부 장치 없이도 동작하는 시나리오.

### 1.1 Problem

- `caffeinate -dims` (현재 Keep Awake 의 default flags) 는 IOPMAssertion 기반이라 lid close 시 macOS 가 강제하는 sleep trigger 를 막지 못함. Apple Silicon + macOS 14+ 부터 더 엄격.
- 사용자는 외부 디스플레이/키보드 없이도 lid 닫고 가방 안에서 빌드/원격 작업이 진행되길 원함.
- 메뉴바 한 클릭 + 자동 안전장치로 처리하고 싶음 (시스템 전역 설정 변경의 위험성을 사용자가 매번 인지/관리 어려움).

### 1.2 Goals

| # | Goal | 측정 |
|---|---|---|
| G1 | lid close 후에도 sleep 없이 작업 진행 | 토글 ON 후 lid 닫고 CPU 작업 5분+ 진행 (manual) |
| G2 | 4가지 자동 해제 트리거로 위험 완화 | timer 만료 / AC 분리 / lid open / muxbar 종료 모두 OFF 도달 |
| G3 | Apple Developer Program 비용 0 | ad-hoc 사인 (`codesign --sign -`) 만으로 동작 |
| G4 | Keep Awake 와 독립 운용 | 두 토글 각자 ON/OFF, 메뉴바 아이콘으로 상태 구분 |

### 1.3 Non-Goals

- macOS 표준 클램쉘 모드(외부 디스플레이 연결 시) 강제 — OS 자동 처리, 추가 코드 불필요
- Privileged helper tool (`SMAppService`) — Apple Developer Program ($99/y) 비용 발생, 후순위
- 디스플레이 ON 유지 — lid close 시 디스플레이 OFF 는 그대로 둠 (`-d` 플래그 제외)
- ON 상태 persist — 앱 재시작 시 자동 복원 X (안전한 기본값)

---

## 2. Architecture

```
┌──────────────────────────────────────────────────┐
│ MuxBarApp                                        │
│  ┌─────────────┐  ┌──────────────────────────┐   │
│  │ KeepAwake   │  │ ClosedLidMenuItem        │   │
│  │ (existing)  │  │ - 기간 popover            │   │
│  └─────┬───────┘  │ - 카운트다운 표시          │   │
│        │          └─────┬────────────────────┘   │
│        ▼                ▼                        │
│  ┌─────────────┐  ┌──────────────────────────┐   │
│  │ AwakeStore  │  │ ClosedLidStore           │   │
│  │ (existing)  │  │ - 상태/만료 timer         │   │
│  └─────────────┘  │ - 자동해제 트리거 구독     │   │
│                   └─────┬────────────────────┘   │
│                         ▼                        │
│                   ┌──────────────────────────┐   │
│                   │ PowerControl             │   │
│                   │ - AppleScript admin      │   │
│                   │ - pmset disablesleep 0/1 │   │
│                   └──────────────────────────┘   │
└──────────────────────────────────────────────────┘
```

`ClosedLidStore` 가 toggle 진입점. `PowerControl` 이 sudo 호출 wrapper. UI 와 도메인은 분리.

---

## 3. Components

### 3.1 `PowerControl` (Core)

`Sources/Core/PowerControl.swift`. AppleScript 통한 sudo 명령 wrapper.

```swift
public enum PowerControl {
    public enum Error: Swift.Error {
        case userCancelled
        case scriptFailed(String)
        case commandFailed(exitCode: Int32, stderr: String)
    }

    public static func disableSystemSleep() async throws
    public static func enableSystemSleep() async throws
}
```

- `NSAppleScript.executeAndReturnError(_:)` 호출. AppleScript: `do shell script "pmset -a disablesleep N" with administrator privileges`.
- 실행은 `MainActor` 보장 (AppleScript 제약). 호출 측은 `await` 로 비동기 인터페이스.
- 사용자 prompt cancel 시 `Error.userCancelled` throw → 호출 측이 state 변경 안 함.
- 5분 securityagent cache 는 OS 가 자동 처리 — 별도 코드 없음.

### 3.2 `ClosedLidStore` (Core)

`Sources/Core/ClosedLidStore.swift`. `@MainActor ObservableObject`.

```swift
@MainActor
public final class ClosedLidStore: ObservableObject {
    public enum State: Equatable {
        case off
        case on(expiresAt: Date?)  // nil → infinite
    }

    @Published public private(set) var state: State = .off
    @Published public private(set) var isToggling: Bool = false

    public func turnOn(duration: Duration?, sessionProvider: any SessionProvider) async
    public func forceOff(sessionProvider: any SessionProvider) async  // idempotent
}
```

- `turnOn`: `PowerControl.disableSystemSleep()` → 성공 시 `_muxbar-closed-lid` tmux 세션에 `caffeinate -is` 시작 → timer/observer 부착.
- `forceOff`: idempotent. 이미 OFF 면 no-op. 모든 자동해제 트리거가 호출.
- 자동해제 구독:
  - **Timer**: `Task.sleep` based, expiresAt 까지 대기 후 `forceOff`. cancel 가능.
  - **AC 분리**: `IOPSNotificationCreateRunLoopSource` (IOKit) 또는 `NSWorkspace.shared.notificationCenter` 의 power notification.
  - **Lid open**: IOKit `IOServiceMatching("AppleClamshellState")` + `IOServiceAddInterestNotification`. lid 가 open 으로 transition 시 `forceOff`.

### 3.3 `ClosedLidMenuItem` (Features)

`Sources/Features/ClosedLid/ClosedLidMenuItem.swift`. SwiftUI View.

- OFF 상태: `🔒 Closed-lid mode    OFF` 한 줄
- 탭 → 기간 popover: `30m` / `1h` / `4h` / `8h` / `∞` 선택 (또는 ESC 로 cancel)
- ON 상태: `🔒 Closed-lid mode    ON · 3:47:12`. 다시 탭하면 즉시 OFF (popover 없음)
- 카운트다운: 1초 timer 로 라벨 재계산. Combine `Timer.publish(every: 1, on: .main, in: .common)`.
- 색상: ON 시 빨간 강조 (Keep Awake 의 오렌지와 구분).

### 3.4 `MenuBarIcon` 확장

기존 `Sources/Features/MenuBarIcon/MenuBarIcon.swift` 변경:

- `awake` ON 만일 때: 오렌지 cup (현재 동작 유지)
- `closedLid` ON 일 때: **빨간 🔒** (closed-lid 우선, awake 동시 ON 여부와 무관)
- 둘 다 OFF: 기본 회색 cup

### 3.5 `AppDelegate` 통합

`Sources/MuxBarApp/MuxBarAppDelegate.swift` 확장:

- `applicationShouldTerminate(_:)` 에서 closed-lid 가 ON 이면 `.terminateLater` 반환, 비동기로 `forceOff` 진행, 완료 후 `NSApplication.shared.reply(toApplicationShouldTerminate: true)`.
- OFF 상태면 `.terminateNow` 즉시 반환 (현재 동작).
- 보장: muxbar 어떤 경로로 종료돼도 `pmset disablesleep 0` 복원.

---

## 4. Data Flow

### 4.1 ON 흐름

```
User tap → popover 열림
   ↓ 기간 선택
ClosedLidStore.turnOn(duration:)
   ↓
PowerControl.disableSystemSleep()
   ↓ AppleScript admin (GUI password / Touch ID)
   │   ├─ cancel/fail → throw → state 변화 없음 (revert)
   │   └─ ok ↓
sessionProvider.createSession("_muxbar-closed-lid", "caffeinate -is")
   ↓
state = .on(expiresAt: now + duration)
   ↓
timer + IOKit observers 부착
   ↓
UI 반영 (메뉴, 아이콘)
```

### 4.2 OFF 흐름

```
trigger (timer / AC / lid / quit / 사용자 toggle)
   ↓
ClosedLidStore.forceOff()  // idempotent
   ↓
PowerControl.enableSystemSleep()  // 5분 내면 prompt 없음
   ↓
sessionProvider.kill("_muxbar-closed-lid")
   ↓
timer/observer 해제 → state = .off
   ↓
UI 원복
```

---

## 5. Permission Flow

- AppleScript `do shell script "..." with administrator privileges` → macOS securityagent
- 첫 호출: GUI password prompt (Touch ID 활성 사용자는 Touch ID)
- 5분 cache: 같은 process 내에서 5분 안에 다시 호출하면 prompt 없이 통과 (Apple 표준)
- ON → 즉시 OFF 시: prompt 1번만
- ON 1시간 후 OFF 시: prompt 다시 1번 (cache 만료)
- cancel 시: `userCancelled` throw, state 변화 없음

---

## 6. Error Handling

| 시나리오 | 처리 |
|---|---|
| AppleScript user cancel (ON 시) | `Error.userCancelled` throw → state 안 바뀜, warning log |
| `pmset` non-zero exit | `commandFailed` throw → revert, error log |
| `caffeinate` 세션 생성 실패 (ON 시) | pmset 은 성공했으니 state ON 유지, 메뉴에 "caffeinate fallback only" 경고 라벨 |
| `tmux kill` 실패 (OFF 시) | log only, `pmset 0` 은 진행 (sleep 회복이 우선) |
| 자동해제 트리거 동시 발동 (timer + AC 동시 등) | `forceOff` idempotent, OFF 도달 보장 |
| `applicationWillTerminate` cleanup 시간 부족 | `applicationShouldTerminate` → `.terminateLater` → 비동기 cleanup → reply |
| OFF 도중 사용자 prompt cancel | state ON 유지, 사용자에게 재시도 안내 (메뉴 라벨) |

---

## 7. State Indication

### 7.1 메뉴바 아이콘 (우선순위 순)

| Closed-lid | Keep Awake | 아이콘 |
|---|---|---|
| ON | * | 🔒 빨강 |
| OFF | ON | ☕ 오렌지 (현행) |
| OFF | OFF | ☕ 회색 (현행) |

### 7.2 메뉴 항목 라벨

```
🔒 Closed-lid mode    ON · 3:47:12
   sleep blocked (system-wide)
```

- 무한 모드: `ON · ∞`
- 카운트다운 1초 갱신 (메뉴 열려 있을 때만)
- caffeinate fallback 발생 시 보조 라벨 추가

---

## 8. Testing

### 8.1 Unit

- `PowerControlTests`:
  - AppleScript 명령 string 생성 (disable/enable)
  - 에러 매핑 (NSAppleScript error → `PowerControl.Error`)
- `ClosedLidStoreTests`:
  - `.off → .on(expiresAt:) → .off` 상태 전이
  - 다중 `forceOff` idempotency
  - timer expiration 시뮬레이션 (clock injection 또는 짧은 duration 사용)

### 8.2 Manual (sudo 필요로 CI 어려움)

- ON 후 lid close → 5분+ CPU 작업 진행 확인 (`top`, `pmset -g`)
- AC 분리 → 자동 OFF 확인 (`pmset -g | grep disablesleep` = 0)
- lid open → 자동 OFF 확인
- timer 만료 → 자동 OFF 확인
- muxbar quit → 자동 OFF 확인 (재실행 시 disablesleep 0 잔존 X)

---

## 9. Out of Scope

- Privileged helper tool (Apple Developer Program 가입 후 별 spec 으로 분리)
- 외부 디스플레이/키보드 detection (클램쉘 자동 모드는 OS 처리)
- 이전 세션 ON 상태 persist (안전한 default — 항상 OFF 시작)
- 디스플레이 ON 유지 (`caffeinate -d`) — 사용자 명시적으로 화면 꺼져도 OK
- 깜빡임/애니메이션 인디케이터 — 색상 + 카운트다운으로 충분
