#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/../.." && pwd)"
cd "$ROOT_DIR"

BUILD_LOG="${BUILD_LOG:-/tmp/colony-release-build.log}"
TEST_LOG="${TEST_LOG:-/tmp/colony-release-test.log}"

./scripts/ci/check-dependency-policy.sh

echo "release-check: remote-only resolve/build/test for Colony"

COLONY_USE_LOCAL_SWARM_PATH=0 AISTACK_USE_LOCAL_DEPS=0 CONDUIT_SKIP_MLX_DEPS=1 swift package resolve
COLONY_USE_LOCAL_SWARM_PATH=0 AISTACK_USE_LOCAL_DEPS=0 CONDUIT_SKIP_MLX_DEPS=1 swift build 2>&1 | tee "$BUILD_LOG"
COLONY_USE_LOCAL_SWARM_PATH=0 AISTACK_USE_LOCAL_DEPS=0 CONDUIT_SKIP_MLX_DEPS=1 swift test 2>&1 | tee "$TEST_LOG"

if rg -n '\bwarning:|\berror:' "$BUILD_LOG" >/dev/null; then
  echo "release-check: compiler diagnostics found in build log" >&2
  rg -n '\bwarning:|\berror:' "$BUILD_LOG" >&2 || true
  exit 1
fi

if rg -n '\bwarning:' "$TEST_LOG" >/dev/null; then
  echo "release-check: compiler warnings found in test log" >&2
  rg -n '\bwarning:' "$TEST_LOG" >&2 || true
  exit 1
fi

echo "release-check: Colony remote verification passed"
