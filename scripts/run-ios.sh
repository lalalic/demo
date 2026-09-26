#!/usr/bin/env bash
# run-ios.sh — iOS adapter. Drives via AppAgent MCP, records via simctl or QuickTime.
#
# Usage:
#   run-ios.sh --out=<dir> --storyboard=<path> --device-mcp-url=<url> [--simulator]
#
# Tool names are configurable. Defaults match NeoX: `agent.pilot` + `agent.demo`.

set -euo pipefail

SKILL_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

OUT=""
STORYBOARD=""
MCP_URL=""
SIMULATOR=0
UI_TOOL="agent.pilot"
DEMO_TOOL="agent.demo"

for arg in "$@"; do
  case "$arg" in
    --out=*)             OUT="${arg#*=}" ;;
    --storyboard=*)      STORYBOARD="${arg#*=}" ;;
    --device-mcp-url=*)  MCP_URL="${arg#*=}" ;;
    --simulator)         SIMULATOR=1 ;;
    --ui-tool=*)          UI_TOOL="${arg#*=}" ;;
    --demo-tool=*)        DEMO_TOOL="${arg#*=}" ;;
  esac
done

if [[ -z "$OUT" || -z "$STORYBOARD" || -z "$MCP_URL" ]]; then
  echo "usage: run-ios.sh --out=<dir> --storyboard=<path> --device-mcp-url=<url> [--simulator]" >&2
  exit 1
fi

# ─── MCP helper ───
mcp_call() {
  local tool="$1"; shift
  local args_json="$1"; shift || true
  local id=$RANDOM
  curl -s -X POST "$MCP_URL" -H 'Content-Type: application/json' \
    -d "{\"jsonrpc\":\"2.0\",\"id\":${id},\"method\":\"tools/call\",\"params\":{\"name\":\"${tool}\",\"arguments\":${args_json}}}"
}

# ─── 1. Snapshot ───
echo "→ snapshot via AppAgent MCP at $MCP_URL"
mcp_call "$UI_TOOL" '{"command":"snapshot"}' > "${OUT}/snapshot.json"

# ─── 2. Start recording ───
RECORD_PID=""
if [[ "$SIMULATOR" -eq 1 ]]; then
  echo "→ starting simctl recording"
  xcrun simctl io booted recordVideo --codec=h264 "${OUT}/demo.mp4" &
  RECORD_PID=$!
  sleep 1
else
  echo
  echo "  ┌─ Manual recording required ──────────────────────────────┐"
  echo "  │ 1. Open QuickTime Player                                 │"
  echo "  │ 2. File → New Movie Recording                            │"
  echo "  │ 3. Click ⌄ next to record button → pick your iOS device  │"
  echo "  │ 4. Click record                                          │"
  echo "  │ 5. Press ENTER here when ready                           │"
  echo "  └──────────────────────────────────────────────────────────┘"
  read -r
fi

# ─── 3. Start runtime event recording ───
mcp_call "$DEMO_TOOL" '{"command":"start_recording"}' > /dev/null

# ─── 4. Walk storyboard ───
"${SKILL_DIR}/scripts/parse-storyboard.sh" "$STORYBOARD" | while IFS= read -r line; do
  CMD=$(printf '%s' "$line" | python3 -c 'import sys,json; print(json.loads(sys.stdin.read())["cmd"])')
  ARGS=$(printf '%s' "$line" | python3 -c 'import sys,json; print(json.dumps(json.loads(sys.stdin.read())["args"]))')

  case "$CMD" in
    app_agent)
      # args has "sub":"tap"|"type"|... + remaining params; restructure
      SUB=$(printf '%s' "$ARGS" | python3 -c 'import sys,json; d=json.loads(sys.stdin.read()); print(d.pop("sub","")); ' )
      REST=$(printf '%s' "$ARGS" | python3 -c 'import sys,json; d=json.loads(sys.stdin.read()); d.pop("sub",None); d["command"]="'"$SUB"'"; print(json.dumps(d))')
      echo "  → $UI_TOOL $SUB"
      mcp_call "$UI_TOOL" "$REST" > /dev/null
      ;;
    *)
      # demo command
      WRAPPED=$(printf '%s' "$ARGS" | python3 -c 'import sys,json; d=json.loads(sys.stdin.read()); d["command"]="'"$CMD"'"; print(json.dumps(d))')
      echo "  → $DEMO_TOOL $CMD"
      mcp_call "$DEMO_TOOL" "$WRAPPED" > /dev/null
      ;;
  esac
done

# ─── 5. Stop runtime recording ───
echo "→ stopping demo runtime recording"
EVENTS_RAW=$(mcp_call "$DEMO_TOOL" '{"command":"stop_recording"}')
echo "$EVENTS_RAW" | python3 -c 'import sys,json; r=json.loads(sys.stdin.read()); content=r.get("result",{}).get("content",[{}])[0].get("text","[]"); print(content)' \
  > "${OUT}/events.json"

# ─── 6. Stop screen recording ───
if [[ "$SIMULATOR" -eq 1 ]]; then
  kill -SIGINT "$RECORD_PID" 2>/dev/null || true
  wait "$RECORD_PID" 2>/dev/null || true
else
  echo
  echo "  Stop QuickTime recording (⌘+ctrl+S or stop button), then save as:"
  echo "    ${OUT}/demo.mp4"
  echo "  Press ENTER when saved."
  read -r
fi

# ─── 7. Clip per step ───
"${SKILL_DIR}/scripts/clip.sh" "$OUT"

echo
echo "Done. Outputs in $OUT:"
ls -1 "$OUT"
