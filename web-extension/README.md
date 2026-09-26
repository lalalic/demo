# Demo Runtime Chrome extension

This MV3 extension installs the shared browser demo runtime into normal web pages as `window.demo`.

It intentionally does **not** click, type, navigate, mock APIs, or own product fixtures. Those remain with the real UI driver and the product's `.demo/` package.

Available primitives are defined in `../contracts/primitives.md`.

Load this directory as an unpacked extension during development. The demo runner can still inject `../runtimes/demo-runtime.js` directly when the extension is unavailable.
