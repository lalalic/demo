#!/usr/bin/env bash
# clip.sh — split demo.mp4 into per-step clips using events.json timestamps
#
# Usage: clip.sh <out-dir>
#
# Reads:  <out>/events.json  (array of {t, type, title?, ...})
#         <out>/demo.mp4
# Writes: <out>/clips/NN-<step-slug>.mp4

set -euo pipefail

OUT="${1:?usage: clip.sh <out-dir>}"
EVENTS="${OUT}/events.json"
VIDEO="${OUT}/demo.mp4"

if [[ ! -f "$EVENTS" ]]; then echo "error: $EVENTS not found" >&2; exit 1; fi
if [[ ! -f "$VIDEO" ]]; then echo "error: $VIDEO not found" >&2; exit 1; fi

mkdir -p "${OUT}/clips"

# Get total video duration in ms via ffprobe.
TOTAL_MS=$(ffprobe -v error -select_streams v:0 -show_entries format=duration \
  -of default=noprint_wrappers=1:nokey=1 "$VIDEO" \
  | awk '{printf "%d", $1 * 1000}')

# Parse events.json with python (jq might not be installed).
python3 - "$EVENTS" "$TOTAL_MS" <<'PY' > "${OUT}/.steps.tsv"
import json, sys, re
events_path, total_ms = sys.argv[1], int(sys.argv[2])
with open(events_path) as f:
    events = json.load(f)
steps = [(int(e["t"]), e.get("title", e.get("text", "step"))) for e in events if e.get("type") == "step"]
for i, (t, title) in enumerate(steps):
    end = steps[i + 1][0] if i + 1 < len(steps) else total_ms
    slug = re.sub(r"[^a-z0-9]+", "-", title.lower()).strip("-")[:40] or f"step-{i+1}"
    print(f"{i+1}\t{t}\t{end}\t{slug}")
PY

NN_FMT="%02d"
while IFS=$'\t' read -r idx start end slug; do
  N=$(printf "$NN_FMT" "$idx")
  OUTFILE="${OUT}/clips/${N}-${slug}.mp4"
  START_S=$(awk -v ms="$start" 'BEGIN{printf "%.3f", ms/1000}')
  DUR_S=$(awk -v s="$start" -v e="$end" 'BEGIN{printf "%.3f", (e-s)/1000}')
  echo "→ ${OUTFILE}  (${START_S}s, ${DUR_S}s)"
  ffmpeg -loglevel error -y -ss "$START_S" -i "$VIDEO" -t "$DUR_S" -c copy "$OUTFILE"
done < "${OUT}/.steps.tsv"

rm -f "${OUT}/.steps.tsv"
echo
echo "Wrote $(ls -1 "${OUT}/clips/" | wc -l | tr -d ' ') clip(s) to ${OUT}/clips/"
