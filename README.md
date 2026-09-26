# demo

Shared demo execution skill and platform runtimes.

`video.md` remains the canonical Markcut source upstream. Execution Director extracts unresolved media requirements into typed JSON lanes. This repository owns only the **demo** lane runtime:

```text
video.md
  -> Execution Director
  -> execution/demo.json
  -> Demo Agent
  -> demo skill
       + product/.demo/
       + real UI driver
       + shared visual runtime
  -> assets/<requested-output>.mp4
```

## Public contracts

- `schemas/demo-execution-v1.schema.json` — input lane contract.
- `templates/inventory.md` — product `.demo/inventory.md` template.
- `contracts/primitives.md` — cross-platform visual primitive vocabulary.

## Product-owned demo package

```text
product/
└── .demo/
    ├── inventory.md
    ├── fixtures/
    ├── scenarios/
    ├── scripts/
    └── adapters/
```

Only `inventory.md` is required. Demo-only data and replay logic stay inside `.demo/`; the shared skill stays product-agnostic.

## Runtime implementations

- `web-extension/` injects the browser runtime into normal pages as `window.demo`.
- `ios/` contains the reusable `DemoKit` Swift package.
- `runtimes/` contains the browser runtime source and build output.

The original storyboard/recording shell pipeline is retained under a compatibility boundary and is not the public planning contract. See `legacy/README.md`.
