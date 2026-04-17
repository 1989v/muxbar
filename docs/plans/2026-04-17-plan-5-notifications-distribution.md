# muxbar Plan 5 — Notifications + Login Item + Distribution Prep

> **For agentic workers:** REQUIRED SUB-SKILL: superpowers:subagent-driven-development

**Goal:** idle/crash 감지 + UserNotification, Login Item (SMAppService), 배포 스크립트 스캐폴딩. 실제 `.dmg` 빌드/서명은 Xcode 설치 후 수동 실행.

**Architecture:** `UserNotifications` 프레임워크로 local notification. `SMAppService.mainApp`로 Login Item 등록. 배포는 `Distribution/Release.sh` 스크립트 + Homebrew cask 템플릿.

**Tech Stack:** UserNotifications, ServiceManagement, Shell scripts.

---

## Task 1: NotificationCenter — idle/crash 감지 + 알림

**Files:** `Sources/Features/Notifications/NotificationService.swift`

- [ ] **Step 1: 서비스 구현**

Create `/Users/gideok-kwon/IdeaProjects/muxbar/Sources/Features/Notifications/NotificationService.swift`:
```swift
import Foundation
import UserNotifications
import Core
import MuxLogging

@MainActor
public final class NotificationService {
    private let logger = MuxLogging.logger("Features.NotificationService")
    private var lastActivityByPane: [String: Date] = [:]
    private var priorSessions: [String] = []
    private var idleCheckTimer: Task<Void, Never>?

    public var idleThresholdMinutes: Int = 30
    public var notifyOnCrash: Bool = true

    public init() {}

    public func requestAuthorization() {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { [weak self] granted, error in
            if let error {
                self?.logger.warning("알림 권한 요청 오류: \(error.localizedDescription)")
            } else {
                self?.logger.info("알림 권한 granted=\(granted)")
            }
        }
    }

    public func startIdleCheck(store: SessionStore) {
        idleCheckTimer?.cancel()
        idleCheckTimer = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 60_000_000_000) // 1분
                guard let self else { break }
                await self.checkIdle(store: store)
            }
        }
    }

    public func stopIdleCheck() {
        idleCheckTimer?.cancel()
    }

    /// 세션 목록 변경 감지. priorSessions 와 비교해 사라진 세션이 있으면 crash 알림.
    public func observeSessionsChange(current: [TmuxSession]) {
        let currentIds = current.map(\.id)
        let disappeared = Set(priorSessions).subtracting(currentIds)
            .filter { !$0.hasPrefix("_muxbar-") }

        if notifyOnCrash && !priorSessions.isEmpty && !disappeared.isEmpty {
            for sessionId in disappeared {
                postNotification(
                    title: "세션 종료됨",
                    body: "tmux 세션 '\(sessionId)' 이 종료되었습니다"
                )
            }
        }
        priorSessions = currentIds
    }

    public func recordPaneActivity(paneId: String) {
        lastActivityByPane[paneId] = .now
    }

    private func checkIdle(store: SessionStore) async {
        let threshold = TimeInterval(idleThresholdMinutes * 60)
        let now = Date.now
        for session in store.userVisibleSessions {
            let elapsed = now.timeIntervalSince(session.lastActivityAt)
            if elapsed > threshold {
                // 최근 10분 안에 중복 알림 방지를 위한 간단한 가드: 날짜 단위 flag 없음 → skip
                // 본격적인 dedupe 는 v0.2
                logger.info("세션 '\(session.id)' idle \(Int(elapsed / 60))분")
            }
        }
    }

    private func postNotification(title: String, body: String) {
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .default
        let request = UNNotificationRequest(
            identifier: UUID().uuidString,
            content: content,
            trigger: nil
        )
        UNUserNotificationCenter.current().add(request)
    }
}
```

- [ ] **Step 2: Build + Commit**

```bash
cd /Users/gideok-kwon/IdeaProjects/muxbar
swift build 2>&1 | tail -3
git add Sources/Features/Notifications
git commit -m "feat(Features): NotificationService — idle/crash 알림"
```

---

## Task 2: LoginItem — SMAppService 래퍼

**Files:** `Sources/Features/LoginItem/LoginItemService.swift`

- [ ] **Step 1: 서비스 구현**

