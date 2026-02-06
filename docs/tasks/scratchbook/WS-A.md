Prompt:
Decompose WS-A (Scratchbook Core + Storage) from the immutable plan into test-first, implementation, and review work. Implement within ColonyCore/Colony with Swift 6.2, Sendable-first, and Swift Testing. Preserve cloud profile behavior unless explicitly configured.

Goal:
Introduce the Scratchbook data model, deterministic view rendering, and JSON-backed per-thread storage with sorted-keys encoding, plus budget trimming for the injected view.

Task Breakdown:
1. Tests (Swift Testing): add failing tests covering:
   - Codable + Sendable conformance for `ColonyScratchbook` and `ColonyScratchItem`
   - Deterministic ordering by `createdAtNanoseconds` / `updatedAtNanoseconds`
   - `renderView(...)` prioritization order and budget trimming
   - JSON encoding uses `.sortedKeys` for determinism
   - Per-thread file path resolution under `{scratchbookPathPrefix}/{sanitizedThreadID}.json`
2. Implementation:
   - Add `ColonyScratchbook` and `ColonyScratchItem` types with required fields
   - Implement deterministic `renderView(...)` with priority tiers
   - Add JSON store helpers for load/save per thread with sorted keys
   - Implement budget trimming (token limit + maxRenderedItems)
3. Review:
   - Verify API misuse resistance and Sendable correctness
   - Ensure view rendering is deterministic and stable across runs
   - Ensure storage is scoped to the thread file only

Expected Output:
- New core types and storage helpers in ColonyCore/Colony with passing tests for determinism, budgeting, and file path resolution.

