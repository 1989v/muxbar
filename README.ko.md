# muxbar

**Language:** [English](README.md) | [한국어](README.ko.md)

> tmux 세션 관리 + caffeinate 토글을 메뉴바에서. macOS 네이티브 앱.

[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](LICENSE)
[![macOS 13+](https://img.shields.io/badge/macOS-13.0+-blue.svg)](https://www.apple.com/macos/)
[![Swift 5.9+](https://img.shields.io/badge/Swift-5.9+-orange.svg)](https://swift.org)

## 주요 기능

- **세션 리스트** — 활성 세션 전체를 메뉴바에서 확인. attached 우선, 그룹 내 생성일 최신순 정렬
- **Attach** — Terminal.app / iTerm2 / Warp / Alacritty / kitty 중 원하는 터미널에서 열기
- **Kill** — 메뉴에서 바로 세션 종료
- **라이브 프리뷰** — 세션 행 클릭 or "Preview" 로 최근 출력 미리보기 (SwiftTerm 으로 ANSI 렌더)
- **Keep Awake** — `caffeinate -dims` 를 `_muxbar-awake` 라는 tmux 세션으로 실행/토글. 외부에서 실행 중인 caffeinate (다른 tmux 세션이든 일반 프로세스든) 까지 감지하고 한 번에 종료.
- **템플릿** — 빌트인 + 사용자 YAML 템플릿. New Session 에서 선택
- **전역 단축키** — `⌘⇧A` Keep Awake 토글, `⌘⇧1` ~ `⌘⇧9` 로 상단 N번째 세션 attach
- **Open at Login** — `.app` 번들로 설치된 경우 macOS Login Item 등록 (Settings 하위)

## 메뉴바 아이콘

- 세션 0개: 빈 커피잔
- 활성 세션: 커피잔 + 세션 수 뱃지
- Keep Awake 활성: 김 나오는 커피잔 + 오렌지 톤

## 메뉴 구조

```
  ┌ ▣ muxbar                   ● ┐  ← 헤더 (이름 + 연결 상태 dot)
  ├──────────────────────────────┤
  │ ● api                1w  ⋯  │   ← attached (초록 dot)
  │    /Users                    │      cwd 는 서브텍스트
  ├──────────────────────────────┤
  │ ○ dev                2w  ⋯  │   ← detached
  │    /Users/kgd/msa            │
  ├──────────────────────────────┤
  │ ○ logs               1w  ⋯  │
  │    /var/log                  │
  ├──────────────────────────────┤
  │ ☕  Keep Awake          ON  │   ← 토글 (⌘⇧A)
  ├──────────────────────────────┤
  │ ⊞  New Session          ▸   │   ← 템플릿 서브메뉴
  ├──────────────────────────────┤
  │ ⚙  Settings             ▸   │   ← Open at Login 등
  ├──────────────────────────────┤
  │    Quit muxbar          ⌘Q  │
  └──────────────────────────────┘
```

- 세션 행은 attached(●) 먼저, 그다음 detached(○) — 각 그룹 내 최신순
- 5개 초과하면 리스트 내부 스크롤
- 행 우측 `⋯` 를 누르면 액션 메뉴 (Attach / Preview / Kill)
- 세션 이름 자체를 누르면 라이브 프리뷰 팝오버가 열림

## 요구사항

- macOS 13 (Ventura) 이상
- `tmux` (`brew install tmux`)

## 설치

### Homebrew (배포 후 제공)

```bash
brew install --cask 1989v/tap/muxbar
```

### 소스에서 직접 빌드 (Xcode 불필요)

Command Line Tools + Swift 5.9+ 만 있으면 빌드 가능.

```bash
git clone https://github.com/1989v/muxbar.git
cd muxbar

./build.sh           # Release 빌드 + .app 번들 생성
./build.sh open      # 빌드 + 즉시 실행
./build.sh install   # 빌드 + /Applications 로 복사
```

`build.sh` 동작:
1. `swift build -c release`
2. `muxbar.app/Contents/{MacOS, Info.plist}` 구조 생성
3. Ad-hoc codesign (`codesign --sign -`)
4. quarantine 속성 제거

### 수동 다운로드 (.dmg, 배포 후)

1. [Releases](https://github.com/1989v/muxbar/releases) 에서 `.dmg` 다운로드
2. `muxbar.app` 을 Applications 로 드래그
3. **첫 실행**: 우클릭 → 열기 (ad-hoc 서명이라 Gatekeeper 우회 필요)

## 개발

소스에서 바로 실행 (일부 기능은 unbundled 모드에서 제한됨 — 아래 표 참조):

```bash
swift build
swift run muxbar
```

테스트 (XCTest 프레임워크 필요, Xcode 설치 시):

```bash
swift test
```

## 실행 모드별 기능 차이

| 기능 | `swift run` (unbundled) | `.app` 번들 |
|---|---|---|
| 세션 리스트 / Attach / Kill / Preview | ✅ | ✅ |
| Keep Awake / 템플릿 / 단축키 | ✅ | ✅ |
| Open at Login | ⚠ (Settings 에 표시만, 비활성) | ✅ |
| 시스템 알림 | ❌ | ✅ |

`.app` 번들이 필요한 기능 (Open at Login, 알림) 은 unbundled 실행 시 자연스럽게 비활성 처리됨 — 메뉴에서는 항목이 보이되 토글이 잠겨 있음.

## 키보드 단축키

| 단축키 | 동작 |
|---|---|
| `⌘⇧A` | Keep Awake 토글 |
| `⌘⇧1` ~ `⌘⇧9` | 메뉴상 N번째 세션 attach |

## 사용자 템플릿

YAML 파일을 `~/Library/Application Support/muxbar/Templates/` 에 두면 됨:

```yaml
name: MyDev
description: My dev setup
sessionNameHint: mydev
windows:
  - name: edit
    command: nvim .
    cwd: ~
  - name: run
    command: npm run dev
  - name: logs
    command: tail -f logs/app.log
```

- 파일명이 `_` 로 시작하면 로더가 무시 (`_example.yaml` 같은 참고용 파일 용도)
- 메뉴에서 reload: **New Session → Reload Templates**
- 폴더 열기: **New Session → Edit Templates…**

## 설계 & 문서

- [v0.1 디자인 스펙](docs/specs/2026-04-17-v0.1-design.md)
- [구현 플랜](docs/README.md)
- [아키텍처 결정 기록 (ADRs)](docs/adr)

## 라이선스

[MIT](LICENSE) © 2026 kgd
