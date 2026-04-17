# ADR-0001: tmux control mode 채택 (폴링 대신)

- Status: Accepted
- Date: 2026-04-17

## Context

muxbar 는 tmux 세션 상태를 실시간으로 표시해야 한다. 두 가지 옵션:

- **폴링**: `tmux list-sessions` 를 1~2초 주기로 반복 실행
- **Control mode** (`tmux -C`): 단일 영구 연결로 이벤트 푸시 수신

## Decision

Control mode 채택.

## Consequences

**장점**:
- 지연 없는 상태 반영 (%sessions-changed 즉시 수신)
- CPU 사용량 최소 (idle 시 실질 0)
- 라이브 프리뷰(Plan 3)의 전제. %output 을 푸시로 받아야 30+ FPS 달성 가능

**단점**:
- 프로토콜 파서 필요 (구현 완료: `ControlProtocol`)
- 프로세스 연결 끊김 시 재연결 로직 필요 (TBD: Plan 2)
- 테스트 복잡도 증가 (통합 테스트에 실제 tmux 바이너리 필요)

## References

- [tmux Control Mode Wiki](https://github.com/tmux/tmux/wiki/Control-Mode)
- [iTerm2 tmux integration](https://iterm2.com/documentation-tmux-integration.html)
- Design spec §3.1
