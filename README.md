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

### Homebrew (권장, 배포 후)

```bash
brew install --cask 1989v/tap/muxbar
```

### 소스에서 직접 빌드 (Xcode 불필요)

CommandLineTools + Swift 5.9+ 만 있으면 .app 번들 생성 가능.

```bash
git clone https://github.com/1989v/muxbar.git
cd muxbar

# Release 빌드 + .app 번들 생성
./build.sh

# 곧바로 실행
./build.sh open

# /Applications 로 복사 (Login Item / 알림 기능 위해 권장)
./build.sh install
open /Applications/muxbar.app
```

스크립트가 하는 일:
1. `swift build -c release`
2. `muxbar.app/Contents/{MacOS, Info.plist}` 구조 생성
3. Ad-hoc codesign (`codesign --sign -`) 로 Gatekeeper 통과
4. quarantine 속성 제거

### 수동 다운로드 (배포 후)

1. [Releases](https://github.com/1989v/muxbar/releases) 에서 `.dmg` 다운로드
2. muxbar.app 을 Applications 로 드래그
3. **첫 실행**: 우클릭 → 열기 (ad-hoc 서명 우회)

## 개발

```bash
# 디버그 빌드 실행 (일부 기능 제한: 알림/LoginItem 은 unbundled 에서 비활성)
swift build
swift run muxbar
```

테스트 (Xcode 필요 — XCTest 프레임워크):
```bash
swift test
```

## 실행 모드별 기능 차이

| 기능 | `swift run` (unbundled) | `./build.sh` 로 생성한 .app |
|------|---|---|
| 세션 리스트 / Attach / Kill / Preview | ✅ | ✅ |
| Keep Awake / HotKeys / Templates | ✅ | ✅ |
| Login Item (시작 시 자동 실행) | ❌ (메뉴 숨김) | ✅ |
| UserNotification (세션 종료 알림) | ❌ | ✅ |

## 문서

- [v0.1 Design](docs/specs/2026-04-17-v0.1-design.md)
- [Plans](docs/README.md)

## 라이선스

MIT © 2026 kgd
