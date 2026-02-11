#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/../.." && pwd)"
cd "$ROOT_DIR"

echo "e2e-tests: running approve/deny/resume coverage"
swift test --filter 'ColonyTests\.colonyInterruptsAndResumesApproved|ColonyTests\.colonyResumesRejected|ColonyTests\.colonyPatchesDanglingToolCallsOnNewInput'
