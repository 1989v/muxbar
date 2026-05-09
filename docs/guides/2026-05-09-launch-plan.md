# muxbar 런치 플랜 — v0.1 + Closed-lid mode

> 한 줄 핵심: 메뉴바에서 tmux 세션을 관리하면서 동시에 **노트북 가방에 넣고도 작업이 진행되는 closed-lid mode** 를 한 클릭으로 켤 수 있다 — 외부 모니터·키보드·전원 어댑터 없이도.

이 문서는 muxbar 를 한국어/영어 사용자 모두에게 알리기 위한 채널·메시지·타임라인 가이드. 실제 실행은 사용자가 직접 (자동 포스팅 X). 각 채널별로 어디에, 무엇을, 어떻게 올릴지의 청사진.

---

## 1. Positioning

**한 문장 (영문):**
> muxbar — manage tmux from your menu bar, and run your laptop with the lid closed (no external display required).

**한 문장 (국문):**
> muxbar — 메뉴바에서 tmux 세션 관리, 그리고 외부 모니터 없이 노트북 덮개 닫고도 작업이 계속.

**무엇이 아닌가 (선 긋기):**
- iTerm2 / Warp / Alacritty 같은 **터미널 에뮬레이터**가 아님 — 그 위에서 도는 tmux 의 **컨트롤러**.
- KeepingYouAwake / Amphetamine 같은 일반 caffeinate 토글이 아님 — 일반 caffeinate 는 lid close 시 sleep 을 못 막음. closed-lid mode 는 `pmset disablesleep` 으로 그걸 푼다.

---

## 2. 차별화 (USP)

기능 비교에서 **closed-lid mode 가 단독 핵심**. tmux 메뉴바 앱은 이미 몇 개 있지만 closed-lid 까지 통합한 건 (찾는 한도에선) 없음. 일반 caffeinate 앱들도 외부 모니터 없는 lid-close 시나리오는 못 다룬다.

| 도구 | 메뉴바 tmux 관리 | Lid-close 작업 (외부 모니터 없이) |
|---|---|---|
| muxbar | ✅ | ✅ (closed-lid mode) |
| Tmux Cheatsheet 류 / cheat-only 메뉴바 | △ | ❌ |
| KeepingYouAwake / Amphetamine | ❌ | ❌ (lid close 시 sleep) |
| Apple 정식 클램쉘 모드 | ❌ | ❌ (외부 모니터 필수) |
| Amphetamine Enhancer / NoSleep | ❌ | ⚠ (private API 트릭, OS 업데이트 취약) |

→ 포스팅에선 **두 기능의 결합**을 강조 (단독 기능들은 이미 있으니 differentiation 약함).

---

## 3. 타겟 audience

| 세그먼트 | 어디서 만나는가 | 후크 메시지 |
|---|---|---|
| **macOS + tmux 개발자** | r/tmux, Hacker News, awesome-tmux | "Stop alt-tabbing into a terminal just to run `tmux ls`" |
| **노트북 들고 다니는 백엔드/DevOps** | r/devops, r/sysadmin | "Run your build / CI in your bag" |
| **국내 개발자 (특히 macOS+tmux 사용자)** | GeekNews, OKKY, Hacker Korea (KFTC), 개발자 트위터 | "외부 모니터 없이 노트북 덮어두고 작업" |
| **OSS / Mac 메뉴바 앱 컬렉터** | awesome-mac, awesome-macos, MacUpdate, mac.getutm.app 류 | "menu bar agent for tmux + insomnia" |

---

## 4. 채널 우선순위

비용 대비 도달률 순. 굵은 글자가 1순위.

### 1순위 — 자가 호스팅 가능 (매몰 비용 0)

- **GitHub Topics + Description + Social preview** — 이미 `docs/guides/github-discoverability.md` 가이드대로 적용된 상태인지 확인 필요.
- **README** — closed-lid mode 섹션을 별도 헤딩으로 노출 (이번 정리에서 반영됨).
- **GitHub Releases** — v0.1 정식 릴리스 + `.dmg` 첨부 + Homebrew tap 등록.

### 2순위 — Awesome 리스트 PR (한 번 머지되면 영구 유입)

