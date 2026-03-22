# Mission-Critical Swift Audit Todo (2026-03-18)

## Plan
- [x] Read prior automation memory and repo state
- [x] Establish working branch for this audit run
- [x] Run baseline verification (`swift test`, `swift build`) and capture failures
- [x] Audit for correctness/safety issues (crash paths, concurrency, wiring, error propagation)
- [x] Add/adjust tests first for each confirmed issue (TDD)
- [x] Implement minimal production-grade fixes
- [x] Re-run targeted tests + full test suite + build
- [ ] Commit with detailed message
- [ ] Push branch and create PR with detailed summary

## Review
- Pending

## Review
- Baseline failures fixed:
  - SwiftPM dependency manifest failure for Hive 0.1.2 pin.
  - Production crash paths (`preconditionFailure`, `try!` path literals).
  - Harness subscriber registration race dropping early `runStarted` events.
  - Control-plane session creation/fork invariant gap (missing project validation).
  - DeepResearch conversation load/persist wiring gap and dead sidebar updater.
  - Ollama non-scalar argument conversion corruption.
- Regression verification:
  - `swift test` passed (117 tests).
  - `swift build` passed.
