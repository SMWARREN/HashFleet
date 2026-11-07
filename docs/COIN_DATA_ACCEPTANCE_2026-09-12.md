# Coin data reliability acceptance, 2026-09-12

## Request and interpretation
Fix the recurring DGB “Needs fresh readings” output and obtain useful coin/network information from pools. This is read-only public data work, not a change to miners, wallets, pool schedules, artwork, splash screen, or app name. Full-time comparison scenarios are not schedule-adjusted mining odds.

## Cause and source contract
- Retired `https://api.blockchair.com/digibyte/stats` returned HTTP 404 on September 12. A generic freshness label hid that source failure.
- Replacement `https://dgb-sha.solopool.org/api/stats` returned HTTP 200. Its SHA-256-specific dashboard consumes `node.difficulty`, `node.height`, and `node.lastUpdate`. The parser uses these fields, not pool share difficulty or another DigiByte algorithm. Neither instantaneous hashrate is relabeled as a 24-hour average.
- SoloFury fixed public `/api[-coin]/pool` summaries provide same-coin network difficulty, block height, pool one-hour hashrate, and miners/workers for BTC, BCH, XEC, BC2, BCH2. DGB is never sent through another coin's fallback.
- Primary healthy explorer data wins. A usable same-coin pool source can replace an unavailable explorer. BC2/BCH2 use pool-reported network data explicitly attributed to SoloFury.
- Pool snapshot timestamps are not supplied. UI explicitly labels retrieval age, not independently verified upstream age. Explicit `sources` health is validated: stale, failed, empty, or malformed source arrays fail closed. Last-found-block timestamps are not snapshot timestamps.

## Requirement-to-check mapping
| Requirement/output | Concrete check and evidence |
|---|---|
| DGB SHA-256 network reading | New DigiByte parser tests verify nested fields, timestamps, positive/bounded values and retired-URL rejection. Production native UI checks require DGB probability and SoloPool.org attribution. |
| All six supported coin rows | Opt-in `LivePublicDataUITests.testProductionPublicDataRendersAutomaticallyOnNativeHome` connects two loopback miners through real Add Miner UI, then reads actual production public services for BTC/BCH/XEC/DGB/BC2/BCH2. No public API fixtures in this path. All six row assertions passed in runs at 16:51 and 16:59 UTC, though subsequent acceptance assertions failed as described below. |
| Useful pool fields | Native test opens Pool-reported network data and checks all five coin cards for reported network difficulty and height, without “Not reported”. Final result recorded below. |
| Honest source failures | `distinguishesSourceOutageStalenessAndMissingDifficulty` covers loading, HTTP 404, missing/invalid difficulty, stale source time and success. UI reports source failure separately from unavailable miner hashrate. |
| Do not freshen upstream caches | `providerCacheAgeCannotBeRefreshedByNewFetch` and `upstreamSourceHealthCannotBeRefreshedBySuccessfulHTTP` cover aged timestamps and stale/failed/malformed upstream source metadata. |
| Miner-rate integrity | `staleOfflineUnknownAndMerelyConfiguredCoinsAreExcluded` now also excludes cached snapshots. Existing incomplete-group tests preserve unknown rather than substituting a partial rate. Full-fleet comparison requires every current device to have a fresh non-cached valid rate, otherwise unavailable. |
| Rotation honesty | Visible assumptions state continuous full-time scenarios with unchanged difficulty. Inactive-coin rows say “If full fleet”. Accessibility also says rotation is not applied. No claim that a miner works every coin simultaneously. Actual schedule-adjusted odds remain outside this change. |
| External-data opt-out | `externalOptOutClearsEveryCoinIncludingDGBAndXEC` verifies DGB/XEC and pool summaries are removed along with existing public data. Existing generation/cancellation tests guard late responses and demo transitions. |
| No miner writes | Native live test checks both loopback journals against GET info, ASIC and live-WebSocket upgrade paths, and asserts neither server received writes. No physical miner is contacted by this acceptance test. Public aggregate endpoints receive no wallets. |
| Packaging | Signed device build, signature verification and installation result recorded below. |

