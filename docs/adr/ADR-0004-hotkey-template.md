# ADR-0004: HotKey + Template 통합

- Status: Accepted
- Date: 2026-04-17

## Context

- 전역 단축키: Carbon API 직접 호출 vs 라이브러리 사용
- 템플릿: YAML 파일 로딩 vs Swift 코드 정의

## Decision

- **HotKey**: soffes/HotKey (MIT, 300★) — Carbon `RegisterEventHotKey` 래퍼
- **Template**: v0.1 은 Swift 코드(`BuiltInTemplates`)로 정의, v0.2 에서 YAML 사용자 템플릿 지원

## Consequences

**장점**:
- HotKey: 단축키 등록 코드 3줄로 간결
- Template 코드 정의: YAML 파서 불필요, 초기 MVP 복잡도 ↓

**단점**:
- HotKey 의존성 추가
- 사용자가 템플릿 편집 불가 (v0.2 에서 해결)
