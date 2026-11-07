# Restrained native Mac layout correction

Date: October 27, 2026 (UTC), following operator feedback on October 26 at 23:52 and 23:54 UTC. This supersedes the aggressive primary-card arrangement in `560d482` without undoing the larger Mac artwork or the existing responsive smaller-card behavior.

## Requested outcome

Keep the hashrate summary and history chart full width. Do not put an entire stack of primary telemetry beside one stretched control panel. Short pages should read vertically rather than spreading three sections into one shallow row with unused space underneath. Retain columns for genuinely related smaller cards and sufficiently dense pages.

## Implementation

- `desktopPrimarySections` stacks the hashrate hero, history chart, ASIC/pool telemetry, temperature/power pair and natural-height control panel. The first three retain the full available content width regardless of the secondary-column preference.
- The control panel no longer requests infinite vertical expansion. Its tuning/settings pair and four quick actions still use their existing responsive row layout. The narrow type-erased navigation boundary remains intact.
- Existing best-share/identity and diagnostics/pool pairs remain paired, with a maximum of two columns. No new arbitrary fixed heights, page scale transformations or viewport-height feedback loop were introduced.
- Mac settings and network reading pages require enough cards for at least two rows before using multiple columns. One to three ordinary sections stack, four or five permit at most two columns, and six or more permit at most three when width and text size allow. Full-width introductions are excluded from that count.
- The minimum-row policy is native-only. The shared mobile grid branch and accessibility single-column rule remain unchanged. Dashboard hashrate and chart structure, larger Mac artwork, saved miner identities and command authorization were not changed by this correction.

## Requirement-to-check evidence

| Requirement | Observed checks |
| --- | --- |
| Primary telemetry remains full width | The production-view runner renders the actual `desktopPrimarySections`, hero, history and control views. It checks the hero's trailing surface, center of the history surface, vertical combined height and control surface across five widths in both themes. Mounted Release AX anchors and the original window capture independently show the full-width summary and chart. |
| No huge stretched control column | The actual rendered primary stack includes natural-height controls below the primary readings. The mounted 2056-point Release window reports a 92-point tuning/settings row and a 70-point quick-action row, below the chart and telemetry rather than alongside them. |
| Short pages stack instead of forming a shallow three-column row | New policy tests cover zero through six cards and invalid inputs. A new ImageRenderer test proves three actual layout children span the full width in separate rows at 900 and 1756 points, with normal and accessibility text. An independent mounted Energy page check measures all three sections at the same x=324 and width=1716 points, in nonoverlapping vertical order. |
| Related smaller cards stay aligned | Existing geometry, row-height, odd-item and real production-surface checks remain. Mounted temperature/power and tuning/settings pairs retain matching row origins and heights. |
| Existing navigation and mobile behavior are preserved | Native and mobile builds, native navigation/source-shell guards and selected mobile geometry tests pass. The two mounted iPad navigation tests are separately tracked below, not inferred from unit-test counts. |
| Installed app and real data remain untouched | Only the exact old isolated Demo preview process was closed. The new preview runs from scratch with `--ui-testing --demo --ui-test-asic-telemetry`. The query-only saved-baseline comparison passed 13/13, including exact saved-inventory preservation. |

## Validation receipts

Owner-private operation directory:
`/Users/USER/.jcode/scratch/hashfleet-ui-update-20261026-2045/restrained-20261027/`

- Native Debug build-for-testing and test-without-building passed. `native-tests.xcresult`: **70 named tests, 118 executions including parameter cases, zero failures and zero skips**. This includes the new sparse-page tests. Existing chart-containment tests emit environment-access runtime warnings, so this is not a warning-free claim.
- Shared mobile build-for-testing passed. `mobile-tests.xcresult`: **41 named tests, 55 executions including parameter cases, zero failures and zero skips** on the iPad simulator. Suites are `FleetBalancedColumnsLayoutTests`, `FleetMinerDetailGridTests` and `FleetAdaptiveLayoutTests`.
- `rendered-final.log`: **50 actual production-view checks passed**, at 320, 480, 728, 1028 and 2056 points, both themes and enlarged-text rendering. The runner has no windows or app activation and uses an isolated network-blocking fixture. This is not physical interaction acceptance.
- A genuine signed native Release build passed. Both the built app and scratch preview pass `Scripts/validate-native-mac-app.sh`. No bundle was copied into `/Applications`.
- Mounted isolated Release checks pass in `energy-mounted.json`, `miner-workspace.json` and `mounted-layout-checks.json`. The window is a normal 2056-by-1228-point native window, not fullscreen. Targeted original captures are `energy-stacked-release.png` and `miner-fullwidth-release.png`. The root inspected both.
- `Scripts/check-native-navigation.py`, `Scripts/check-shared-page-shells.py` and whitespace checks pass. All production section-grid callers were audited for the restrained policy.
- `ipad-current-ui.xcresult`: **2 UI tests passed, zero failures and zero skips** on the current corrected source. The authoritative test tree contains `testResponsiveMinerRowsAndWholeCardNavigation()` (123 seconds) and `testLargestTextMinerCardsStackAndRemainWholeCardLinks()` (48 seconds), both Passed. These cover normal portrait/landscape card geometry and whole-card review navigation, plus mounted largest-text stacking and the Demo write lock. This run is separate from the earlier October 26 result-name postprocessor failure.

## Preserved failed attempts

The operation retains earlier failed build and renderer logs rather than treating every attempt as successful. A source race during an unsuccessful read-only review attempt left an inconsistent build input. The root restored the intended diff and the coherent rebuild and regression run passed. No successful independent reviewer signoff is credited.

The first standalone renderer link used a library-name lookup that did not resolve the debug dylib. Linking its exact existing file fixed the invocation. The next renderer run exposed an incorrect newly added light-theme pixel oracle: the actual canonical opposite-surface hero is `0x111111`, not the normal dark card surface `0x10191D`. The oracle was corrected to `FleetTheme.hashrateSurface`'s actual palette, without modifying production colors or unrelated assertions. The final renderer then passed all 50 checks.

A preceding October 26 UI command's postprocessor had required result names without XCTest's `()` suffix. Its two authoritative test results actually passed. That historical reporting failure remains distinct from this correction's current-source UI run.

## Delivery boundary

The corrected Release Demo preview is available for operator review, left on Workshop Gamma. Installation remains paused. Operator visual approval, physical native padding clicks, system status-popover acceptance, full application acceptance and resolution of the separately recorded legacy-history UUID linkage are not claimed.

No miner GET/POST/PATCH, OTA, self-test, restart, tuning, fan, pool, power-wiring, service or recovery-policy operation was performed for this UI-only correction. Demo values and dated playbook entries are not reported as current fleet telemetry. Real miner controls were not submitted.
