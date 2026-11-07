# Page redesign handoff · 2026-09-10

## Approval boundary

The requested functional updates are implemented separately. The generated page layouts are proposals only. Do not implement them until the user selects a direction. The source app and its tested contracts are authoritative, not text or invented controls in a generated image.

- [Approval gallery](research/page-redesign-2026/index.html)
- [Source screenshot inventory](PAGE-CAPTURE-INVENTORY-2026-09-10.md)
- [Per-page context, generation prompts and original-image hashes](research/page-redesign-2026/manifest.json)

The gallery groups 33 route families and explicit states into 56 original screenshots. It contains 10 generated images, including multi-screen boards and refinements. This does not mean the app has 56 separate pages. Diagnostics, history, offline settings and appearance variants are states. Read/PATCH/restart/upload screens share endpoint-editor infrastructure.

## Cross-page requirements

1. Use existing FleetTheme neutral graphite/orange tokens. Do not reproduce blue/cyan casts from generated boards. Preserve the existing logo and black launch unless a separate artwork change is approved.
2. Keep native navigation, Dynamic Type, VoiceOver, minimum hit targets, keyboard-safe actions, Reduce Motion and Reduce Transparency. Native system pickers and system Siri/Control Center are not redesigned by these images.
3. Use bounded numeric transitions only on changed readings, with stable view identity. Never turn missing, stale or unavailable data into zero. No continuous animation loop.
4. Keep demo read-only. Public lookup examples are synthetic, not live financial results. Show source and observation time. CKPool address submission retains provider/IP disclosure, and no wallet balance is inferred.
5. Keep exact target, request and risk review. Native power-user mode is opt-in, per-miner, limited to 10 minutes and resets on background. It can skip typed APPLY only for recognized unmodified native settings drafts. Raw/custom JSON, voltage, credentials, pool routing and uploads retain typing. Nothing sends solely because APPLY was typed.
6. Siri restart/frequency/manual-fan actions require device authentication, fresh telemetry, exact target/value/risk confirmation and revalidation before writing. Manual fan speed disables automatic fan control. Firmware wire ranges are not safe operating ranges.
7. Custom JSON must remain a local, nonempty object draft, at most 256 KiB. Preserve unknown keys and exact JSONValue numeric semantics. Editing/importing/formatting does not write. Stage routes to existing typed review.
8. Guided pool selection prepares a draft only. Full-slot replacement semantics and credential masking must remain. No invented tuning presets, safe-range badges, optimization guarantees or mining-success claims.
9. Widget and Live Activity surfaces show aggregate snapshots only, with explicit opt-in where required. They do not become live background miner sockets or tuning controls.

## Corrections identified during image review

- The `refinements` board supersedes widget/Live Activity columns on `system` and the compatibility column on `diagnostics`.
- The refinement compatibility subtitle incorrectly attributes field coverage solely to `/api/system/asic`. Remove that subtitle. Reported settings coverage comes from system info. Exact checks are GET `/api/system/info` and GET `/api/system/asic`, not PATCH or WebSocket probes.
- Endpoint paths and method badges must be copied from `Sources/HashFleetCore/MinerEndpoint.swift`, not OCR of the image. Binary upload variants are POST `/api/system/OTA` and POST `/api/system/OTAWWW`.
- The launch concept is exploratory and does not authorize replacement of the black logo launch. Pool icon demo remains a preview, not a pool picker.
- Use existing app scope for CKPool lookup and About. Generated coin options or separate privacy/license subpages are not automatically new requirements.
- Some boards compress content into a single frame. Implement real scrolling, not smaller inaccessible text or fixed heights. Preserve navigation back buttons even where a generated frame omits one.

## Implementation gate

For each selected route, use its linked current screenshots, source view and note in the manifest. Before claiming the redesign complete, run native route/UI acceptance in light/dark, large Dynamic Type, Reduce Motion and keyboard states. Hardware writes must be tested against the loopback fixture, not a real miner. Siri voice and system surfaces need separate real-device validation.
