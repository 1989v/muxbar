# GitHub Repo 발견성(Discoverability) 가이드

> muxbar 를 공개 배포하면서 실제로 적용한 체크리스트 모음. 다른 개인 OSS 프로젝트에도 그대로 재사용 가능.

목표: 레포 링크를 받은 사람이 1초 안에 무엇인지 파악하고, 키워드로 검색한 사람이 도달 가능하게 만든다.

---

## 전체 레이어

```
[Layer 1] 레포 자체 메타데이터   ← GitHub 검색 / Topic 페이지 유입
  ├ Topics          (태깅 = 카테고리 인덱싱)
  ├ Description     (한 줄 소개)
  └ Social preview  (링크 공유 카드)

[Layer 2] README 품질           ← 방문 직후 "그대로 써볼 만한가" 판단
  ├ Quick start / 설치          (복붙 한 덩어리)
  ├ 스크린샷 / 데모             (시각 정보)
  ├ 언어 스위처                 (글로벌 타겟 시)
  └ Badge (버전/라이선스/빌드)  (신뢰성)

[Layer 3] 외부 인덱스           ← 능동적 유입 경로 확보
  ├ Homebrew tap (cask)
  ├ awesome-* 리스트 PR
  ├ Product Hunt
  ├ Reddit (r/MacApps, r/tmux 등)
  └ Hacker News (Show HN)
```

---

## Layer 1. 레포 메타데이터

### 1-1. Topics — 레포 태깅

