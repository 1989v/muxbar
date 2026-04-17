# ADR-0003: SwiftTerm 채택 (ANSI 렌더링)

- Status: Accepted
- Date: 2026-04-17

## Context

라이브 프리뷰(L3)는 tmux `%output` 으로 받은 바이트 스트림(ANSI escape 포함)을
정확히 렌더해야 한다. 직접 ANSI 파서를 구현하면 CSI/OSC/SGR 수많은 escape 시퀀스를
모두 처리해야 해 러빗홀.

## Decision

SwiftTerm (MIT, 미구엘 데 이카자 메인테인) 의 headless `Terminal` 엔진을 사용.
`feed(byteArray:)` 로 원시 바이트 주입 → 내부에서 cell buffer 갱신 →
`getScrollInvariantLine(row:)` 로 읽어 NSAttributedString 생성.

## Consequences

**장점**:
- ANSI/UTF-8/SGR/CSI 처리 검증된 구현 재사용
- iTerm2 유사 렌더 가능 (미래 색상 지원 용이)

**단점**:
- 외부 의존성 추가 (빌드 시 Git 네트워크 필요)
- SwiftTerm 의 API 가 버전에 따라 소폭 변경될 수 있음

## References
- https://github.com/migueldeicaza/SwiftTerm