## Regression evidence and iteration
- Full core run after serializing the shared URLProtocol fixture suite: 188 tests / 21 suites passed. The DGB tests extend the existing serialized suite instead of racing its global handler from a separate suite.
- After upstream source-health regression: 189 core tests / 21 suites passed at 16:58 UTC.
- Full native unit run at 16:59 UTC passed 572 test functions (771 expanded executions). Result bundle: `Test-HashFleet-2026.09.12_12-59-16--0400.xcresult`.
- First extended live UI run passed all six coin rows and existing Network page, then failed its old two-path allowlist. Monitoring legitimately performs a read-only `/api/ws/live` GET upgrade. The allowlist now covers that audited path and verifies both miners' journals, with unexpected requests included in failures.
- The next run again passed six real coin rows, but could not address the new pool card container. Adding nested accessibility containers exposed a reproducible SwiftUI `AccessibilityAttachmentModifier.willCreateNode` crash. Those containers were removed. Pool readings now have individual accessible identifiers, and the expandable group was replaced by a dedicated native navigation page. All network-value and no-write assertions are retained. These attempts were not installed on the phone.
- Final live acceptance PASSED at 17:12 UTC in 42.862 seconds, zero skips/failures. Result: `Test-HashFleet-2026.09.12_13-10-54--0400.xcresult`. All six live probabilities, DGB/SoloFury attribution, ten pool difficulty/height fields, navigation back to real fees/backlog, and both GET-only miner journals passed. Dedicated pool-page navigation eliminated the reproduced accessibility crash. Device packaging follows this verified source.

## Limits
External API availability is not guaranteed forever. Fetch and upstream health failures stay explicit, never replaced by fabricated fresh data. Public pool summaries are not private account earnings or miner hashrate. The acceptance miners are controlled loopback fixtures, while public data uses real production clients/endpoints. Physical iPhone launch may be blocked by its lock state and must not be claimed without a successful launch result. No physical background notification delivery is part of this coin-data change.

## Device delivery
Executable source commit `fd8d12b` built successfully for iOS at 17:13 UTC. `codesign --verify --deep --strict` passed, including the embedded widget. CoreDevice confirmed `app.hashfleet` installed on the paired iPhone at 17:14 UTC (database sequence 2120). Subsequent launch was denied explicitly because the phone was locked. The combined command's exit 1 is a launch failure, not an installation failure. No physical-device UI acceptance is claimed for this revision. No miner settings or protected artwork/splash files changed.

## Complete output-to-check follow-up (17:21 UTC)
The earlier partial-coverage assessment is superseded by this bounded follow-up. Existing business logic was not changed: the fresh-fleet helper moved into `ChainObservation` for direct testing, and stable identifiers were added to existing reading elements. No nested accessibility groups were reintroduced.

Result bundle `Test-HashFleet-2026.09.12_13-19-24--0400.xcresult`: **573 native unit functions plus one live UI test passed**, 773 expanded executions total, zero failures/skips. The live UI path ran for 53.928 seconds against production public data, with only miner telemetry provided by loopback servers.

