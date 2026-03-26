#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/../.." && pwd)"
cd "$ROOT_DIR"

REMOTE_URL="https://github.com/christopherkarani/Swarm.git"
EXPECTED_SWARM_VERSION="${EXPECTED_SWARM_VERSION:-}"

fail() {
  echo "dependency-policy: $1" >&2
  exit 1
}

echo "dependency-policy: validating Colony -> Swarm dependency policy"

if ! rg -n 'COLONY_USE_LOCAL_SWARM_PATH' Package.swift >/dev/null; then
  fail "Package.swift must gate any local Swarm fallback behind COLONY_USE_LOCAL_SWARM_PATH"
fi

if ! rg -n '\.package\s*\(\s*path\s*:\s*"\.\./Swarm"\s*\)' Package.swift >/dev/null; then
  fail "Package.swift must keep the explicit ../Swarm local fallback path for opt-in development"
fi

if ! rg -n "\\.package\\s*\\(\\s*url\\s*:\\s*\"$REMOTE_URL\"" Package.swift >/dev/null; then
  fail "Package.swift must declare the Swarm GitHub dependency at $REMOTE_URL"
fi

if [[ -n "$EXPECTED_SWARM_VERSION" ]]; then
  if ! rg -n "\\.package\\s*\\(\\s*url\\s*:\\s*\"$REMOTE_URL\"\\s*,\\s*exact\\s*:\\s*\"$EXPECTED_SWARM_VERSION\"\\s*\\)" Package.swift >/dev/null; then
    fail "Package.swift must pin Swarm exactly to $EXPECTED_SWARM_VERSION before release"
  fi
else
  echo "dependency-policy: warning - EXPECTED_SWARM_VERSION not set, skipping exact-tag enforcement"
fi

if [[ ! -f Package.resolved ]]; then
  fail "Package.resolved is required and must be committed"
fi

if rg -n "\"location\"\\s*:\\s*\"$REMOTE_URL\"" Package.resolved >/dev/null; then
  if [[ -n "$EXPECTED_SWARM_VERSION" ]]; then
    if ! rg -n "\"version\"\\s*:\\s*\"$EXPECTED_SWARM_VERSION\"" Package.resolved >/dev/null; then
      fail "Package.resolved must pin Swarm version to $EXPECTED_SWARM_VERSION"
    fi
  fi
else
  echo "dependency-policy: warning - Swarm pin missing from Package.resolved (likely local override mode)"
fi

echo "dependency-policy: checking lockfile reproducibility in remote mode"
resolved_snapshot="$(mktemp)"
cp Package.resolved "$resolved_snapshot"

mkdir -p /tmp/clang-module-cache
COLONY_USE_LOCAL_SWARM_PATH=0 AISTACK_USE_LOCAL_DEPS=0 CONDUIT_SKIP_MLX_DEPS=1 CLANG_MODULE_CACHE_PATH=/tmp/clang-module-cache swift package resolve >/dev/null

if ! diff -u "$resolved_snapshot" Package.resolved >/dev/null; then
  echo "dependency-policy: Package.resolved changed after resolve" >&2
  diff -u "$resolved_snapshot" Package.resolved >&2 || true
  rm -f "$resolved_snapshot"
  fail "lockfile drift detected"
fi

rm -f "$resolved_snapshot"

echo "dependency-policy: OK"
