# DemoKit

Shared iOS implementation of the demo primitive contract.

An app provides a `DemoTargetResolving` implementation backed by its accessibility/UI scanner, creates one `DemoRuntime`, overlays `DemoOverlayView(runtime:)` at the app root, and maps its MCP/control command to `DemoRuntime.execute(_:)`.

This package deliberately does not depend on NeoX/AppAgent MCP types. That keeps the visual runtime reusable by any iOS app while allowing each host app to use its existing control transport.