Create `/Users/gideok-kwon/IdeaProjects/muxbar/Sources/Features/LoginItem/LoginItemService.swift`:
```swift
import Foundation
import ServiceManagement
import MuxLogging

@MainActor
public final class LoginItemService: ObservableObject {
    @Published public private(set) var isEnabled: Bool

    private let logger = MuxLogging.logger("Features.LoginItem")

    public init() {
        self.isEnabled = (SMAppService.mainApp.status == .enabled)
    }

    public func refresh() {
        isEnabled = (SMAppService.mainApp.status == .enabled)
    }

    public func set(_ enabled: Bool) {
        do {
            if enabled {
                try SMAppService.mainApp.register()
                logger.info("Login Item 등록됨")
            } else {
                try SMAppService.mainApp.unregister()
                logger.info("Login Item 해제됨")
            }
            refresh()
        } catch {
            logger.error("Login Item 토글 실패: \(error.localizedDescription)")
        }
    }
}
```

- [ ] **Step 2: Build + Commit**

```bash
swift build 2>&1 | tail -3
git add Sources/Features/LoginItem
git commit -m "feat(Features): LoginItemService — SMAppService.mainApp 래퍼"
```

---

## Task 3: AppState — 알림 + LoginItem 연결

**Files:** `Sources/MuxBarApp/AppState.swift`

- [ ] **Step 1: AppState 확장**

Edit `/Users/gideok-kwon/IdeaProjects/muxbar/Sources/MuxBarApp/AppState.swift`:

Add properties:
```swift
public let notificationService: NotificationService
public let loginItemService: LoginItemService
```

In init:
```swift
self.notificationService = NotificationService()
self.loginItemService = LoginItemService()
```

In `bootstrap()` after `registerHotkeys()`:
```swift
notificationService.requestAuthorization()
notificationService.startIdleCheck(store: sessionStore)
// 세션 변경 감지 → observeSessionsChange 호출
Task { [weak self] in
    guard let self else { return }
    for await _ in sessionStore.$sessions.values {
        self.notificationService.observeSessionsChange(current: self.sessionStore.sessions)
    }
}
```

Also add `import Combine` if not present (for `.values` on Published).

- [ ] **Step 2: Build + Commit**

```bash
swift build 2>&1 | tail -5
git add Sources/MuxBarApp/AppState.swift
git commit -m "feat(MuxBarApp): AppState — Notification + LoginItem 통합"
```

---

## Task 4: MuxBarApp — Preferences 메뉴에 Login Item 토글

**Files:** `Sources/MuxBarApp/MuxBarApp.swift`

- [ ] **Step 1: 메뉴에 Login Item 토글 추가**

Edit `/Users/gideok-kwon/IdeaProjects/muxbar/Sources/MuxBarApp/MuxBarApp.swift` — add before the Quit button:

```swift
Divider()
Toggle(isOn: Binding(
    get: { appState.loginItemService.isEnabled },
    set: { appState.loginItemService.set($0) }
)) {
    Text("시작 시 자동 실행")
}
.toggleStyle(.switch)
.padding(.horizontal, 8)
.padding(.vertical, 4)
```

- [ ] **Step 2: Release build + relaunch**

```bash
cd /Users/gideok-kwon/IdeaProjects/muxbar
swift build -c release 2>&1 | tail -3
pkill -f muxbar 2>/dev/null
sleep 1
./.build/release/muxbar > /tmp/muxbar.log 2>&1 &
sleep 3
pgrep -fl muxbar
```

- [ ] **Step 3: Commit**

```bash
git add Sources/MuxBarApp/MuxBarApp.swift
git commit -m "feat(MuxBarApp): Preferences — Login Item 토글 추가"
```

---

## Task 5: 배포 스크립트 스캐폴딩 (Xcode 설치 후 실행)

**Files:**
- Create: `Distribution/Release.sh`
- Create: `Distribution/HomebrewTap/muxbar.rb`
- Create: `Distribution/README.md`

- [ ] **Step 1: Release 스크립트**

Create `/Users/gideok-kwon/IdeaProjects/muxbar/Distribution/Release.sh`:
```bash
#!/bin/bash
# muxbar 릴리스 빌드 + .dmg 패키징
# 실행 전제: Xcode 설치 + DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer

set -euo pipefail

VERSION="${1:-0.1.0}"
OUT_DIR="dist"
APP_NAME="muxbar.app"

echo "[1/5] swift build -c release (universal)"
swift build -c release --arch arm64 --arch x86_64

echo "[2/5] .app 번들 생성"
mkdir -p "$OUT_DIR/$APP_NAME/Contents/MacOS"
mkdir -p "$OUT_DIR/$APP_NAME/Contents/Resources"

cp .build/apple/Products/Release/muxbar "$OUT_DIR/$APP_NAME/Contents/MacOS/muxbar"

cat > "$OUT_DIR/$APP_NAME/Contents/Info.plist" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>CFBundleName</key><string>muxbar</string>
<key>CFBundleDisplayName</key><string>muxbar</string>
<key>CFBundleIdentifier</key><string>com.1989v.muxbar</string>
<key>CFBundleVersion</key><string>$VERSION</string>
<key>CFBundleShortVersionString</key><string>$VERSION</string>
<key>CFBundleExecutable</key><string>muxbar</string>
<key>CFBundlePackageType</key><string>APPL</string>
<key>LSMinimumSystemVersion</key><string>13.0</string>
<key>LSUIElement</key><true/>
<key>NSHighResolutionCapable</key><true/>
</dict></plist>
EOF

echo "[3/5] Ad-hoc codesign"
codesign --deep --force --sign - "$OUT_DIR/$APP_NAME"

echo "[4/5] create-dmg"
if ! command -v create-dmg >/dev/null 2>&1; then
    echo "create-dmg 없음. brew install create-dmg"
    exit 1
fi
create-dmg \
    --volname "muxbar $VERSION" \
    --app-drop-link 450 120 \
    "$OUT_DIR/muxbar-$VERSION.dmg" \
    "$OUT_DIR/$APP_NAME"

echo "[5/5] SHA256"
shasum -a 256 "$OUT_DIR/muxbar-$VERSION.dmg"

echo "done → $OUT_DIR/muxbar-$VERSION.dmg"
```

