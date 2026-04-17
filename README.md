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
