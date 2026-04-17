# ADR-0002: SessionProvider 프로토콜 기반 UI-TmuxKit 분리

- Status: Accepted
- Date: 2026-04-17

## Context

SessionStore(@MainActor, Core 모듈) 가 ControlClient(actor, TmuxKit 모듈) 에 직접 의존하면
Core → TmuxKit 역방향 의존이 생겨 Clean Architecture 원칙 위배.

## Decision

- Core 에 `SessionProvider` 프로토콜 정의 (listSessions/kill/createSession/events)
- TmuxKit 에서 `extension ControlClient: SessionProvider` 로 conformance 제공
- SessionStore 는 프로토콜만 알고 구현체는 외부에서 주입

## Consequences

**장점**:
- Core ← TmuxKit 한 방향 의존 유지
- 테스트에서 Mock provider 주입 가능
- 미래에 remote tmux 지원 시 프로토콜 재구현만 하면 됨

**단점**:
- existential `any SessionProvider` 사용 (Swift 5.7+ 에서 성능 영향 크지 않음)