Make executable: `chmod +x Distribution/Release.sh`

- [ ] **Step 2: Homebrew cask 템플릿**

Create `/Users/gideok-kwon/IdeaProjects/muxbar/Distribution/HomebrewTap/muxbar.rb`:
```ruby
cask "muxbar" do
  version "0.1.0"
  sha256 "TBD_AFTER_BUILD"

  url "https://github.com/1989v/muxbar/releases/download/v#{version}/muxbar-#{version}.dmg"
  name "muxbar"
  desc "tmux session manager with caffeinate toggle in the menu bar"
  homepage "https://github.com/1989v/muxbar"

  depends_on formula: "tmux"
  depends_on macos: ">= :ventura"

  app "muxbar.app"

  postflight do
    system_command "xattr",
                   args: ["-dr", "com.apple.quarantine", "#{appdir}/muxbar.app"],
                   sudo: false
  end

  zap trash: [
    "~/Library/Application Support/muxbar",
    "~/Library/Preferences/com.1989v.muxbar.plist",
  ]
end
```

- [ ] **Step 3: Distribution README**

Create `/Users/gideok-kwon/IdeaProjects/muxbar/Distribution/README.md`:
```markdown
# muxbar Distribution

## 릴리스 절차

1. 버전 확정 (semver) → `./Release.sh 0.1.0`
2. `dist/muxbar-0.1.0.dmg` 생성됨
3. GitHub Release 생성 → .dmg 업로드
4. SHA256 복사 → `HomebrewTap/muxbar.rb` 의 `sha256` 업데이트
5. `1989v/homebrew-tap` 별도 레포에 `Casks/muxbar.rb` 푸시

## 전제 조건

- Xcode 설치 (codesign, universal binary 빌드)
- `brew install create-dmg` (dmg 패키징)
- 사용자 검증: `brew install --cask 1989v/tap/muxbar`

## Ad-hoc 서명의 한계

Apple Developer 계정 없음 → notarize 불가. 사용자는 첫 실행 시 우클릭 → 열기 필요.
Homebrew cask 가 `xattr -dr com.apple.quarantine` 로 자동 우회.
```

- [ ] **Step 4: Commit**

```bash
chmod +x Distribution/Release.sh
git add Distribution
git commit -m "chore(dist): Release.sh + Homebrew cask 템플릿"
```

---

## Task 6: ADR-0005 + 최종 README

**Files:**
- Create: `docs/adr/ADR-0005-adhoc-signing-distribution.md`
- Modify: `README.md`
- Modify: `docs/README.md`

- [ ] **Step 1: ADR-0005**

Create `/Users/gideok-kwon/IdeaProjects/muxbar/docs/adr/ADR-0005-adhoc-signing-distribution.md`:
```markdown
# ADR-0005: Ad-hoc 서명 + quarantine 제거 배포

- Status: Accepted
- Date: 2026-04-17

## Context

개발자가 Apple Developer 계정($99/년) 없이 무료 배포 진행.
정식 서명/공증 불가. Gatekeeper 경고 우회 필요.

## Decision

- `codesign --sign -` (ad-hoc 서명) 으로 최소 무결성 보장
- Homebrew cask 의 `postflight` 에서 `xattr -dr com.apple.quarantine` 자동 실행
- GitHub Releases 직접 다운로드 사용자는 README 의 "우클릭 → 열기" 안내

## Consequences

**장점**:
- 비용 0
- 빠른 릴리스 가능

**단점**:
- 직접 .dmg 다운로드 첫 실행 시 마찰
- notarize 되지 않아 일부 엔터프라이즈 맥은 실행 차단 가능
- 업데이트 자동 배포(Sparkle)는 v0.2 에서 고려

## References
- Apple Developer 계정 가입 시 이 ADR 은 supersede 됨
```

