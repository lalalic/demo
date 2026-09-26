#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
npx --yes esbuild "$ROOT/runtimes/demo-runtime.ts" --bundle --format=iife --global-name=__demoRuntime --outfile="$ROOT/runtimes/demo-runtime.js"
cp "$ROOT/runtimes/demo-runtime.js" "$ROOT/web-extension/demo-runtime.js"
echo "Built browser runtime and synced Chrome extension."
