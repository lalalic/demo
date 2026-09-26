# <Product> — Demo Inventory

> Product-owned declaration consumed by the shared `demo` skill. Keep this file at `.demo/inventory.md`.

## Surface

- **type**: `<web | extension | ios>`
- **driver**: `<browser-harness | app control/MCP>`
- **target**: `<URL, bundle id, or launch instruction>`
- **prerequisites**:
  - `<login/state requirement>`

## Targets

Only declare stable targets a demo execution item may reference at runtime.

| Name | Selector / ref / label | Purpose |
|---|---|---|
| `<chat-input>` | `<selector>` | `<what it is>` |

## Scenarios

Deterministic product states or replay sequences. Implementation and data live under this product's `.demo/` directory.

| Name | What the viewer sees | Apply |
|---|---|---|
| `<scenario>` | `<result>` | `<script/trigger>` |

## Recipes

Reusable product-specific action fragments. Keep visual overlays in the shared primitive vocabulary and real UI actions in the platform driver.

### <recipe name>

```text
<commands>
```
