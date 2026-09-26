#!/usr/bin/env bash
# parse-storyboard.sh — convert storyboard.md → JSONL command stream on stdout
#
# Usage: parse-storyboard.sh <path/to/storyboard.md>
#
# Output: one JSON object per line:
#   {"step": <N>, "step_title": "...", "cmd": "spotlight", "args": {"ref":"r5","text":"..."}}
#
# Grammar (per design.md §8):
#   - "## Step N: <title>" begins a step block
#   - Indented lines (>=2 spaces) within a step block are commands
#   - Command syntax: <cmd> [key=value | key="quoted value"]*
#   - Comments (#) and blank lines ignored
#   - Action verbs `app_agent`/`agent-browser` are passed through verbatim
#     as cmd="app_agent" args={"sub":"tap", ...} etc.

set -euo pipefail

# Treat input as bytes (handles UTF-8 in say/keyboard text safely on macOS awk)
export LC_ALL=C

if [[ $# -ne 1 ]]; then
  echo "usage: $0 <storyboard.md>" >&2
  exit 1
fi

awk '
function trim(s) { sub(/^[[:space:]]+/, "", s); sub(/[[:space:]]+$/, "", s); return s }

# JSON-escape a string
function jesc(s,    r) {
  r = s
  gsub(/\\/, "\\\\", r)
  gsub(/"/,  "\\\"", r)
  gsub(/\n/, "\\n",  r)
  gsub(/\t/, "\\t",  r)
  return r
}

# Tokenize a command line into cmd + key=value pairs (handling "quoted").
# Emits a JSON object with cmd, args.
function emit_cmd(line, step_n, step_title,    cmd, rest, args, key, val, in_q, c, i, n, char, buf, subcmd, raw, sp) {
  # First token is the cmd
  n = split(line, parts, /[[:space:]]+/)
  cmd = parts[1]
  rest = ""
  for (i = 2; i <= n; i++) rest = rest (rest ? " " : "") parts[i]

  # For action verbs: extract sub-command, pass rest verbatim as "raw".
  # This avoids parser collisions with `#` (CSS ids), quoted strings, JS expressions, etc.
  if (cmd == "agent-browser" || cmd == "app_agent") {
    if (split(rest, sp, /[[:space:]]+/) >= 1) {
      subcmd = sp[1]
      raw = rest
      sub(/^[[:space:]]*[^[:space:]]+[[:space:]]*/, "", raw)
      args = "\"sub\":\"" jesc(subcmd) "\",\"raw\":\"" jesc(raw) "\""
    } else {
      args = ""
    }
    printf "{\"step\":%d,\"step_title\":\"%s\",\"cmd\":\"%s\",\"args\":{%s}}\n", step_n, jesc(step_title), jesc(cmd), args
    return
  }

  args = ""
  i = 1
  L = length(rest)
  while (i <= L) {
    # skip whitespace
    while (i <= L && substr(rest, i, 1) ~ /[[:space:]]/) i++
    if (i > L) break
    # comment?
    if (substr(rest, i, 1) == "#") break
    # parse key
    key = ""
    while (i <= L && substr(rest, i, 1) != "=" && substr(rest, i, 1) !~ /[[:space:]]/) {
      key = key substr(rest, i, 1); i++
    }
    if (i > L || substr(rest, i, 1) != "=") {
      # bare flag — for app_agent/agent-browser, the first bare token is the sub-command;
      # otherwise treat as boolean true.
      if ((cmd == "app_agent" || cmd == "agent-browser") && args == "") {
        args = "\"sub\":\"" jesc(key) "\""
        continue
      }
      val = "true"
    } else {
      i++  # skip =
      # quoted?
      if (substr(rest, i, 1) == "\"") {
        i++
        val = ""
        while (i <= L && substr(rest, i, 1) != "\"") {
          if (substr(rest, i, 1) == "\\" && i < L) {
            val = val substr(rest, i, 2); i += 2
          } else {
            val = val substr(rest, i, 1); i++
          }
        }
        i++  # skip closing "
      } else {
        val = ""
        while (i <= L && substr(rest, i, 1) !~ /[[:space:]]/) {
          val = val substr(rest, i, 1); i++
        }
      }
    }
    args = args (args ? "," : "") "\"" jesc(key) "\":\"" jesc(val) "\""
  }

  printf "{\"step\":%d,\"step_title\":\"%s\",\"cmd\":\"%s\",\"args\":{%s}}\n", step_n, jesc(step_title), jesc(cmd), args
}

BEGIN { step_n = 0; step_title = "" }

/^##[[:space:]]+Step[[:space:]]+[0-9]+:/ {
  step_n++
  step_title = $0
  sub(/^##[[:space:]]+Step[[:space:]]+[0-9]+:[[:space:]]*/, "", step_title)
  next
}

# Skip code fences
/^```/ { next }

# Indented command line within a step block
step_n > 0 && /^[[:space:]]{2,}/ {
  line = trim($0)
  if (line == "" || line ~ /^#/) next
  emit_cmd(line, step_n, step_title)
  next
}
' "$1"
