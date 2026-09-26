#!/usr/bin/env bash
# run-web.sh — execute a storyboard against a live web/extension page,
# record via macOS screencapture, write per-step clips.
#
# Inputs:
#   --target=web|extension
#   --storyboard=<path/to/storyboard.md>
#   --out=<dir>                   # already created by run.sh
#   --url=<url>                   # required for web; ignored if a tab is already on it
#   --extension-dir=<path>        # extension only, advisory (Chrome must already be loaded)
#   --tab=<tab-id>                # optional: pin to a specific tab (e.g. t7)

set -euo pipefail

SKILL_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
RUNTIME_JS="${SKILL_DIR}/runtimes/demo-runtime.js"

TARGET=""; OUT=""; STORYBOARD=""; URL=""; EXT_DIR=""; TAB=""
for arg in "$@"; do
  case "$arg" in
    --target=*)        TARGET="${arg#*=}" ;;
    --out=*)           OUT="${arg#*=}" ;;
    --storyboard=*)    STORYBOARD="${arg#*=}" ;;
    --url=*)           URL="${arg#*=}" ;;
    --extension-dir=*) EXT_DIR="${arg#*=}" ;;
    --tab=*)           TAB="${arg#*=}" ;;
  esac
done

[[ -f "$STORYBOARD" ]] || { echo "error: storyboard not found: $STORYBOARD" >&2; exit 1; }
[[ -d "$OUT" ]]        || { echo "error: out dir not found: $OUT (run.sh should have created it)" >&2; exit 1; }
[[ "$TARGET" == "web" || "$TARGET" == "extension" ]] || { echo "error: bad --target=$TARGET" >&2; exit 1; }
[[ "$TARGET" == "web" && -z "$URL" ]] && { echo "error: --url required for --target=web" >&2; exit 1; }

# --- prereqs ---
for t in agent-browser edge-tts ffmpeg python3 screencapture osascript; do
  command -v "$t" >/dev/null || { echo "error: $t not on PATH" >&2; exit 1; }
done

# --- ensure compiled runtime bundle ---
if [[ ! -f "$RUNTIME_JS" ]]; then
  echo "→ building runtime bundle (one-time)"
  ( cd "$SKILL_DIR/runtimes" && npx --yes esbuild demo-runtime.ts --bundle --format=iife --global-name=__demoRuntime --outfile=demo-runtime.js >/dev/null )
fi

# --- pin to a tab (optional) ---
if [[ -n "$TAB" ]]; then
  echo "→ switch to tab $TAB"
  agent-browser tab "$TAB" >/dev/null
fi

# --- navigate (only if URL given AND current tab not already on it) ---
if [[ -n "$URL" ]]; then
  CUR_URL=$(agent-browser eval 'location.href' 2>/dev/null | tr -d '"' || echo "")
  if [[ "$CUR_URL" != "$URL"* ]]; then
    echo "→ navigate $URL"
    agent-browser navigate "$URL" >/dev/null
    sleep 1
  else
    echo "→ already on $URL (skip navigate)"
  fi
fi

# --- ensure shared runtime exists ---
# Preferred path: Demo Runtime Chrome extension already exposes window.demo.
# Fallback: inject the bundled runtime directly for compatibility.
HAS_DEMO=$(agent-browser eval 'typeof window.demo !== "undefined"' 2>/dev/null | tr -d '"' || echo "false")
if [[ "$HAS_DEMO" == "true" ]]; then
  echo "→ shared demo runtime already available"
else
  echo "→ inject demo-runtime.js (extension not present)"
  agent-browser eval --stdin < "$RUNTIME_JS" >/dev/null
fi

# --- snapshot ---
echo "→ snapshot"
agent-browser snapshot --json > "${OUT}/snapshot.json" 2>/dev/null \
  || agent-browser snapshot > "${OUT}/snapshot.json"

# --- parse storyboard once into JSONL ---
PARSED="${OUT}/.storyboard.jsonl"
"${SKILL_DIR}/scripts/parse-storyboard.sh" "$STORYBOARD" > "$PARSED"

# --- TTS pre-pass ---
echo "→ TTS pre-pass (edge-tts)"
SAY_IDX=0
while IFS= read -r line; do
  CMD=$(printf '%s' "$line" | python3 -c 'import sys,json; print(json.loads(sys.stdin.read())["cmd"])')
  if [[ "$CMD" == "say" ]]; then
    SAY_IDX=$((SAY_IDX+1))
    TEXT=$(printf '%s' "$line" | python3 -c 'import sys,json; print(json.loads(sys.stdin.read())["args"].get("text",""))')
    OUTWAV="${OUT}/vo/say-${SAY_IDX}.wav"
    echo "  • say-${SAY_IDX}: ${TEXT:0:60}"
    edge-tts --voice "en-US-AriaNeural" --text "$TEXT" --write-media "${OUTWAV%.wav}.mp3" >/dev/null
    ffmpeg -loglevel error -y -i "${OUTWAV%.wav}.mp3" -ar 48000 -ac 2 "$OUTWAV"
    rm -f "${OUTWAV%.wav}.mp3"
  fi
