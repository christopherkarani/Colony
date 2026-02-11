#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/../.." && pwd)"
cd "$ROOT_DIR"

source ./HIVE_DEPENDENCY.lock

HIVE_CHECKOUT=".deps/Hive"
HIVE_PACKAGE_PATH="$HIVE_CHECKOUT/Sources/Hive"
LOCAL_FALLBACK_HIVE="$(cd .. && pwd)/Hive"
USING_FALLBACK_MIRROR=false

echo "bootstrap-hive: validating Package.swift remote pin"
if ! rg -n "\\.package\\s*\\(\\s*url\\s*:\\s*\"$HIVE_URL\"\\s*,\\s*exact\\s*:\\s*\"$HIVE_TAG\"\\s*\\)" Package.swift >/dev/null; then
  echo "bootstrap-hive: Package.swift does not match pinned Hive remote dependency" >&2
  exit 1
fi

if [[ -d "$HIVE_CHECKOUT/.git" ]]; then
  echo "bootstrap-hive: using existing checkout at $HIVE_CHECKOUT"
  git -C "$HIVE_CHECKOUT" fetch --tags origin >/dev/null 2>&1 || true
else
  echo "bootstrap-hive: cloning $HIVE_URL into $HIVE_CHECKOUT"
  if ! git clone "$HIVE_URL" "$HIVE_CHECKOUT" >/dev/null 2>&1; then
    if [[ -d "$LOCAL_FALLBACK_HIVE/.git" ]]; then
      echo "bootstrap-hive: remote clone unavailable, falling back to local mirror $LOCAL_FALLBACK_HIVE"
      mkdir -p "$(dirname "$HIVE_CHECKOUT")"
      ln -sfn "$LOCAL_FALLBACK_HIVE" "$HIVE_CHECKOUT"
      USING_FALLBACK_MIRROR=true
    else
      echo "bootstrap-hive: clone failed and local fallback is unavailable" >&2
      exit 1
    fi
  fi
fi

if [[ "$USING_FALLBACK_MIRROR" == "false" ]]; then
  echo "bootstrap-hive: checking out pinned revision $HIVE_REV"
  git -C "$HIVE_CHECKOUT" fetch --tags origin "$HIVE_REV" >/dev/null 2>&1 || true
  git -C "$HIVE_CHECKOUT" checkout --detach "$HIVE_REV" >/dev/null
else
  echo "bootstrap-hive: fallback mirror mode (read-only); skipping checkout mutation"
fi

if [[ ! -f "$HIVE_PACKAGE_PATH/Package.swift" ]]; then
  echo "bootstrap-hive: missing package manifest at $HIVE_PACKAGE_PATH/Package.swift" >&2
  exit 1
fi

resolved_url="$(git -C "$HIVE_CHECKOUT" remote get-url origin)"
if [[ "$resolved_url" != "$HIVE_URL" ]]; then
  echo "bootstrap-hive: origin URL mismatch (expected $HIVE_URL, got $resolved_url)" >&2
  exit 1
fi

resolved_rev="$(git -C "$HIVE_CHECKOUT" rev-parse HEAD)"
if [[ "$resolved_rev" != "$HIVE_REV" ]]; then
  if [[ "$USING_FALLBACK_MIRROR" == "true" ]]; then
    echo "bootstrap-hive: warning - fallback mirror at $resolved_rev differs from pinned $HIVE_REV"
  else
    echo "bootstrap-hive: revision mismatch (expected $HIVE_REV, got $resolved_rev)" >&2
    exit 1
  fi
fi

echo "bootstrap-hive: ready ($HIVE_URL @ $HIVE_REV, tag $HIVE_TAG)"
echo "bootstrap-hive: use COLONY_USE_LOCAL_HIVE_PATH=1 for offline/local fallback builds"
