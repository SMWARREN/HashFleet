# Coin visibility acceptance, 2026-09-12

## Request interpretation
Default to actively mined coins, one combined row per coin, without overlaps, and allow users to choose visible coins. The ambiguous fallback phrase was interpreted explicitly as: when no fresh active coin can be identified, show recognized configured coins rather than all six. This is display selection only, not pool switching or schedule changes.

## Implementation and mapped checks
| Requirement | Check and observed result |
|---|---|
| Only actively mined coins by default | `coinVisibilityIsUniqueActiveFirstAndExplicitlyOverridable` passed. Native UI added two BTC loopback miners and one BCH miner and observed only BTC/BCH rows; XEC/DGB/BC2/BCH2 absent. |
| At most one row per coin | Pure selection normalizes through a Set and fixed display order. Native queries found exactly one BTC and one BCH row, and BTC accessibility label reported two active miners. |
| No overlap | Native test checked BTC/BCH row rectangles do not intersect. Picker control uses a separate full-width row instead of crowding the existing Network header. |
| Fallback when activity is unavailable | `configuredFallbackUsesOnlyCurrentDevicesAndRecognizedCoins` passed: cached configured DGB via documented SoloPool host/port retained, removed-device and unknown-host coins excluded. Empty active/configured input stays empty, not all six. Fallback copy explicitly says activity is unavailable. |
| User-chosen visible coins | Native Coins to show form switched from Automatic to Custom, cleared selection, chose DGB and observed DGB alone. Select all then restored exactly one row for each of six coins. |
| Saved choice | Native app terminated and relaunched with the same isolated app storage; DGB-only selection and Custom mode persisted. `dashboardCoinSelectionPersistsAndEmptyIsNotAutomatic` also passed recreation, empty selection, reset to automatic, duplicate/unknown raw values and malformed storage. |
| Deliberately empty selection | Unit checks confirm explicit empty Set is not automatic fallback. UI offers explanatory empty-state text and keeps the picker reachable. |
| Rotation/default updates | Pure selector switches output when active input changes. Existing active-group tests still cover rotation and same-coin grouping. No schedule writes or schedule-adjusted-odds claim. |
| Existing real sources still work | After explicit Select all, the unchanged live public API assertions passed all six coin probabilities, all20 pool fields, XEC/DGB detail fields and native navigation. |
| No hardware/settings writes | Native acceptance used three loopback miners, checked all three write lists empty and all three journals GET-only. Preference test confirms notification/monitoring settings unchanged. No physical miner contacted by tests. |

## Results
`Test-HashFleet-2026.09.12_14-20-54--0400.xcresult`: **576 native unit functions in58 suites passed**, plus the extended live UI test passed in78.274seconds. The public-data clients were real production clients; only miner telemetry was a controlled loopback fixture.

The first run exposed two test issues: the DGB fallback fixture incorrectly used the public API host instead of the documented mining host/port, and tapping the outer accessibility switch row did not actuate its nested UISwitch. Corrected the fixture to `us1.solopool.org:8004` and targeted the actual switch control, adding post-tap state assertions. No product behavior or data-source safety gate was weakened.

Protected splash/artwork, app name, miner configuration and network source logic were unchanged. Physical-device foreground acceptance remains separate from simulator workflows. Device delivery follows this verified source.

## Device delivery
Executable `24945ca` passed signed iOS build and strict deep signature verification. CoreDevice confirmed installation at18:25 UTC (sequence2136) and successfully launched `app.hashfleet` on the paired iPhone. Launch success is confirmed, but automated interaction/visual acceptance was on the simulator as described above.
