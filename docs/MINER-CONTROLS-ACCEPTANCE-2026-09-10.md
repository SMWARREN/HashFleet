# Miner controls and page-design acceptance · 2026-09-10

## Implemented

- Inner-page numeric changes use the existing bounded spring/numeric text transition with Reduce Motion fallback. Includes miner detail, diagnostic values, live-console counters and shared public-insight rows used by CKPool.
- Siri/App Intents: Restart Fleet Miner, Set Fleet Miner Frequency and Set Fleet Miner Fan Speed. Requires local device authentication, exact saved target/value/risk confirmation, fresh shape-valid telemetry before and after confirmation, target/gate revalidation and cancellation checks. Manual fan speed sends both `autofanspeed: 0` and the requested percentage. Frequency bounds are wire constraints, not hardware-safe limits.
- Optional power-user review session: one miner, 10 minutes, reset on background/demo and nonpersistent. Only unchanged recognized native settings drafts may omit typed APPLY. Risk acknowledgment and final Send remain. Raw/custom JSON, voltage, credentials, pool routing and uploads retain typing.
- Typing APPLY dismisses the keyboard and reveals the Send action without another manual scroll. Typing alone never sends. Reduce Motion avoids animated scrolling.
- Custom JSON: nonempty object, 256 KiB limit, unknown fields and exact JSONValue number semantics preserved. Local format/paste/import/stage flow. Staging always routes to existing typed request review, including while native power mode is enabled.
- Capability labels no longer imply a successful info GET established support for a write endpoint.

## Passing checks

- `axe-controls-final-native.log`: 395 native tests in 36 suites.
- `axe-controls-core.log`: 146 core tests in 17 suites.
- `axe-controls-final-ui.log`, retained result bundle `axe-controls-final-ui.xcresult`: all four RealModeControlUITests passed together on final application source. Verifies offline cached lockout, native power review/cancel/exact payload/background reset, custom JSON keyboard/draft/typed gate, and native hostname cancellation/invalid token/APPLY auto-reveal/exactly-one PATCH. All writes go to a local fixture, not a real miner.
- Screenshot iterations repaired incorrect settings titles, hidden endpoint routes and a disclosure-center tap that did not expand diagnostics. Final `final-diagnostics.log` passes an explicit Expanded-state and visible-header assertion. Endpoint/live/compatibility capture passed in `final-variants.log`. Settings/custom/upload capture passed in `settings-root2.log`.
- Gallery: 56 original screenshots in 33 route families and explicit states, with 10 generated concept images. All groups have source screenshots. All 66 PNG signatures/hashes, local image links and fragment targets validated. Browser launch/file opening is suppressed in this harness, so browser-rendered gallery acceptance is not claimed.
- Clean signed iPhone build passed (`axe-controls-device.log`). Deep strict code signature verification passed. The app contains archived English Siri language data in `Metadata.appintents/nlu`.

Logs/result bundles are under `$HOME/.jcode/scratch/`. Screenshot-specific logs are in `axe-page-capture/`.

## Delivery and limitations

No real miner was restarted or modified. Actual Siri voice invocation, cold-launch system intent behavior and real hardware responses are not device-verified. System authentication policy and confirmation plumbing are compiled and covered by executor/policy tests, not a substitute for real Siri UI acceptance.

Functional source commit `7372752` (plus numeric-motion commit `8d14a5b`) was installed on the paired iPhone 14 Pro Max after one CoreDevice tunnel retry. Receipt: `axe-controls-install-retry.json`, installation completed at approximately 13:07 UTC. A normal no-argument remote launch then hit another CoreDevice tunnel timeout, so launch is not confirmed. The user can open the installed app directly. No real miner commands were executed.

The generated redesign is not implemented. [Open the approval gallery](research/page-redesign-2026/index.html) and read [handoff corrections](PAGE-REDESIGN-BRIEFS-2026-09-10.md). Screenshot variants are not counted as separate pages. Native document pickers, share sheets, system Siri/Control Center and every generic API operation are not exhaustively captured.

Existing unrelated AppIcon/brand artwork and compiler-object artifacts remain excluded from the control commits. Application source uses iOS 17 minimum and existing availability gates. FPS diagnostics remain disabled by default.