done < "$PARSED"

# --- estimate recording duration in seconds ---
DUR=$(python3 - "$PARSED" <<'PY'
import json, sys
total_ms = 1500  # leading pad (screencapture init + first command)
for line in open(sys.argv[1]):
    e = json.loads(line)
    cmd, args = e["cmd"], e["args"]
    if cmd == "wait":
        total_ms += int(args.get("ms", 0))
    elif cmd == "say":
        total_ms += max(2000, len(args.get("text","").split()) * 450)
    elif cmd in ("step", "spotlight", "caption", "highlight", "annotate", "clear", "cursor"):
        total_ms += 350
    elif cmd == "agent-browser":
        sub = args.get("sub","")
        if sub == "keyboard":
            text = args.get("text","")
            total_ms += max(1000, len(text) * 90)
        elif sub == "fill":
            text = args.get("text","")
            total_ms += max(500, len(text) * 25)
        elif sub == "click":
            total_ms += 350
        elif sub == "press":
            total_ms += 250
        elif sub == "eval":
            total_ms += 500
        else:
            total_ms += 500
total_ms += 1500  # trailing pad
print(max(5, int(round(total_ms / 1000))))
PY
)
echo "→ estimated recording duration: ${DUR}s"

# --- compute screencapture region (full Chrome window) ---
BOUNDS=$(osascript -e 'tell application "Google Chrome" to get bounds of front window' 2>/dev/null || echo "0, 0, 1280, 800")
read -r RECT_X RECT_Y RECT_W RECT_H < <(python3 -c "
b = '$BOUNDS'.replace(',','').split()
x1, y1, x2, y2 = int(b[0]), int(b[1]), int(b[2]), int(b[3])
print(x1, y1, x2-x1, y2-y1)
")
echo "→ region: ${RECT_X},${RECT_Y} ${RECT_W}x${RECT_H}"

# --- start screen recording (background) ---
RAW_MOV="${OUT}/demo.raw.mov"
rm -f "$RAW_MOV"
echo "→ screencapture starting (${DUR}s)"
screencapture -V "$DUR" -R"${RECT_X},${RECT_Y},${RECT_W},${RECT_H}" -v "$RAW_MOV" &
REC_PID=$!
sleep 1.2  # let screencapture initialize before we start typing/clicking

# --- start runtime event timeline ---
agent-browser eval 'window.demo.startRecording()' >/dev/null

# --- helper: build runtime call expression for one parsed command ---
runtime_expr() {
  python3 - <<PY
import json
cmd = "$1"
args = json.loads('''$2''')
def sel():
    if args.get("ref"):
        return "@" + args["ref"]
    return args.get("selector", "")
def js(v): return json.dumps(v)
if cmd == "step":      print(f"window.demo.step({js(args.get('title',''))})")
elif cmd == "spotlight":
    t = args.get("text")
    print(f"window.demo.spotlight({js(sel())}, {js(t) if t else 'undefined'})")
elif cmd == "annotate":
    print(f"window.demo.annotate({js(sel())}, {js(args.get('text',''))})")
elif cmd == "caption": print(f"window.demo.caption({js(args.get('text',''))})")
elif cmd == "cursor":  print(f"window.demo.cursorTo({js(sel())})")
elif cmd == "highlight":print(f"window.demo.highlight({js(sel())})")
elif cmd == "wait":    print(f"window.demo.wait({int(args.get('ms',0))})")
elif cmd == "clear":   print("window.demo.clear()")
elif cmd == "pause":   print("window.demo.pause()")
elif cmd == "resume":  print("window.demo.resume()")
else: print(f"console.warn('unknown demo cmd: {cmd}')")
PY
}

# --- walk storyboard ---
SAY_COUNTER=0
echo "→ executing storyboard"
while IFS= read -r line; do
  CMD=$(printf '%s' "$line" | python3 -c 'import sys,json; print(json.loads(sys.stdin.read())["cmd"])')
  ARGS=$(printf '%s' "$line" | python3 -c 'import sys,json; print(json.dumps(json.loads(sys.stdin.read())["args"]))')

  case "$CMD" in
    say)
      SAY_COUNTER=$((SAY_COUNTER+1))
      TEXT=$(printf '%s' "$ARGS" | python3 -c 'import sys,json; print(json.loads(sys.stdin.read()).get("text",""))')
      AUDIO="vo/say-${SAY_COUNTER}.wav"
      EXPR=$(python3 -c "
import json
text = json.loads('''$ARGS''').get('text','')
audio = '$AUDIO'
print(f'window.demo.caption({json.dumps(text)}); (window.__demoSayLog=window.__demoSayLog||[]).push({{t:Date.now(),audio:{json.dumps(audio)},text:{json.dumps(text)}}})')
")
      printf '%s' "$EXPR" | agent-browser eval --stdin >/dev/null
      echo "  • say-${SAY_COUNTER}: ${TEXT:0:60}"
      ;;
    agent-browser)
      SUB=$(printf '%s' "$ARGS" | python3 -c 'import sys,json; print(json.loads(sys.stdin.read()).get("sub",""))')
      RAW=$(printf '%s' "$ARGS" | python3 -c 'import sys,json; print(json.loads(sys.stdin.read()).get("raw",""))')
      case "$SUB" in
        click)
          # RAW = selector (may contain spaces, e.g. "#aichat textarea")
          # Strip outer quotes if present.
          SEL="$RAW"
          [[ "$SEL" == \"*\" ]] && SEL="${SEL:1:${#SEL}-2}"
          echo "  • click $SEL"
          agent-browser click "$SEL" >/dev/null
          ;;
        press)
          KEY="$RAW"
          [[ "$KEY" == \"*\" ]] && KEY="${KEY:1:${#KEY}-2}"
          echo "  • press $KEY"
          agent-browser press "$KEY" >/dev/null
          ;;
        keyboard)
          # RAW = "type \"<text>\""  (or "type <text>")
          # Pop the first word; the remainder is the text (strip surrounding quotes).
          SUBSUB="${RAW%% *}"
          TEXT="${RAW#* }"
          [[ "$TEXT" == \"*\" && "$TEXT" == *\" ]] && TEXT="${TEXT:1:${#TEXT}-2}"
          echo "  • keyboard $SUBSUB ${TEXT:0:50}"
          agent-browser keyboard "$SUBSUB" "$TEXT" >/dev/null
          ;;
        eval)
          # RAW = full JS expression
          echo "  • eval ${RAW:0:60}"
          printf '%s' "$RAW" | agent-browser eval --stdin >/dev/null
          ;;
        fill)
          # RAW = "<selector_or_@ref> \"<text>\""
          REF="${RAW%% *}"
          TEXT="${RAW#* }"
          [[ "$TEXT" == \"*\" && "$TEXT" == *\" ]] && TEXT="${TEXT:1:${#TEXT}-2}"
          echo "  • fill $REF ${TEXT:0:40}"
          agent-browser fill "$REF" "$TEXT" >/dev/null
          ;;
        *)
          echo "  ⚠ unsupported agent-browser sub: $SUB"
          ;;
      esac
      ;;
    wait)
      MS=$(printf '%s' "$ARGS" | python3 -c 'import sys,json; print(int(json.loads(sys.stdin.read()).get("ms",0)))')
      echo "  • wait ${MS}ms"
      python3 -c "import time; time.sleep($MS/1000)"
      # Also notify the runtime so events.json captures the wait
      printf '%s' "window.demo.logEventPublic && window.demo.logEventPublic({type:'wait',duration:${MS}})" | agent-browser eval --stdin >/dev/null 2>&1 || true
      ;;
    *)
      EXPR=$(runtime_expr "$CMD" "$ARGS")
      echo "  • demo.$CMD"
      printf '%s' "$EXPR" | agent-browser eval --stdin >/dev/null
      ;;
  esac
done < "$PARSED"

# --- stop runtime recording, dump events ---
echo "→ stop runtime recording"
EVENTS=$(agent-browser eval 'JSON.stringify(window.demo.stopRecording())')
SAYLOG=$(agent-browser eval 'JSON.stringify(window.__demoSayLog||[])')

# Strip outer quotes from agent-browser eval response (it returns "{...}" as a JSON string)
python3 - "$EVENTS" "$SAYLOG" > "${OUT}/events.json" <<'PY'
import json, sys
def unwrap(s):
    s = s.strip()
    if s.startswith('"') and s.endswith('"'):
        return json.loads(s)
    return s
events = json.loads(unwrap(sys.argv[1]))
saylog = json.loads(unwrap(sys.argv[2]))
if saylog:
    base = min(s["t"] for s in saylog)
    for s in saylog:
        events.append({"t": s["t"] - base, "type": "say", "audio": s["audio"], "text": s["text"]})
events.sort(key=lambda e: e.get("t", 0))
print(json.dumps(events, indent=2))
PY

# --- wait for screencapture to finish ---
echo "→ waiting for screencapture to finish"
wait "$REC_PID" 2>/dev/null || true

# --- transcode raw mov → demo.mp4 ---
DEMO_MP4="${OUT}/demo.mp4"
if [[ ! -s "$RAW_MOV" ]]; then
  echo "error: screencapture produced no output ($RAW_MOV)" >&2
  exit 1
fi
echo "→ transcode demo.raw.mov → demo.mp4"
ffmpeg -loglevel error -y -i "$RAW_MOV" \
  -c:v libx264 -pix_fmt yuv420p -movflags +faststart -an "$DEMO_MP4"

# --- mix VO ---
"${SKILL_DIR}/scripts/mix-vo.sh" "$OUT" || echo "  ⚠ mix-vo.sh failed (continuing)"

# --- clip per step ---
"${SKILL_DIR}/scripts/clip.sh" "$OUT" || echo "  ⚠ clip.sh failed (continuing)"

echo
echo "✓ done. Output:"
ls -la "$OUT"
[[ -d "${OUT}/clips" ]] && ls -la "${OUT}/clips"
