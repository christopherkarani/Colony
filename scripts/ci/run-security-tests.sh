#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/../.." && pwd)"
cd "$ROOT_DIR"

test_list="$(swift test list)"

# Prefer explicit execution-hardening tests when present.
if echo "$test_list" | rg -q 'diskBackend_rejectsSymlinkFileEscape_read'; then
  echo "security-tests: running execution hardening suite"
  swift test --filter 'diskBackend_rejectsSymlinkFileEscape_read|diskBackend_rejectsSymlinkParentEscape_write|hardenedShellBackend_rejectsDeniedPrefixWorkingDirectory|hardenedShellBackend_timesOutLongRunningCommand|hardenedShellBackend_truncatesOutputAtByteCap'
else
  echo "security-tests: execution-hardening tests not present; running security fallback subset"
  swift test --filter 'ColonyTests\.scratchbookTools_rejectExecutionWhenCapabilityDisabled|ColonyTests\.systemPrompt_injectsScratchbookView_fromSanitizedPath|ColonyTests\.colonyResumesRejected'
fi
