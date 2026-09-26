#!/usr/bin/env bash
# run.sh — entry point. Routes to run-ios.sh or run-web.sh.
#
# Usage:
#   run.sh --target=ios|web|extension --storyboard=<path> [--out=<dir>] ...
#
# Common flags:
#   --target=ios|web|extension   (required)
#   --storyboard=<path/to/storyboard.md>   (required)
#   --out=<dir>                  (default: <repo>/.market/assets/demos/<slug>/)
#   --slug=<slug>                (default: storyboard filename without .md)
#
# iOS-only:
#   --device-mcp-url=http://...  (required for ios)
#   --simulator                  (use simctl recording instead of QuickTime)
#
# Web/extension-only:
#   --url=<url>                  (required for web)
#   --extension-dir=<path>       (required for extension)

set -euo pipefail

SKILL_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

TARGET=""
STORYBOARD=""
OUT=""
SLUG=""
EXTRA=()

for arg in "$@"; do
  case "$arg" in
    --target=*)         TARGET="${arg#*=}" ;;
    --storyboard=*)     STORYBOARD="${arg#*=}" ;;
    --out=*)            OUT="${arg#*=}" ;;
    --slug=*)           SLUG="${arg#*=}" ;;
    *)                  EXTRA+=("$arg") ;;
  esac
done

if [[ -z "$TARGET" || -z "$STORYBOARD" ]]; then
  echo "usage: run.sh --target=ios|web|extension --storyboard=<path> [--out=<dir>] ..." >&2
  exit 1
fi

if [[ ! -f "$STORYBOARD" ]]; then
  echo "error: storyboard not found: $STORYBOARD" >&2
  exit 1
fi

# Default slug = storyboard filename without .md
if [[ -z "$SLUG" ]]; then
  SLUG="$(basename "$STORYBOARD" .md)"
fi

# Default --out: assume CWD is a repo root → <repo>/.market/assets/demos/<slug>/
if [[ -z "$OUT" ]]; then
  OUT="${PWD}/.market/assets/demos/${SLUG}"
fi

mkdir -p "$OUT/clips" "$OUT/vo"
# Copy provenance only if source != destination (skip when caller already saved
# the storyboard to <out>/storyboard.md, which is the recommended convention).
if [[ "$(cd "$(dirname "$STORYBOARD")" && pwd)/$(basename "$STORYBOARD")" != "$(cd "$OUT" && pwd)/storyboard.md" ]]; then
  cp "$STORYBOARD" "$OUT/storyboard.md"
fi

case "$TARGET" in
  ios)
    exec "${SKILL_DIR}/scripts/run-ios.sh" --out="$OUT" --storyboard="$OUT/storyboard.md" "${EXTRA[@]}"
    ;;
  web|extension)
    exec "${SKILL_DIR}/scripts/run-web.sh" --target="$TARGET" --out="$OUT" --storyboard="$OUT/storyboard.md" "${EXTRA[@]}"
    ;;
  *)
    echo "error: unknown --target=$TARGET (expected ios|web|extension)" >&2
    exit 1
    ;;
esac