- [awesome-mac](https://github.com/jaywcjlove/awesome-mac) — Productivity 또는 Developer Tools 섹션
- [awesome-macos](https://github.com/iCHAIT/awesome-macOS) — Menu Bar 섹션
- [awesome-tmux](https://github.com/rothgar/awesome-tmux) — Tools 섹션
- [awesome-swift](https://github.com/matteocrippa/awesome-swift) — App 카테고리

PR 본문 템플릿: 1줄 설명 + alphabetical 위치 정확히 유지.

### 3순위 — 한 번 노출, 단기 spike 후 long tail

- **Hacker News (Show HN)** — closed-lid mode 를 핵심 후크로. Tuesday/Wednesday 오전 (US ET) 가장 활발.
- **r/macapps** — 새 macOS 앱 환영. "Show & Tell" flair.
- **r/tmux** — tmux 사용자 직접 타겟. 메뉴바 통합 측면 강조.
- **GeekNews (news.hada.io)** — 국내 개발자 다수 유입. closed-lid mode 가 한국어 사용자에게 새로운 단어라 호기심 후크.
- **OKKY** — 국내 개발자 커뮤니티. 자기 OSS 소개 카테고리 활용.
- **Product Hunt** — 캘린더 잡고 정식 런치 (아래 6번 참조).

### 4순위 — soft 노출

- 개인 X (Twitter) / Mastodon — closed-lid mode 데모 GIF 포함
- 개인 블로그 / Medium / dev.to — "Why I built X" 형식
- macOS YouTube 채널 (예: tipsmake, 9to5mac) DM

---

## 5. 포스팅 draft

### 5.1 Hacker News — Show HN

```
Title: Show HN: muxbar – tmux from your macOS menu bar, with a "lid-closed" mode

Body:
I built a menu bar app for two things I kept doing manually:

1. tmux ls → tmux a -t … in a terminal, dozens of times a day
2. Putting my laptop in a bag mid-build and praying it doesn't sleep

The first part is the standard menu bar list / attach / kill / live preview.
The interesting bit is the second: "Closed-lid mode" toggles `pmset -a
disablesleep 1` (kernel-level) plus `caffeinate -is`, with auto-off on AC
unplug, lid open, timer, or app quit. That means I can close the lid, drop
the laptop in a bag, and the build keeps going — no external display
required (which Apple's own clamshell mode insists on).

It uses an AppleScript admin prompt for the sudo `pmset` call, so there's
no privileged helper to install and no Apple Developer Program needed.
Ad-hoc signed, MIT, ~3.5kloc Swift / SwiftUI.

Repo: https://github.com/1989v/muxbar

Curious if anyone else relies on the same in-bag workflow, or if the
4-trigger auto-off (timer / AC / lid / quit) feels safe enough.
```

### 5.2 Reddit — r/macapps

```
Title: muxbar — menu bar app for tmux that also lets you close the lid and keep working

Body:
- Open source (MIT), macOS 13+, ad-hoc signed (no Apple Dev account)
- Standard tmux ops: list / attach / kill / live preview / templates
- Closed-lid mode: toggle prevents system sleep even with the lid down,
  no external monitor required. Auto-off on timer / AC unplug / lid open / quit.
- Combines `pmset -a disablesleep 1` + `caffeinate -is` via an AppleScript
  admin prompt — no helper installer.

[Screenshot]
[GitHub link]
```

### 5.3 Reddit — r/tmux

```
Title: I made a menu bar UI for tmux — list, attach, kill, live preview

Body (focus on tmux side, closed-lid as bonus):
After dozens of `tmux ls; tmux a -t …` cycles a day I built a menu bar
controller. Live preview uses tmux control mode (`tmux -C`) so it streams
%output in real time without re-attaching.

Bonus: it has a "closed-lid mode" toggle for keeping a session alive
while the laptop is in a bag.

[Screenshot of menu]
[Repo link]
```

### 5.4 GeekNews (news.hada.io)

```
제목: muxbar — 메뉴바 tmux 컨트롤러 + 노트북 덮고도 작업 계속

본문:
tmux 세션을 메뉴바에서 관리하는 macOS 네이티브 앱. 보통 메뉴바 caffeinate
앱이나 터미널 에뮬레이터들과 다른 점은 두 기능을 합친 것 — 그리고 핵심으로
"Closed-lid mode" 가 있어 외부 모니터 없이도 노트북 덮개 닫고 빌드/CI/원격
세션을 유지할 수 있음.

내부적으로 pmset -a disablesleep 1 + caffeinate -is 결합. AppleScript admin
prompt 라 helper daemon 없음, Apple Developer Program 멤버십 없이도 ad-hoc
signed 로 동작. 자동 해제 4 트리거 (타이머/AC분리/lid열림/종료) 로 시스템
전역 sleep 차단의 위험 완화.

기능:
- 세션 list / attach / kill / 라이브 프리뷰
- Keep Awake (caffeinate) 토글
- Closed-lid mode (이번 v0.1)
- YAML 템플릿
- 전역 단축키

Swift 5.9 / SwiftUI / MIT. macOS 13+.

GitHub: https://github.com/1989v/muxbar
```

### 5.5 Product Hunt (정식 런치)

- **태그**: Developer Tools, macOS, Productivity, Open Source
- **Tagline**: "Manage tmux from your menu bar — and keep working with the lid closed."
- **Topics**: macOS, Developer Tools, Open Source
- **Maker comment**:
  ```
  Hi PH 👋 maker here. muxbar grew out of two annoyances:
  (1) opening a terminal just to type `tmux ls`
  (2) Apple clamshell mode requiring an external monitor.
  
  closed-lid mode is the differentiator — it's the first menu bar app I'm
  aware of that combines tmux control with no-external-monitor lid-close
  insomnia. Auto-off triggers (timer / AC / lid / quit) cover the obvious
  battery-drain risk.
  
  Open source (MIT), macOS 13+, ad-hoc signed.
  ```
- **Hunt 시점**: Tuesday/Wednesday 오전 12:01 PT (Pacific Time, UTC-8/-7) 에 게시 = 한국 시간 오후 5시. PH 알고리즘이 첫 24시간 트래픽으로 ranking 결정.

### 5.6 awesome-* PR

- **Title 후보**: `Add muxbar — menu bar tmux controller + closed-lid mode`
- **본문**:
  ```
  Adds [muxbar](https://github.com/1989v/muxbar) under [section].
  
  - macOS 13+ menu bar app
  - tmux session list / attach / kill / live preview
  - Closed-lid mode (new): keeps system awake with lid closed, no external
    display required
  - MIT licensed, native Swift/SwiftUI
  ```
- 알파벳 순서 위치 확인. 이미 머지된 다른 항목 포맷 그대로 따라하기.

---

## 6. 타임라인

| 시점 | 작업 | 채널 |
|---|---|---|
| Day 0 (오늘) | README 정리 (closed-lid 섹션 확장) ✓<br>v0.1 release tag 준비 | — |
| Day 1 | `.dmg` notarize 또는 ad-hoc + SHA256 표기, GitHub Release 게시, Homebrew tap 1차 등록 | 자체 |
| Day 2 | awesome-mac / awesome-tmux / awesome-macos PR | 1순위 |
| Day 3 (Tue/Wed 오전 ET) | Show HN 게시, 동시에 r/macapps + r/tmux | 3순위 |
| Day 3 저녁 | GeekNews + OKKY 게시 (한국어) | 3순위 |
| Day 7 | 트래픽 / star / issue 모니터 → 응답 사이클 | — |
| Week 2 | Product Hunt 캘린더 잡고 정식 런치 | 3순위 |
| Week 3+ | 발견된 버그/요청 처리 후 v0.2 plan | — |

---

## 7. KPI / 측정

런치 첫 7일 기준 — 전부 GitHub native 지표라 별도 분석 도구 불필요.

| 지표 | 베이스라인 | 1주 목표 |
|---|---|---|
| GitHub Star | 현재 N개 | +50 |
| GitHub Issue 생성 | 0 | 5+ (피드백 신호) |
| Homebrew install 수 | 0 | 측정 불가 (tap 통계 제한) |
| Show HN 점수 | — | 첫 페이지 진입 (50+) 시도 |
| awesome-* PR 머지 | 0 | 2개 |

KPI 미달이어도 awesome-* PR 이 머지된 것만으로 long-tail SEO 자산 — 6개월 후도 유효.

---

## 8. 후속 — 다음 release 메시지

closed-lid mode 가 v0.1 의 핵심 differentiator 이므로 v0.2 부터는 무엇으로 갈지가 다음 주제. 아래는 가설:

- 시계열 카운트다운을 menu bar 아이콘에도 표시 (`🔒 0:47`)
- closed-lid 토글 시 시간 만료 자동 30 분 추가 옵션
- Privileged helper 옵션 (`SMAppService`) — Apple Developer 가입자에게 prompt 없이
- 네트워크 / GitHub Action runner 연동 — 빌드 큐 비면 자동 OFF

각각 별 spec 으로 분기.

---

## 부록 — 내부 체크리스트 (실제 런치 전)

- [ ] README.md / README.ko.md closed-lid 섹션 검수 (이번 PR)
- [ ] `docs/specs/2026-05-08-closed-lid-mode-design.md` 의 옵션 (`30m/1h/4h/8h/∞`) 코드와 일치
- [ ] `docs/assets/screenshots/menu.png` 갱신 — closed-lid 메뉴 항목 노출되게 새로 캡처
- [ ] `docs/assets/screenshots/closed-lid-popover.png` 신규 (시간 popover 모습)
- [ ] GitHub Release notes v0.1 — Features 섹션 + 다운로드 링크 + SHA256
- [ ] Homebrew tap (`1989v/homebrew-tap`) 의 `Casks/muxbar.rb` 갱신
- [ ] Social preview 이미지 (1280×640) — closed-lid 강조 카피
