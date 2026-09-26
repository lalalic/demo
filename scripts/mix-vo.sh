#!/usr/bin/env bash
# mix-vo.sh — mix per-`say` edge-tts wavs into demo video at recorded timestamps.
#
# Usage: mix-vo.sh <out-dir>
#
# Reads:  <out>/demo.webm  (or .mp4)
#         <out>/events.json   (events with type="say", t in ms, audio="vo/say-N.wav")
#         <out>/vo/*.wav      (pre-generated edge-tts files)
# Writes: <out>/demo.mp4 (replaces input if input was webm; in-place if mp4)

set -euo pipefail

OUT="${1:?usage: mix-vo.sh <out-dir>}"
EVENTS="${OUT}/events.json"

# Pick input
if [[ -f "${OUT}/demo.webm" ]]; then
  INPUT="${OUT}/demo.webm"
elif [[ -f "${OUT}/demo.mp4" ]]; then
  INPUT="${OUT}/demo.mp4"
else
  echo "error: no demo.webm or demo.mp4 in ${OUT}" >&2
  exit 1
fi

# Collect (delay_ms, wav_path) for every say event.
PAIRS=$(python3 - "$EVENTS" "$OUT" <<'PY'
import json, os, sys
events_path, out_dir = sys.argv[1], sys.argv[2]
with open(events_path) as f:
    events = json.load(f)
pairs = []
for e in events:
    if e.get("type") != "say": continue
    audio = e.get("audio")
    if not audio: continue
    full = os.path.join(out_dir, audio) if not os.path.isabs(audio) else audio
    if not os.path.exists(full):
        sys.stderr.write(f"warn: missing {full}\n")
        continue
    pairs.append((int(e["t"]), full))
pairs.sort()
for t, p in pairs:
    print(f"{t}\t{p}")
PY
)

if [[ -z "$PAIRS" ]]; then
  echo "→ no say events; just transcoding to mp4"
  ffmpeg -loglevel error -y -i "$INPUT" -c:v libx264 -c:a aac "${OUT}/demo.mp4"
  [[ "$INPUT" == "${OUT}/demo.webm" ]] && rm "$INPUT"
  exit 0
fi

# Build ffmpeg input args + filter graph.
INPUTS=(-i "$INPUT")
FILTER=""
MIX_LABELS=""
i=0
while IFS=$'\t' read -r delay_ms wav; do
  INPUTS+=(-i "$wav")
  IDX=$((i + 1))  # 0 is the video
  FILTER+="[${IDX}:a]adelay=${delay_ms}|${delay_ms}[a${IDX}];"
  MIX_LABELS+="[a${IDX}]"
  i=$((i + 1))
done <<< "$PAIRS"

FILTER+="${MIX_LABELS}amix=inputs=${i}:dropout_transition=0[mix]"

OUTFILE="${OUT}/demo.mp4"
TMPOUT="${OUT}/demo.mixed.mp4"
echo "→ mixing $i voiceover clip(s) into $OUTFILE"
ffmpeg -loglevel error -y "${INPUTS[@]}" \
  -filter_complex "$FILTER" \
  -map 0:v -map "[mix]" \
  -c:v libx264 -c:a aac \
  "$TMPOUT"
mv "$TMPOUT" "$OUTFILE"

[[ "$INPUT" == "${OUT}/demo.webm" ]] && rm "$INPUT"
echo "Done: $OUTFILE"
