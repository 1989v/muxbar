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