| Explicit requirement or changed public output | Concrete check | Observed result |
|---|---|---|
| DGB no longer blocked by retired endpoint | DigiByte parser/URL allowlist tests; live DGB home row | Retired endpoint rejected by allowlist; new source produced probability with SoloPool.org attribution. |
| All supported coin rows work | Live UI iterates BTC/BCH/XEC/DGB/BC2/BCH2 | Each displayed a probability. No generic “Needs fresh” output. BC2/BCH2 explicitly attributed to SoloFury. |
| Pool network difficulty | Live `insights.poolNetwork.<coin>.difficulty`, five coins | All five labels contained the expected title and a numeric reading, with no missing placeholder. |
| Pool block height | Live `.height`, five coins | All five numeric block-height readings present. |
| Pool one-hour hashrate | Live `.hashrate`, five coins | All five numeric readings present with H/s units; no “Not reported”. |
| Pool miners/workers | Live `.counts`, five coins | All five count pairs present; no unknown `?` placeholders. Parser tests separately distinguish valid zero from absent/invalid fields. |
| XEC and DGB network detail rows | Live `insights.coinNetwork.<coin>.difficulty` and `.height` | All four numeric readings present. DGB difficulty explicitly labeled SHA-256d network difficulty. |
| Pool-page navigation and existing network figures | Live open pool page, inspect 20 readings, return, inspect fees/backlog and coin detail rows | Navigation completed without crash. Existing fee and backlog content remained accessible. |
| Loading, HTTP outage, malformed difficulty and stale-source labels | `distinguishesSourceOutageStalenessAndMissingDifficulty` | All branches passed with distinct loading, HTTP404, missing difficulty, stale data and success outputs. |
| Cached source age not made fresh by another response | `providerCacheAgeCannotBeRefreshedByNewFetch`; core `upstreamSourceHealthCannotBeRefreshedBySuccessfulHTTP` | Aged timestamps rejected. Failed/stale/malformed upstream source arrays rejected, healthy arrays accepted without inventing a timestamp. |
| Source-specific price freshness and failure timestamp wording | `ChainObservation.isFresh` boundary regression plus explicit source review of `primaryNetworkData(.dgb)` and `InsightsSourceCard` | DGB own-price branch uses DGB freshness; fallback price uses market freshness. Failed requests show “Failed attempt”, not successful stale-cache wording. Optional market-price availability is not guaranteed or asserted as a required live value. |
| No substitution of full-fleet rate for incomplete active group | `incompleteGroupNeverSilentlyUsesPartialHashrate`; source review of `group.map { $0.rateHPS }` selection | Missing group rate remains unknown. No partial numeric rate manufactured. |
| Fresh whole-fleet comparison fallback | `freshFleetFallbackRequiresCompleteCurrentReadingsAndFiniteSum` | Empty/missing device, missing info/date/rate, cached/offline, stale/future, negative/nonfinite and overflowing readings all returned nil. Complete readings summed, zero remained zero, exact time boundaries passed, demo bypassed age only. |
| Rotation/full-fleet comparison honesty | Source review of visible assumptions and live home accessibility labels | Comparison is explicitly full-time with rotation not applied; inactive-coin caption says “If full fleet”. No schedule-adjusted odds claim is made. This check is wording/attribution, not validation of a physical mining schedule. |
| External data opt-out and late response rejection | `externalOptOutClearsEveryCoinIncludingDGBAndXEC`; `cancellationAndDemoTransitionRejectLatePublicResults` | All coin/pool data cleared, late/cancelled responses rejected. |
| Cooldown, forced refresh and per-source failures | `refreshCooldownPreventsHammeringPublicServices`; `forcedRefreshPreservesPartialFailuresAndAccurateTimestamps`; source review of 60-second scene-active loops | Cooldown and forced-refresh state checks passed, failures/timestamps remained source-specific. Foreground loops are configured at 60 seconds; extended background scheduling is not promised or part of this change. |
| Public pool queries disclose no miner identity | `explicitPublicRefreshPreservesPartialFailuresAndSendsNoIdentity` | Fixed public request paths/hosts and no identity payload passed, including the new pool summaries and DGB source. |
| No physical miner writes | Live UI checks both loopback request journals and write lists | Only audited GET info, ASIC and telemetry upgrade requests, zero writes. No physical miner was contacted by the test. |
| Preserve other agent work | Scoped git diff review | No splash, single-miner artwork, app naming, hardware configuration or pool schedule edits. |
| Device packaging/delivery | Signed build, strict signature verification, CoreDevice installation | Original repair installed at17:14 UTC. Follow-up verification build delivery recorded below. Physical-device UI acceptance remains explicitly unverified. |

“Complete” here describes mapping every changed public output to an identified check with its actual observation. It does not mean exhaustive device/OS/provider coverage, perpetual API availability, or physical mining-schedule validation. Code-review checks are distinguished from executed native assertions above.

Follow-up executable `e750fc2` built and passed strict deep signature verification. CoreDevice confirmed installation at17:24 UTC, sequence2128. Remote launch was not retried after the earlier explicit lock denial. No physical foreground observation is claimed.


## Whole-result rerun after mapping (17:31 UTC)
Repeated the entire core suite and native suite together with all seven current app acceptance workflows, without any executable change after the mapped17:21 run. Core189/21suites passed. Native573 unit functions plus7 UI workflows passed,779 expanded executions, zero failures/skips. Result: `Test-HashFleet-2026.09.12_13-27-03--0400.xcresult`. The production public-data UI rerun passed in51.176s, again verifying all six probability/source rows, all20 pool fields, four XEC/DGB detail fields, navigation and GET-only journals. The named source-error, freshness/overflow, opt-out, privacy, cancellation and cooldown tests were rerun as part of the full suites.

The separately identified code-review checks were repeated on this same source: DGB price freshness follows the selected price source; failed fetches use “Failed attempt”; assumptions label full-time scenarios with rotation not applied; refresh loops gate external opt-in/active scene and sleep60seconds. These observations do not assert a background timer or guarantee market feed availability. HashWatcher real UI workflow outcomes are recorded in `HASHWATCHER_ACCEPTANCE_2026-09-12.md` from this same result bundle. No synthetic-only harness was substituted for the live UI paths. No new hardware writes, phone unlock attempts, real-fleet restores, or external report sends occurred.
