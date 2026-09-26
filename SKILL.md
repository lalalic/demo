---
name: demo
description: Create reproducible product demos from a product-owned .demo package. Uses a shared demo primitive runtime for web/Chrome and iOS, reads .demo/inventory.md plus optional fixtures/scenarios/scripts, composes a storyboard, drives the real product UI, records the result, and emits reusable clips.
---

# Demo

Use this skill to plan and execute product demos without teaching the shared engine product-specific behavior.

## Product contract

A product that supports demos owns a `.demo/` directory at its repository root:

```text
.demo/
├── inventory.md          # required: what can be demonstrated
├── fixtures/             # optional: deterministic demo data
├── scenarios/            # optional: reproducible scenario definitions
├── scripts/              # optional: replay / state-setup scripts
└── adapters/             # optional: product-specific state injection helpers
```

Only `.demo/inventory.md` is required. Keep demo-only data and replay logic inside `.demo/` rather than scattering it through product source. A product may expose a minimal generic bridge when external state injection is impossible, but the demo assets remain in `.demo/`.

Start from `templates/inventory.md`.

## Shared primitive contract

The visual primitive vocabulary is platform-neutral and defined in `contracts/primitives.md`:

`step`, `spotlight`, `annotate`, `caption`, `say`, `cursor`, `highlight`, `clear`, `pause`, `resume`, `wait`, `start_recording`, `stop_recording`.

The demo agent should use this vocabulary rather than inventing platform-specific overlay commands.

## Platform runtimes

### Web / Chrome extension

`web-extension/` installs the shared browser runtime into every normal web page as `window.demo`. It only provides demo visuals/timeline. Browser navigation and real UI actions remain the responsibility of browser-harness/agent-browser.

For development, load `web-extension/` as an unpacked Chrome extension. The existing runner also falls back to direct runtime injection when the extension is not installed.

### iOS

`ios/` is a Swift Package (`DemoKit`). An app includes it, owns the element-resolution bridge, places `DemoOverlayView` over its root view, and exposes the same primitive commands through its MCP/app control layer.

## Workflow

1. Locate `<product>/.demo/inventory.md`.
2. Read only the capabilities needed for the requested demo: surface, targets/selectors, scenarios, and recipes.
3. If deterministic state is needed, use `.demo/fixtures`, `.demo/scenarios`, and `.demo/scripts` to prepare it while keeping the real product rendering path.
4. Compose a short `storyboard.md` from `templates/storyboard.md`.
5. Execute real UI actions through the platform driver and visual primitives through the shared demo runtime.
6. Record the full run and emit `events.json`, `demo.mp4`, and per-step clips.

Do not invent selectors/scenarios that are absent from the product inventory. If the product lacks a needed capability, update its `.demo/` package first.

## Runner

The migrated v1 runner remains under `scripts/` and `runtimes/`:

```bash
./scripts/run.sh --target=web --storyboard=/path/storyboard.md --out=/path/out --url=https://example.com
./scripts/run.sh --target=extension --storyboard=/path/storyboard.md --out=/path/out
./scripts/run.sh --target=ios --storyboard=/path/storyboard.md --out=/path/out --device-mcp-url=http://...
```

The runner is intentionally kept compatible with the original `demo-video` implementation while this repository becomes the canonical shared home.