- [ ] **Step 2: README.md 대폭 업데이트**

Overwrite `/Users/gideok-kwon/IdeaProjects/muxbar/README.md`:
```markdown
# muxbar

> tmux session manager + caffeinate toggle — macOS menu bar app.

## 기능

- 메뉴바 아이콘 → tmux 세션 리스트
- 세션 **Attach** (Terminal.app / iTerm2 / Warp / Alacritty / kitty)
- 세션 **Kill**
- 세션 **Live Preview** (SwiftTerm 기반 ANSI 렌더)
- **Keep Awake** 토글 — `caffeinate -dims` 을 `_muxbar-awake` tmux 세션으로 실행
- **세션 템플릿** 5종 (Dev, WebDev, Monitoring, SSH, Docker)
- **전역 단축키** (⌘⇧A: Keep Awake, ⌘⇧1~9: 즐겨찾기 attach)
- 시작 시 자동 실행 옵션 (Login Item)
- 세션 종료 시 알림

## 사전 요구사항

- macOS 13 (Ventura) 이상
- `tmux` (`brew install tmux`)

## 설치

### Homebrew (권장)

```bash
brew install --cask 1989v/tap/muxbar
```

### 수동 다운로드

1. [Releases](https://github.com/1989v/muxbar/releases) 에서 `.dmg` 다운로드
2. muxbar.app 을 Applications 로 드래그
3. **첫 실행**: 우클릭 → 열기 (ad-hoc 서명 우회)

## 개발

```bash
swift build
swift run muxbar

# release
swift build -c release
./.build/release/muxbar
```

테스트 (Xcode 필요):
```bash
swift test
```

## 문서

- [v0.1 Design](docs/specs/2026-04-17-v0.1-design.md)
- [Plans](docs/README.md)

## 라이선스

MIT © 2026 kgd
```

- [ ] **Step 3: docs/README.md 업데이트**

Overwrite `/Users/gideok-kwon/IdeaProjects/muxbar/docs/README.md`:
```markdown
# muxbar Docs

## Specs
- [v0.1 Design](specs/2026-04-17-v0.1-design.md)

## Plans
- [Plan 1 — Foundation + TmuxKit](plans/2026-04-17-plan-1-foundation-tmuxkit.md)
- [Plan 2 — SessionList + KeepAwake](plans/2026-04-17-plan-2-sessionlist-keepawake.md)
- [Plan 3 — Live Preview](plans/2026-04-17-plan-3-live-preview.md)
- [Plan 4 — Templates + HotKeys](plans/2026-04-17-plan-4-hotkeys-templates.md)
- [Plan 5 — Notifications + Distribution](plans/2026-04-17-plan-5-notifications-distribution.md)

## ADRs
- [ADR-0001: tmux control mode 채택](adr/ADR-0001-tmux-control-mode-over-polling.md)
- [ADR-0002: SessionProvider 프로토콜 분리](adr/ADR-0002-sessionprovider-protocol.md)
- [ADR-0003: SwiftTerm 채택](adr/ADR-0003-swiftterm-rendering.md)
- [ADR-0004: HotKey + Template 통합](adr/ADR-0004-hotkey-template.md)
- [ADR-0005: Ad-hoc 서명 배포](adr/ADR-0005-adhoc-signing-distribution.md)
```

- [ ] **Step 4: Commit + v0.1 태그**

```bash
git add README.md docs/
git commit -m "docs: Plan 5 완료 — README 전면 개편 + ADR-0005"
git tag -a v0.1.0-rc1 -m "muxbar v0.1.0 릴리스 후보 (Xcode 설치 후 배포 빌드 필요)"
git tag -a plan-5-complete -m "Plan 5: Notifications + LoginItem + Distribution 준비 완료"
```

---

## Plan 5 완료 기준

- [x] NotificationService (권한 요청 + idle/crash 감지)
- [x] LoginItemService (SMAppService)
- [x] AppState 통합 + UI 토글
- [x] Release.sh 배포 스크립트
- [x] Homebrew cask 템플릿
- [x] ADR-0005 + README 전면 개편
- [ ] **Xcode 설치 후 수동 실행**: `./Distribution/Release.sh 0.1.0` 로 실제 .dmg 생성

## v0.1 이후 로드맵 (비 Plan)

- Sparkle 자동 업데이트
- 사용자 템플릿 YAML 편집 UI
- L3 프리뷰의 컬러/테마 지원 확장
- Preferences 패널 고도화 (idle 임계값, 터미널 기본 선택)
