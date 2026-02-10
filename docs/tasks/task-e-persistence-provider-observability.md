Prompt:
Implement durable persistence/recovery, artifact storage, provider routing controls, and observability.

Goal:
Support crash-safe resume, durable run state, artifact retention/redaction, and production model routing.

Task Breakdown:
1. Add durable checkpoint store (`HiveCheckpointQueryableStore` impl on disk).
2. Add durable run-state/event store with restart lookup.
3. Add artifact store with retention policy and redaction policy.
4. Add provider router abstraction with retry/backoff/rate-limit/cost ceilings.
5. Add deterministic budgeting and graceful degradation policies.
6. Add structured observability emitter with default redaction for secrets/content.
7. Add tests for persistence, retention/redaction, routing fallback, and budgeting.

Expected Output:
- New persistence/provider/observability modules with passing tests.
