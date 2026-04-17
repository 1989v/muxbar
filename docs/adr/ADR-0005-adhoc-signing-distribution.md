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
