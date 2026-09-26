# demo

Shared demo skill and runtime for reproducible product demos.

The repository root is itself an installable skill. It combines three things only:

1. **Demo skill** — reads a product's `.demo/` package, authors/executes storyboards, records and clips demos.
2. **Shared visual runtime** — Chrome extension for web and `DemoKit` Swift package for iOS, both implementing the same primitive vocabulary.
3. **Product contract** — each product owns `.demo/inventory.md` and optional fixtures/scenarios/scripts.

```text
Demo Agent
    ↓
this demo skill
    ├── product/.demo/
    ├── shared visual runtime
    └── real UI driver (browser-harness / app control)
             ↓
          real product
             ↓
      demo.mp4 + clips
```

## Product layout

```text
my-product/
└── .demo/
    ├── inventory.md
    ├── fixtures/
    ├── scenarios/
    └── scripts/
```

`inventory.md` is an inventory/capability declaration, not executable runtime code. Demo-only data and replay assets live beside it under `.demo/`.

## Repository layout

```text
SKILL.md
contracts/primitives.md
runtimes/                 # migrated web runtime
scripts/                  # migrated storyboard runner/recording pipeline
templates/
web-extension/            # Chrome MV3 wrapper for the web runtime
ios/                      # DemoKit Swift Package
examples/product-demo/    # minimal .demo example
legacy-design.md           # preserved original demo-video design
```

The initial code is intentionally a migration of the previously working `copilot-infinite/demo-video` and NeoX demo primitives, not a redesign.
