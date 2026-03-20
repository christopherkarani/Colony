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

if ! rg -n 'COLONY_USE_LOCAL_HIVE_PATH' Package.swift >/dev/null; then
  fail "Package.swift must gate any local Hive fallback behind COLONY_USE_LOCAL_HIVE_PATH"
fi

if ! rg -n "\\.package\\s*\\(\\s*url\\s*:\\s*\"$HIVE_URL\"\\s*,\\s*exact\\s*:\\s*\"$HIVE_TAG\"\\s*\\)" Package.swift >/dev/null; then
  fail "Package.swift must pin Hive remote dependency from HIVE_DEPENDENCY.lock"
fi

if ! rg -n '\.package\s*\(\s*path\s*:\s*"\.deps/Hive/Sources/Hive"\s*\)' Package.swift >/dev/null; then
  fail "Package.swift must keep the explicit .deps/Hive local fallback path for offline mode"
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
  echo "dependency-policy: warning - Hive pin missing from Package.resolved (likely local fallback mode)"
fi

echo "dependency-policy: checking lockfile reproducibility"
resolved_snapshot="$(mktemp)"
cp Package.resolved "$resolved_snapshot"

mkdir -p /tmp/clang-module-cache
COLONY_USE_LOCAL_HIVE_PATH=1 CLANG_MODULE_CACHE_PATH=/tmp/clang-module-cache swift package resolve >/dev/null

if ! diff -u "$resolved_snapshot" Package.resolved >/dev/null; then
  echo "dependency-policy: Package.resolved changed after resolve" >&2
  diff -u "$resolved_snapshot" Package.resolved >&2 || true
  rm -f "$resolved_snapshot"
  fail "lockfile drift detected"
fi

rm -f "$resolved_snapshot"

echo "dependency-policy: OK"
