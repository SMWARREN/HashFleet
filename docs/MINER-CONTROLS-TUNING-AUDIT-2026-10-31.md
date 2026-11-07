# Miner Controls-style Easy tuning and audit

Date: October 31, 2026. Final application/source revision: `fa63a75`. App version: `0.1.0`, build `12`.

## Delivered layout

Easy mode now uses the same `MinerControlsCard` and `MinerControlsHeader` components as the existing Miner Controls screen. Frequency is above Core voltage in one card. Each row has an icon and label on the left and a directly editable value with its unit on the right. There is no disclosure arrow or separate staging button required to edit either value. Accessibility text sizes stack the label and value within each row. The review card shares the same styling.

Frequency and voltage still share the existing draft with Advanced mode. Focus changes and Done stage edits only. Invalid voltage is not rounded, invalid values block mode changes/application, and reset clears invalid text. Demo, stale/offline data, hardware limits, risk acknowledgement, explicit confirmation, fresh preflight, one-write behavior and post-write verification remain in place. Tests use demo or loopback fixtures, not physical miners.

## Regressions found and fixed before installation

- The initial shared-card extraction eagerly stored its entire generic content value. Native tests crashed while constructing several existing settings pages. The card now stores an escaping content builder and evaluates it in `body`. A new regression test asserts deferred evaluation. All 21 affected settings checks passed, followed by the full final unit suite.
- The UI text replacement helper tapped a right-aligned input twice, putting the native edit menu in the way of deletion. Failure screenshots and the accessibility hierarchy confirmed this. It now focuses once at the trailing edge and waits for the keyboard. Assertions requiring the complete old value to be cleared and the exact replacement text remain unchanged. Failure-only diagnostics are retained.

## Final observed test results

| Check | Result | Evidence |
| --- | --- | --- |
| Complete native iOS unit/rendering enumeration | **1,447 / 1,447 passed**, zero skipped | Three disjoint groups: 467 + 491 + 489. Every enumerated identity matched a passed executed identity exactly once. |
| Native Mac target | **118 / 118 passed** | `build/controls12-verified-mac.xcresult` |
| Final tuning UI acceptance | **7 / 7 passed** | `build/controls12-verified-seven-ui.xcresult` |
| Additional dashboard audit recheck | **2 / 3 passed**, one failure retained | `build/controls12-broader-dashboard-audit.xcresult` |
| Swift package | **337 passed** | 53 XCTest + 284 Swift Testing tests, with real coverage. Package sources unchanged since execution. |
| Python Tools regression suite | **93 passed** | Python 3.14 run and Python 3.12 coverage run. Tool sources unchanged since execution. |
| CLI/package scripts | **66 passed** | Dashboard 18, settings 21, firmware/activity 11, Mac packaging 16. Correct binary arguments and loopback fixtures used. |
| Independent strict SwiftLint | **0 findings** | `build/sonar/controls12-final-swiftlint.json`, repeated by the final scan |
| Signed release archive/export | **Passed** | Final archive and exported app plus notification/widget extensions all report build 12 and pass strict signature verification. |

The unit identity receipt is `build/sonar/controls12-exhaustive-unit-identities.json`. Its accepted bundles are:

- `build/controls12verified-unit-1-20261031.xcresult`
- `build/controls12verified-unit-2-20261031.xcresult`
- `build/controls12verified-unit-3-20261031.xcresult`

The seven tuning tests cover standard and accessibility geometry, minimum touch targets, direct fractional-frequency entry, integer-only voltage, invalid entry, focus-change commits, reset, shared Easy/Advanced draft state, frequency-only and combined loopback payloads, risk acknowledgement, explicit confirmation, and the Demo write lock.

## Remaining UI audit boundaries

The final broader recheck passed the exact best-share formatting/native transport case and Fleet Tools/Miner Controls discoverability. The remaining failure is:

`CompactDashboardUITests/testAccessibilityTickerExposesStaticUntruncatedMinerSummaries()` expects three `fleet.ticker.item.*` elements and observes zero.

