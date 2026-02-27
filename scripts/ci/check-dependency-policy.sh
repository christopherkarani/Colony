#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/../.." && pwd)"
cd "$ROOT_DIR"

fail() {
  echo "dependency-policy: $1" >&2
  exit 1
}

if [[ ! -f HIVE_DEPENDENCY.lock ]]; then
  fail "HIVE_DEPENDENCY.lock is required"
fi

source ./HIVE_DEPENDENCY.lock

echo "dependency-policy: validating Package.swift Hive dependency policy"

if ! rg -n '\.package\s*\(\s*path\s*:\s*"\.deps/Hive/Sources/Hive"\s*\)' Package.swift >/dev/null; then
  fail "Package.swift must consume Hive from .deps/Hive/Sources/Hive"
fi

if [[ ! -f Package.resolved ]]; then
  fail "Package.resolved is required and must be committed"
fi

if rg -n "\"location\"\\s*:\\s*\"$HIVE_URL\"" Package.resolved >/dev/null; then
  if ! rg -n "\"revision\"\\s*:\\s*\"$HIVE_REV\"" Package.resolved >/dev/null; then
    fail "Package.resolved must pin Hive revision to $HIVE_REV"
  fi
  if ! rg -n "\"version\"\\s*:\\s*\"$HIVE_TAG\"" Package.resolved >/dev/null; then
    fail "Package.resolved must pin Hive version to $HIVE_TAG"
  fi
else
  echo "dependency-policy: warning - Hive pin missing from Package.resolved (local path mode)"
fi

echo "dependency-policy: checking lockfile reproducibility"
resolved_snapshot="$(mktemp)"
cp Package.resolved "$resolved_snapshot"

mkdir -p /tmp/clang-module-cache
mkdir -p .build/swiftpm-cache .build/swiftpm-config .build/swift-home
./scripts/ci/bootstrap-hive.sh >/dev/null
set +e
resolve_output="$(
  HOME="$ROOT_DIR/.build/swift-home" \
  SWIFTPM_PACKAGECACHE="$ROOT_DIR/.build/swiftpm-cache" \
  SWIFTPM_CONFIG_PATH="$ROOT_DIR/.build/swiftpm-config" \
  CLANG_MODULE_CACHE_PATH=/tmp/clang-module-cache \
  swift package resolve --disable-sandbox --scratch-path /tmp/colony-swiftpm-policy 2>&1
)"
resolve_status=$?
set -e

if [[ $resolve_status -ne 0 ]]; then
  if echo "$resolve_output" | rg -q 'Could not resolve host|Failed to clone repository'; then
    echo "dependency-policy: warning - skipping lockfile reproducibility check (offline dependency fetch failure)"
    rm -f "$resolved_snapshot"
    echo "dependency-policy: OK (offline mode)"
    exit 0
  fi
  echo "$resolve_output" >&2
  rm -f "$resolved_snapshot"
  fail "swift package resolve failed"
fi

if ! diff -u "$resolved_snapshot" Package.resolved >/dev/null; then
  echo "dependency-policy: Package.resolved changed after resolve" >&2
  diff -u "$resolved_snapshot" Package.resolved >&2 || true
  rm -f "$resolved_snapshot"
  fail "lockfile drift detected"
fi

rm -f "$resolved_snapshot"

echo "dependency-policy: OK"
