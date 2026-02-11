# Coding Harness Readiness Plan (Immutable)

Status: authoritative, immutable after creation.
Owner: Orchestrator (CTO role)
Date: 2026-02-10

## Goals
1. Ship a production-ready coding harness API over Colony runtime.
2. Enforce product-grade tool safety with mandatory approval for mutating actions.
3. Harden execution and filesystem confinement.
4. Add coding-native Git/LSP tooling.
5. Deliver durable persistence/recovery and artifact handling.
6. Add provider routing/retry/rate/cost controls.
7. Add protocol contracts, E2E, security tests, and CI gates.
8. Remove local-path Hive dependency and document release policy.
9. Add structured observability with default redaction.

## Constraints
- Preserve existing public APIs where feasible; additive evolution preferred.
- Keep Swift type safety strong; avoid untyped payloads for new surfaces.
- New protocol payloads must be versioned and Codable.
- Deterministic behavior in tests.
- No plan edits after this file is created.

## Non-Goals
- Full external service integrations (real LSP server process orchestration across all editors).
- Provider-specific SDK deep integrations beyond stable abstraction layer.

## Architecture Decisions
1. Introduce a first-class harness session layer in `Colony`:
   - Lifecycle methods: create/start/stream/interrupted/resume/stop.
   - Versioned event envelope + payload enums.
2. Introduce a tool safety policy engine in `ColonyCore`:
   - Per-tool risk levels.
   - Mandatory approvals for mutating/execution/network actions.
   - Signed decision records and immutable hash-chained audit log.
3. Introduce hardened execution backend:
   - PTY-capable shell backend with timeout/cancel/output/resource caps.
   - Hardened path confinement with canonical + symlink-safe checks.
4. Add first-class coding backends in `ColonyCore` and tool adapters in `Colony`:
   - Git backend + tools.
   - LSP backend + tools.
5. Add persistence components:
   - Durable checkpoint store implementation.
   - Durable run-state/event store.
   - Artifact store with retention + redaction.
6. Add provider production router:
   - Retry/backoff/rate/cost ceilings and deterministic fallback/degradation.
7. Add observability pipeline:
   - Structured run/tool events and redaction middleware.

## Task Mapping
- Task A: Harness lifecycle + versioned protocol contracts.
- Task B: Safety policy engine + signed immutable audit logs.
- Task C: Execution hardening + confinement hardening.
- Task D: Git/LSP first-class tools and runtime wiring.
- Task E: Persistence/recovery + artifacts + provider routing + observability.
- Task F: Dependency/release hardening + CI quality gates + integration tests.

## Validation Checklist
- Contract tests for protocol envelope/payload versions.
- E2E tests for approve/deny/resume flow.
- Security tests for command/path injection and policy bypass.
- Tooling tests for Git/LSP adapters.
- Persistence tests for restart/recovery and immutable audit chain.
- CI workflow executes all above.