Repository history shows the dashboard's `FleetStatusTicker` embedding was removed by commit `9b9c99c` on October 3, 2026. The test still expects that removed surface. This work does not restore an old dashboard design or rewrite its acceptance assertion merely to make the audit green. The failure is included in the final Sonar result bundle, not filtered out.

The entire 182-case UI inventory was **not** completed on the final source. Earlier broader runs included three iPad/desktop geometry failures on iPadOS 27 and other interrupted/failed runs. Those are not converted into passing results. New-runtime permission/OCR/timing failures are distinct from the final accepted iOS 26.5/26.4 unit matrix. No physical-miner opt-in UI tests were enabled. There is no claim that every UI configuration passes or that nothing can ever break.

## Final Sonar evidence

Final merged bundle: `build/controls12-final-audit-sonar.xcresult`. It includes the complete passing unit matrix, native Mac tests, the seven tuning UI tests, **and the broader dashboard run with its failure**.

- Server analysis ID: `5525e2e6-f9c2-4c33-83cf-3744325d235d`.
- Analysis task: `SUCCESS`.
- Quality gate: **PASSED**, no ignored conditions.
- Overall coverage: **79.7%**. Line coverage: **79.8%**.
- New-code coverage: **90.6%**, against the unchanged 80% gate.
- Branch coverage reported by the imported Python coverage: **67.3%**.
- New violations: **0**. Reported total violations, bugs, vulnerabilities and hotspots: **0**. This is an analyzer finding count, not proof of absence of defects.
- Overall/new duplication: **0.0%**.
- The server reports **one test failure**, correctly retained from the dashboard audit.
- The plugin's aggregate test measure is **733**, not a complete census of the native executions. The fresh enumeration and exact executed-identity receipts, not that plugin aggregate, establish the 1,447-unit result.

Server evidence: `build/sonar/controls12-final-server-evidence.json`. Scanner log: `$JCODE_SCRATCH_DIR/hashfleet-controls12-final-sonar.log`.

Swift package coverage was imported from `build/sonar/audit11-core-coverage.xml`, Python from `build/sonar/controls-python-coverage.xml`. Their source trees were verified unchanged relative to the executed checks. Native coverage comes from the final application source. No prior layout's native coverage was substituted. Test execution percentage and source coverage are different: complete unit execution is **not 100% coverage**.

## Free Swift analysis improvements

See `FREE-SWIFT-ANALYSIS.md` for verified primary-source research and limitations. The pipeline now checks the expected installed sonar-apple plugin and actual Swift language registration, independently enforces strict SwiftLint, requires a selected result bundle in verification mode, and waits for the real quality gate. No rule threshold, exclusion, baseline, server, plugin version, account or model routing was relaxed or upgraded.

Automatic swarm review was attempted but did not deliver an accepted review: three workers failed before inference and the bounded research worker timed out. Independent swarm approval is not claimed. Google access was attempted but blocked; primary project/vendor pages were used rather than invented Google results.

## Delivery artifacts

The corrected signed app was installed and launched successfully on the connected phone. A fresh device app inventory confirmed `app.hashfleet`, version `0.1.0`, build `12`.

- Corrected final archive: `build/HashFleet-controls-verified-20261031.xcarchive`.
- Corrected final export: `build/controls-verified-distribution-20261031/Hash Fleet.ipa`.
- The earlier `HashFleet-controls-20261031.xcarchive` and `controls-distribution-20261031` export predate the construction fix and are **superseded**, not delivery artifacts.
- Installation/launch receipts: `$JCODE_SCRATCH_DIR/hashfleet-controls12-installed.json`, `hashfleet-controls12-launched.json`, and `hashfleet-controls12-device-apps.json`.

Implementation commits: `6956b18` (scan safeguards), `55b4d7b` (shared layout), `2289e1a` (input interaction diagnostics/fix and scan documentation), `fa63a75` (deferred card construction and regression test).
