# Decision: Hash Fleet for Windows from the Mac Swift source

**Recorded:** November 22, 2026. **Status:** Documentation only. Windows implementation is on hold while the current Hash Fleet work finishes. Do not start implementation, dependency setup, builds, installs, VM provisioning, or device testing until the operator explicitly resumes it.

## First deliverable

Ship the existing **native Hash Fleet Mac desktop product on Windows**, using the same Swift code through a compatibility layer. `HashFleetMac` is the reference, not the iPhone/iPad preview. The Windows app should use native controls, with WinUI preferred. Do not build a separate dashboard, move the UI into a webview, or make a generic Xcode converter a prerequisite. The [Mac inventory](SWIFTPORT_AUDIT_RESULTS.md) records what exists and what is missing.

## What “same code” means

| Keep shared | Put behind the compatibility layer |
|---|---|
| Swift miner models, telemetry parsing, formatting, validation and math where portable. | OS-specific services: credentials, notifications, network discovery, filesystem/storage and transport where needed. |
| The desktop screen definitions, view composition, presentation state, and interaction logic where the same file can compile against both backends. | Native UI primitives, split/window presentation, appearance and assets, charts where the rendering API differs, system menus and tray integration. |
| Existing offline fixtures and behavioral expectations. | Native app entry point, target configuration, runtime dependencies and packaging per OS. |

Keep platform differences narrowly scoped. For a screen claimed as shared, both builds must compile the same checked-in screen file. No copied Windows view with the same appearance, no fake no-op for an unsupported control, and no assumption that a SwiftUI-shaped API behaves identically. If a backend cannot preserve source sharing or accessible interaction, show the limitation before choosing an alternative. The existing Mac target and behavior remain the regression baseline.

## Future validation gates

1. **Evidence of same-source reuse:** Choose a real Mac dashboard component and use its existing demo data. Document exactly which shared files both targets compile and which APIs the shim provides. The component is an engineering checkpoint, not the first product.
2. **Native Windows behavior:** Use a pinned candidate backend and verify a runnable staged executable on Windows, including the keyboard, resize behavior, focus order, Narrator and missing data. Reject a backend that cannot pass the required flows. Do not silently pivot to a duplicated UI or a different backend.
3. **Desktop delivery:** Expand to the Mac dashboard, miner detail, and agreed desktop workflows. Verify the Mac build and established workflows still work, and verify the Windows artifact on a clean machine. Document Windows gaps explicitly. Fixture-only acceptance does not authorize miner changes or certify live control.

**Not started:** No shim, Windows target, build, package, or runtime verification exists in the audited checkout. This record sets the direction only.
