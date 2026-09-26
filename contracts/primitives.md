# Demo primitive contract

All platform implementations expose the same semantic commands.

| Primitive | Required input | Meaning |
|---|---|---|
| `step` | `title` | Mark a narrative step and timeline boundary. |
| `spotlight` | target, optional `text` | Dim the rest of the UI and emphasize one target. |
| `annotate` | target, `text` | Place explanatory text next to a target. |
| `caption` | `text` | Show narration text without requiring speech. |
| `say` | `text` | Speak narration and show its caption. |
| `cursor` | target | Move/show a demo cursor at a target. |
| `highlight` | target | Briefly emphasize a target. |
| `clear` | — | Remove active demo overlays. |
| `pause` | — | Pause demo visual/timeline progression. |
| `resume` | — | Resume progression. |
| `wait` | `ms` | Hold for a deterministic duration. |
| `start_recording` | — | Reset and start the semantic event timeline. |
| `stop_recording` | — | Stop and return timeline events. |

A target is platform-specific only at the binding edge: web commonly uses a CSS selector or browser ref; iOS commonly uses an accessibility ref/label resolved to a frame. Storyboards should prefer targets declared by the product's `.demo/inventory.md`.

UI-driving verbs such as click, type, tap, swipe, and navigation are **not** demo primitives. They belong to the real UI driver.
