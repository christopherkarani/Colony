#!/usr/bin/env bash
set -euo pipefail

# Contract gate for runtime/protocol invariants.
# If explicit contract/harness tests exist, run them.
# Otherwise run deterministic fallback tests that enforce message/protocol semantics.

ROOT_DIR="$(cd "$(dirname "$0")/../.." && pwd)"
cd "$ROOT_DIR"

test_list="$(swift test list)"

if echo "$test_list" | rg -q '(Harness|harness|Contract|contract|protocolVersion|Envelope)'; then
  pattern='Harness|harness|Contract|contract|protocolVersion|Envelope'
  echo "contract-tests: running discovered contract/harness tests"
  swift test --filter "$pattern"
else
  echo "contract-tests: no explicit contract/harness tests discovered; running fallback contract invariants"
  swift test --filter 'ColonyTests\.colonyMessagesReducerSemantics|ColonyTests\.colonyPatchesDanglingToolCallsOnNewInput'
fi