**용도**: GitHub 의 `topic:tmux` 같은 검색 필터와 [topic 페이지](https://github.com/topics/tmux) 에 레포 포함시킴. GitHub 검색 랭킹에 기여.

**개수 제한**: 최대 20개. 관련 없는 태그 남발하면 스팸 판정 → 오히려 역효과.

**좋은 topic 조건**:

| 카테고리 | 예시 (muxbar 기준) |
|---|---|
| 기술 스택 | `swift`, `swiftui`, `appkit` |
| 플랫폼 | `macos` |
| 도메인 | `menu-bar`, `menu-bar-app`, `tmux`, `caffeinate` |
| 통합 대상 | `homebrew-cask` |
| 넓은 카테고리 | `developer-tools` |

**피할 것**:
- 너무 일반적: `app`, `tool`, `utility` — 검색 유입 효과 미미
- 관련 없는 트렌드: `ai`, `web3` 등 무관하면 남용 금지

**명령**:
```bash
gh repo edit OWNER/REPO --add-topic tag1,tag2,tag3
gh repo view OWNER/REPO --json repositoryTopics -q '.repositoryTopics[].name'
```

### 1-2. Description — 한 줄 소개

**표시 위치**:
- 레포 메인 페이지 우측 About 사이드바
- 검색 결과 리스트
- Social preview 에 자동 포함 (이미지 없을 때)

**좋은 Description 공식**:
```
[핵심 정체성] — [주요 특징 1-3개 단어], [주요 특징 1-3개 단어], [특징 더].
```

**예시 (muxbar)**:
> Native macOS menu bar app for tmux session management — attach, live preview, Keep Awake (caffeinate detection), templates, global hotkeys.

- `Native macOS menu bar app` — 뭐인지 / 어디서 도는지 즉시 명시
- `tmux session management` — 핵심 도메인
- `attach, live preview, Keep Awake, templates, global hotkeys` — 주요 기능 나열 (검색 키워드 확보)

**명령**:
```bash
gh repo edit OWNER/REPO --description "..."
gh repo view OWNER/REPO --json description -q '.description'
```

### 1-3. Social preview — 링크 공유 카드

**용도**: Slack, Twitter, 메신저에 레포 URL 붙였을 때 뜨는 미리보기 카드의 이미지.

**제약**:
- **GitHub API 로 업로드 불가** — 웹 UI 전용
- 크기: 1280×640 px 권장
- 포맷: PNG / JPG

**업로드 경로**:
```
https://github.com/OWNER/REPO/settings#social-preview
```

**이미지 만들기 옵션**:

1. **socialify.git.ci** (추천) — 레포명/설명 자동으로 예쁘게 렌더
   ```
   https://socialify.git.ci/OWNER/REPO/image?font=JetBrains+Mono&pattern=Floating+Cogs&theme=Dark
   ```
   브라우저 방문 후 커스터마이즈 → 이미지 다운로드

2. **og-image generator** 직접 디자인
3. **README 상단 이미지** 로 대체 — Social preview 에 안 올려도 README 최상단 이미지가 링크 카드로 쓰임

**검증**:
```
https://opengraph.githubassets.com/1/OWNER/REPO
또는 https://www.opengraph.xyz/url/https%3A%2F%2Fgithub.com%2FOWNER%2FREPO
```
(업로드 후 캐시 갱신 30초 ~ 몇 분 소요)

---

## Layer 2. README 품질

### 2-1. Quick start 블록

방문자는 **스크롤 안 하려고 합니다**. 상단에 복붙 가능한 한 덩어리 명령:

```markdown
## Quick start

```bash
git clone https://github.com/OWNER/REPO.git
cd REPO
./install.sh  # 또는 build.sh / make / npm install / ...
```
```

### 2-2. 스크린샷 / 데모

- **GUI 앱**: 메뉴바/창 스크린샷 — `docs/assets/screenshot.png` 로 보관 후 README 에 embed
- **CLI 도구**: asciinema / terminalizer 로 녹화 → GIF 혹은 svg 로 임베드
- **복잡한 워크플로**: 1분 이내 GIF. Kap / Gifox 로 녹화

### 2-3. 언어 스위처 (글로벌 타겟 시)

```markdown
**Language:** [English](README.md) | [한국어](README.ko.md)
```

양쪽 README 상단에 동일 링크. GitHub 가 각각 렌더링.

### 2-4. Badge (신뢰도)

상단에 모아서:

```markdown
[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](LICENSE)
[![macOS 13+](https://img.shields.io/badge/macOS-13.0+-blue.svg)](...)
[![Swift 5.9+](https://img.shields.io/badge/Swift-5.9+-orange.svg)](...)
```

shield.io 의 static badge + 자동 생성 badge (빌드 상태, 커버리지, npm 버전 등).

### 2-5. Feature availability 표

여러 모드/환경 지원 시, "무엇이 언제 되는가" 를 표로:

```markdown
| Feature | Mode A | Mode B |
|---|---|---|
| X | ✅ | ✅ |
| Y | ❌ | ✅ |
```

### 2-6. 설치 옵션 3단 분리

```markdown
## Installation options

### 1. <실제 동작하는 경로> (current default)
### 2. <배포 후 제공 예정> *(not yet published)*
### 3. <추가 대안>
```

현재 동작 가능한 경로를 최상단. 미배포 경로는 `*(not yet published)*` 로 명시해 방문자 혼란 방지.

---

## Layer 3. 외부 인덱스 / 능동적 유입

### 3-1. Homebrew tap (macOS CLI/앱)

**비용 0** (Apple Developer 계정 불필요 — ad-hoc 서명 OK).

**단계**:
1. `.dmg` 파일 준비 (`hdiutil create -volname ... -srcfolder stage -ov -format UDZO out.dmg`)
2. GitHub Release 생성 + `.dmg` 업로드 (`gh release create v0.1.0 out.dmg ...`)
3. SHA256 계산: `shasum -a 256 out.dmg`
4. `OWNER/homebrew-tap` repo 생성 (public)
5. `Casks/NAME.rb` 작성 (templated in [`Distribution/HomebrewTap/`](../../Distribution/HomebrewTap))
6. 사용자 설치: `brew install --cask OWNER/tap/NAME`

**cask 의 `postflight` 에 `xattr -dr com.apple.quarantine` 넣으면** Gatekeeper 경고 자동 우회.

### 3-2. awesome-* 리스트 PR

키 리스트들 (본인 도메인 매칭되는 것):

| 리스트 | 범위 |
|---|---|
| [awesome-macos](https://github.com/iCHAIT/awesome-macOS) | macOS 앱 전반 |
| [awesome-tmux](https://github.com/rothgar/awesome-tmux) | tmux 생태계 |
| [awesome-swift](https://github.com/matteocrippa/awesome-swift) | Swift 프로젝트 |
| [awesome-dev-tools](https://github.com/ericandrewlewis/awesome-developer-experience) | 개발자 도구 |

PR 방식: fork → 알파벳 순서로 한 줄 추가 → PR. 제목/설명 기준을 리스트 README 에서 확인.

### 3-3. Product Hunt

- 대상: 완성도 있는 소비자/개발자 앱
- 화면 캡처, 데모 GIF, 태그 라인 준비
- Tuesday/Wednesday PST 오전 런치가 정석 (상위 노출 유리)

### 3-4. Reddit

도메인별 서브레딧:

| 서브 | 대상 |
|---|---|
| r/MacApps | macOS 앱 |
| r/tmux | tmux 사용자 |
| r/swift | Swift 개발자 |
| r/opensource | 일반 OSS |

**주의**: 각 서브마다 Self-promotion 규칙 있음. Read-only 멤버로 규칙 확인 후 포스팅.

### 3-5. Hacker News — "Show HN"

- 형식: `Show HN: NAME – one-line description`
- URL 은 레포 직접 링크 또는 lander page
- 오전 9시 PST 근처 런치가 유리
- 첫 댓글을 본인이 달아서 맥락 설명 관례

---

## 체크리스트 — 새 공개 레포 출시 시

```
□ Topics 10~15개 등록 (기술스택 + 도메인 + 카테고리)
□ Description 한 줄 작성 (정체성 + 주요 기능 키워드 포함)
□ README 최상단에 Quick start 복붙 블록
□ README 에 Badge (라이선스/플랫폼/버전)
□ (GUI 앱) 스크린샷 docs/assets/ 에 추가해 README embed
□ (글로벌 타겟) README.ko.md 등 언어 스위처
□ Social preview 이미지 업로드 (socialify 또는 직접 디자인)
□ (macOS 앱) Homebrew tap 레포 + cask 정의 + Release .dmg
□ LICENSE 파일 존재
□ 적절한 awesome-* 리스트 PR
□ (콘텐츠 준비되면) Reddit / HN / Product Hunt 런치
```

---

## 참고

- [GitHub Topics 공식 docs](https://docs.github.com/en/repositories/classifying-your-repository-with-topics)
- [Homebrew Acceptable Casks](https://docs.brew.sh/Acceptable-Casks) — 공식 `homebrew/cask` 레포 PR 시 기준
- [shields.io](https://shields.io) — badge 생성
- [socialify.git.ci](https://socialify.git.ci) — 자동 social preview 이미지 생성
