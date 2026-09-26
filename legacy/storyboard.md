# Storyboard — `<demo title>`

> Caller fills this in (typically the `repo-marketing` skill).
> Each `## Step N:` block becomes a clip in `clips/NN-<slug>.mp4`.

## Grammar (one command per indented line)

```
step title="..."                             # NEW STEP — required first line of each ## block
caption text="..."                           # bottom caption (no audio on web)
say text="..."                               # TTS narration (mixed in for web; native AVSpeech for iOS)
spotlight ref=r5 text="..."                  # dim screen + spotlight + tooltip
spotlight selector=".my-button" text="..."   # web: CSS selector form
annotate ref=r5 text="..."                   # tooltip only (no dim)
highlight ref=r5                             # brief pulse
cursor ref=r5                                # animate cursor to element
wait ms=800                                  # pause overlays
clear                                        # remove all overlays
pause                                        # freeze timeline (rare)
resume                                       # unfreeze (rare)

# Action verbs (driver-specific):
app_agent tap ref=r5            # iOS
app_agent type ref=r5 text="hi" # iOS
app_agent swipe direction=up    # iOS
agent-browser click @e1         # web
agent-browser fill @e1 "hello"  # web
agent-browser press Enter       # web
```

Comments start with `#` and are ignored.

## Example

## Step 1: Welcome screen

  step title="Welcome to MeetMate"
  caption text="3 taps to capture your meeting"
  say text="Welcome to MeetMate. Let's see how it works."
  wait ms=600
  spotlight ref=r3 text="Tap here to begin"
  app_agent tap ref=r3
  clear

## Step 2: Pick a meeting

  step title="Pick a meeting"
  say text="Pick the meeting you want to capture."
  spotlight ref=r7 text="Today's standup"
  app_agent tap ref=r7
  clear

## Step 3: Done

  step title="That's it"
  caption text="Recording starts automatically"
  say text="That's it. MeetMate handles the rest."
  wait ms=1200
  clear
