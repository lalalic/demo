---
name: demo
description: Execute semantic demo work from execution/demo.json against a product-owned .demo package using shared Web/iOS demo primitives, real UI drivers, recording, and fresh-UI verification.
---

# Demo

This repository is the shared runtime skill for the **demo execution lane**. It does not define a second video plan, storyboard, or timeline.


Markcut may carry out-of-band `<!-- execution {...} -->` comments. Markcut ignores those comments; Execution Director extracts them into `execution/*.json`. This demo repository never parses Markcut and only consumes `execution/demo.json`.

Canonical upstream flow:

```text
video.md (Markcut, owned by Video Director)
  -> Execution Director
  -> execution/demo.json
  -> Demo Agent
  -> this demo skill + <product>/.demo/
  -> real product UI
  -> requested media asset
```

## Input contract

Consume one item from `execution/demo.json`. The machine schema is `schemas/demo-execution-v1.schema.json` and an example is in `examples/execution/demo.json`.

A demo item carries semantic requirements only: stable id, source scene, product/surface/feature identity, intent, visible evidence, fresh-UI success criteria, presentation intent, autonomy boundary, and expected output path. It must not contain brittle selectors, coordinates, or fixed click sequences.

## Product contract

A product that supports demos owns a `.demo/` directory:

```text
.demo/
├── inventory.md          # required
├── fixtures/             # optional
├── scenarios/            # optional
├── scripts/              # optional
└── adapters/             # optional
```

The Demo Agent uses `.demo/inventory.md` to resolve product-specific targets/scenarios and loads only the assets needed for the current execution item.

## Shared primitives

The platform-neutral visual vocabulary is defined in `contracts/primitives.md`:

`step`, `spotlight`, `annotate`, `caption`, `say`, `cursor`, `highlight`, `clear`, `pause`, `resume`, `wait`, `start_recording`, `stop_recording`.

UI-driving verbs such as click/type/tap/swipe/navigation are not demo primitives; use the real UI driver (for example browser-harness or app control).

## Platform runtimes

- `web-extension/`: Chrome MV3 runtime exposing the shared browser primitives as `window.demo`.
- `ios/`: reusable Swift `DemoKit` package implementing the same semantic primitives.
- `runtimes/`: browser runtime source/build output shared with the extension and legacy runner.

## Legacy compatibility

The original storyboard runner remains for migration compatibility only. See `legacy/README.md`. New callers should not author `storyboard.md`, `demo-plan`, or `demo-script` artifacts.
