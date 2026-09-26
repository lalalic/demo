# Skill: `demo` — design (v2)

> Status: **active**. v1 was "pure executor, caller hands in
> storyboard.md". v2 is **compose + execute**: the skill itself reads
> the app's `.demo-runtime.md` manifest and authors the storyboard
> from a plain-language scene description, then executes it.

## 1. Purpose

A single skill that takes a plain-language demo intent (e.g. "Show
how MeetMate dissolves the language barrier") plus a path to the
app's `.demo-runtime.md` manifest, and produces a self-contained
demo folder under `<repo>/.market/assets/demos/<slug>/` containing:

- `script.md` (the intent, for provenance)
- `storyboard.md` (DSL program composed by the agent)
- `demo.mp4` (full walkthrough with overlays + TTS baked in)
- `clips/NN-<step-slug>.mp4` (one per step)
- `events.json`, `snapshot.json` (introspection)

The skill works across three surfaces — **iOS app, web app, Chrome
extension** — with a unified DSL.

Unifies the existing runtimes:

| Surface | Runtime | Driver |
|---------|---------|--------|
| iOS | `copilot-ios/AppAgent/Sources/{DemoRuntime, DemoOverlayView}.swift` + MCP `demo` tool | `app_agent` MCP + `demo` MCP |
| Web | `runtimes/demo-runtime.ts` (~475 lines) injected as `window.demo` | `agent-browser` (CDP) |
| Chrome extension | same `runtimes/demo-runtime.ts` injected into the extension's `chrome-extension://...` page | `agent-browser` |

All three speak the same DSL → one demo script (story.md) renders
identically on any target.

## 2. Unified DSL

A **single command vocabulary** maps 1:1 across surfaces:

| Command | Params | iOS | Web |
|---------|--------|-----|-----|
| `step` | `title` | `demo step title=…` MCP | `window.demo.step(title)` |
| `spotlight` | `ref \| label \| selector`, `text?` | `demo spotlight ref=r5 text=…` | `window.demo.spotlight(sel, text)` |
| `annotate` | `ref \| label \| selector`, `text` | `demo annotate …` | `window.demo.annotate(sel, text)` |
| `caption` | `text` | `demo caption text=…` | `window.demo.caption(text)` |
| `say` | `text` | `demo say text=…` (TTS via AVSpeechSynthesizer) | `window.demo.say(text)` (Web Speech API) |
| `cursor` | `ref \| selector` | `demo cursor ref=…` | `window.demo.cursorTo(sel)` |
| `highlight` | `ref \| selector` | `demo highlight ref=…` | `window.demo.highlight(sel)` |
| `clear` | — | `demo clear` | `window.demo.clear()` |
| `pause` | — | `demo pause` | `window.demo.pause()` |
| `resume` | — | `demo resume` | `window.demo.resume()` |
| `wait` | `ms` | `demo wait ms=…` | `window.demo.wait(ms)` |
| `start_recording` | — | `demo start_recording` (event timeline) | `window.demo.startRecording()` |
| `stop_recording` | — | returns events JSON | returns events JSON |

**Action verbs** (`tap`, `type`, `swipe`, `click`, `fill`) come from
the *driver*, not the demo runtime:

- iOS: `app_agent tap ref=r5`
- Web: `agent-browser click @e1`

The skill issues an interleaved sequence of demo + driver commands.

## 3. Pipeline

```mermaid
flowchart LR
    INPUT[storyboard.md\n+ target spec\n(from caller)] --> S1[step 1: connect target]
    S1 --> S2[step 2: snapshot\n(write snapshot.json)]
    S2 --> S3[step 3: bind refs\n(map storyboard refs → selectors)]
    S3 --> S4[step 4: capture\n(start recording + drive)]
    S4 --> S5[step 5: clip\n(ffmpeg split per step event)]
    S5 --> S6[step 6: mix VO\n(web only: ffmpeg + edge-tts wavs)]
    S6 --> OUT[demo.mp4 + clips/ + events.json]
```

No LLM calls inside the skill — every step is a deterministic shell
operation. The caller (`repo-marketing`) is responsible for
any generative work.

## 4. Artifacts (per demo)

Default output directory: `<repo>/.market/assets/demos/<slug>/`.
The skill knows this convention but accepts `--out=<path>` for
standalone use.

```
<repo>/.market/assets/demos/<slug>/
├── storyboard.md       # input (handed in by caller)
├── snapshot.json       # captured element tree (refs from app_agent or @e1)
├── events.json         # actual timeline from runtime's recording
├── demo.mp4            # full screen capture
└── clips/
    ├── 01-step-name.mp4
    ├── 02-step-name.mp4
    └── ...
```

The `repo-marketing` skill consumes `clips/*.mp4` (or
`demo.mp4` cropped) as `props.background` for `Demo` scenes.

## 5. Surface adapters

Single skill, three adapter sub-procedures:

### 5.1 iOS adapter (`scripts/run-ios.sh`)

1. Read MCP URL from device (user provides via `.env.local` or CLI arg).
2. Call `app_agent command=snapshot` → write `snapshot.json`.
3. Walk storyboard.md commands; route `demo *` → MCP `demo` tool,
   route `app_agent *` → MCP `app_agent` tool, await each.
4. **Recording**:
   - Simulator: `xcrun simctl io booted recordVideo demo.mp4`
     started before step 1, killed after `clear` of the last step.
   - Physical device (v1): script **prints instructions** to start
     QuickTime "New Movie Recording" (⌘+⌥+N, pick the device)
     and waits for ENTER, then runs the demo, then prompts user to
     stop QuickTime and save as `demo.mp4` in the output dir.
5. iOS `demo say` plays TTS via AVSpeechSynthesizer, captured
   in-line by both simulator and QuickTime recordings. **No
   post-mix needed.**

### 5.2 Web adapter (`scripts/run-web.sh`)

1. Caller provides target URL (web app or `chrome-extension://<id>/page.html`).
2. `agent-browser navigate <url>`.
3. Inject `runtimes/demo-runtime.js` (compiled from `demo-runtime.ts`)
   via `agent-browser eval --file=…`.
4. `agent-browser snapshot` → write `snapshot.json` (with `@e1` refs).
5. Call `window.demo.mapRefs(refs)` so `agent-browser` refs are
   addressable by the demo runtime.
6. **TTS pre-pass**: walk storyboard.md, for every `say text="..."`
   line, call edge-tts to produce `vo/<step-N>-<seq>.wav`. Replace
   `say` calls in the runtime invocation with `caption` (text-only,
   no Web Speech API — silent during recording). Track each wav's
   `event.t` for post-mix.
7. Walk storyboard.md commands; route `demo *` → eval
   `window.demo.<cmd>(…)`, route action verbs → `agent-browser <verb>`.
8. **Recording**: `agent-browser record start demo.webm` (CDP
   screencast) before step 7, `record stop` after.
9. ffmpeg convert webm → mp4 + **mix in** the per-`say` wavs at
   their captured timestamps:
   ```bash
   ffmpeg -i demo.webm \
     -i vo/say-1.wav -i vo/say-2.wav \
     -filter_complex "[1]adelay=1500|1500[a1]; [2]adelay=4200|4200[a2]; [a1][a2]amix=inputs=2[mix]" \
     -map 0:v -map "[mix]" -c:v libx264 demo.mp4
   ```

### 5.3 Chrome-extension adapter

Same as web adapter, with one extra setup step: load the unpacked
extension into the agent-browser-controlled Chrome instance via
`--load-extension=<path>` flag, then navigate to the extension's
options/popup page (`chrome-extension://<id>/popup.html`).

## 6. Decisions

| # | Topic | Decision |
|---|-------|----------|
| 1 | Storyboard source | **Skill composes it** from a plain-language scene description + the app's `.demo-runtime.md` manifest. v1's "caller hands in storyboard" model is still supported (call `run.sh` directly) but the skill's primary entry point is compose+execute. |
| 2 | TTS for web | **edge-tts pre-pass + ffmpeg post-mix.** Web Speech API not used. iOS uses native TTS in-recording. |
| 3 | iOS device recording | **Manual QuickTime for v1.** Simulator uses `simctl io recordVideo`. |
| 4 | Output path | **Defaults to `<repo>/.market/assets/demos/<slug>/`** (one self-contained folder per demo). Override with `--out=<path>`. |
| 5 | Web target mode | **Always headed** (visible Chrome via agent-browser on port 9222). |
| 6 | Ref binding (web) | agent-browser `snapshot` returns `@e1`+CSS selector → feed into `window.demo.mapRefs()`. |
| 7 | Languages | **English only in v1.** |
| 8 | Multi-target | **One target per run.** Caller invokes the skill once per surface. |

## 7. Per-step clipping (`scripts/clip.sh`)

`events.json` contains `{t, type:"step", title}` markers. After full
recording:

```bash
for each step in events.json (where event.type == "step"):
    start = event.t (ms)
    end = next step's t (or end-of-video)
    ffmpeg -i demo.mp4 -ss <start>ms -to <end>ms -c copy clips/NN-<slug>.mp4
```

User/caller picks which clips go into the marketing video — or uses
the full `demo.mp4` for a "full walkthrough" video type.
## 8. Story format (`templates/storyboard.md`)

Plain markdown. Each `## Step N:` block = one step. Commands use a
tiny YAML-ish grammar (one per line, indented under step):

```markdown
## Step 1: Open the app

  step title="Welcome to MeetMate"
  caption text="3 taps to capture your meeting"
  say text="Welcome to MeetMate. Let's see how it works."
  wait ms=800
  spotlight ref=r3 text="Tap to start"
  app_agent tap ref=r3   # <- action verb (driver-specific)
  clear

## Step 2: Pick a meeting
  ...
```

Parser is a 30-line awk reader (`scripts/parse-storyboard.sh`) → emits
command records `{step, cmd, args}` to stdout for the adapter to dispatch.

## 9. Skill layout

```
.github/skills/demo-video/
├── SKILL.md                # main entry
├── design.md               # this file
├── runtimes/
│   ├── demo-runtime.ts     # source (canonical location)
│   └── demo-runtime.js     # compiled bundle (used by web/extension adapter)
├── templates/
│   └── storyboard.md       # skeleton + grammar examples (caller fills this in)
└── scripts/
    ├── run.sh              # entry: routes by --target=ios|web|extension
    ├── run-ios.sh          # iOS adapter (MCP)
    ├── run-web.sh          # web + chrome-extension adapter (agent-browser)
    ├── parse-storyboard.sh # storyboard.md → command stream
    ├── mix-vo.sh           # web only: edge-tts pre-pass + ffmpeg mix
    └── clip.sh             # ffmpeg split by step events
```

## 10. Non-goals (v1)

- Authoring tool / GUI for storyboards
- Multi-language narration (English only)
- Cross-device coordination (one target per run)
- Editing / post-production beyond ffmpeg clipping
- LLM-driven storyboard generation (caller's job)
