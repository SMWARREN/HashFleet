# Requested SwiftUI expert skill analysis

Checked 2026-11-08 UTC. This is analysis, not a declaration that the remaining crashes are fixed.

## Requested method and provenance

Installed the exact `avdlee/swiftui-agent-skill` / `swiftui-expert-skill` with the skills CLI, globally for the Codex agent, then loaded it through Jcode. Installation exited 0. Skill root: `/Users/USER/.agents/skills/swiftui-expert-skill`. Installed lock entry reports folder hash `0c8daa1643f919dd603e577b773564b1be5dfe7d` and installation time `2026-11-08T03:25:58.336Z`. This is the installer folder hash, not asserted to be a Git commit. `SKILL.md` SHA-256 is `6fa1d5188176628a00e7f032298e640f5191185904e305983cc8a2fa6e2c31d5`.

Root applied Charts, chart accessibility, performance, view-structure, modifier, state-management and trace-recording references. Spider performed a source audit. Whale independently loaded the same skill and checked the cache dependency finding. No production source was modified by this analysis.

## Concrete dependency mismatch found

`FleetHistoryPageIdentity` in `App/Features/Dashboard/FleetHistoryCard+Display.swift:4-12,73-84` includes window/range/display mode/active kind/history signatures/stored revision, but omits each device name, address and kind. `MinerHistorySignature` in `FleetChartSelection.swift:303-316` includes UUID, count, first/last date and updatedAt only.

The cached computation actually consumes omitted inputs:

- `FleetHistoryCard.swift:405-425` uses device names and addresses to form series labels and duplicate-name disambiguation.
- `FleetHistoryCard.swift:72-77` and `FleetHistoryPresentation.swift:21-27` filter chart membership by each device kind. A device kind change need not change the active kind.
- `FleetHistoryCard+Display.swift:87-100` forms fleet alignment and the single-device fleet label from those devices.

Consequently, with the same installed card/cache and unchanged history signatures, metadata-only changes can hit the old cache key and return stale labels or membership. Whale independently verified this static dataflow. It justifies a targeted regression, but no specific app session has yet been shown to retain the card across that change. It is not evidence for the original HashableText trap.

Minimal regression coverage: metadata-only rename, duplicate-name introduction/resolution plus address change, and kind change in a mixed-kind device set while the active kind is unchanged. Preserve the same cache, UUIDs and telemetry signatures. Reorder coverage should retain array ordering. A small ordered presentation identity of UUID/name/address/kind would cover these dependencies without comparing whole telemetry payloads. Do not call this repaired before the failing-before/passing-after checks run.

## Performance investigation, not a measured diagnosis

`DashboardView+Sections.swift:40-113` reads whole-fleet snapshots for aggregate totals, the hero and the history card inside helper methods. The skill distinguishes helper methods from real View invalidation boundaries. These aggregate reads are functionally expected, so they are not themselves a defect. Their measured update cost and propagation into the navigation chain remain unprofiled. Existing per-miner snapshot cells already address a different observation boundary. Do not remove necessary aggregate dependencies or blanket-refactor the dashboard without a profile.

For a separate, explicitly labeled simulator profile, the skill recommends app-scoped Time Profiler rather than expecting the SwiftUI instrument lane to populate on the simulator. Do not attach a profiler mid-way through an already preregistered control run. Physical-device scene-create performance remains a separate acceptance gap.

## False positives rejected during this audit

- Conditional chart content is supported. Apple ChartContentBuilder explicitly supports buildIf/buildEither, and the installed skill Charts reference demonstrates combined LineMark and PointMark. SwiftUI list child-count advice is not a blanket prohibition on conditional ChartContent.
- A one-point line plus a point mark is not, by itself, evidence of invalid Charts construction.
- Date IDs across different miners are not duplicates within the same nested ForEach. The current merge path collapses per-second readings, and fleet aggregation replaces repeated aligned timestamps within a segment. An actual duplicate in the plotted scope must be demonstrated before changing identity semantics.
- The page/range caches are nonobservable reference memoization objects retained by State. Their internal mutation does not publish observation changes. That alone is not proof of a state-update/layout loop. Cache dependency correctness is a distinct issue, described above.
- The iOS page-height preference observer already rounds and checks a one-point deadband. That is not proof that arbitrary layout feedback cannot oscillate, but no runaway cycle was measured here.
- Plottable labels differ between Area/Point marks (`Hashrate`) and Line/selection marks (`Hashrate in <unit>`). This is an observable source difference, not proof of an internal HashableText dictionary collision. The original crash has not been causally linked to it.
- Integer segment IDs can be reassigned when gaps split/merge. That is a possible transition-identity discriminator, not demonstrated duplicate IDs or a proven crash cause.

## Installed Charts API check, November 8 at 06:28 UTC

Tiger and root independently read lines 2672–2683 of the installed iPhoneSimulator SDK `Charts.framework/Modules/Charts.swiftmodule/arm64-apple-ios-simulator.swiftinterface`. The single-value `PlottableValue.value` overloads accept `LocalizedStringKey`, `LocalizedStringResource`, generic `StringProtocol`, and `Text`. The resource and generic string overloads carry `@_disfavoredOverload`. These declarations do not establish which overload the compiler selects at the four app call sites and do not disclose private `HashableText` dictionary behavior. No compiler experiment or label change was performed.

The four y-label sites are AreaMark at line 109 and single-point PointMark at line 130 with `Hashrate`, plus LineMark at line 120 and selection PointMark at line 152 with interpolated `Hashrate in <unit>`. Any uniform-label discriminator must account for all four sites. A surviving run alone would not prove a fix. Temporal unit changes also change numeric coordinates and the y-domain, and the failed AX discovery probe is not a validated equivalence oracle.

## Follow-up chronology

Earlier pending statements in this initial analysis are historical, not the latest outcome. Subsequent native red/green metadata-cache checks and the real Dashboard negative control are recorded in the rendering/stability validation records. The ordinary CPU profiles, encoding-cache correctness tests and independently audited, exposure-unmatched comparison are recorded in `DASHBOARD-CPU-PROFILE-2026-11-08.md`. Candidate18 also reproduced the observed Charts trap signature before one unchanged repeat survived. None of those outcomes clears the remaining integrated or physical acceptance requirements.

## Remaining acceptance preserved

The bounded 12-step image/OCR observation passed independently: six GH/s and six TH/s states, all 11 plot-mask transitions, 6.938 seconds. The older 80/1600 digest thresholds and the 90-second aggressive budget remain failed. The original Charts SIGTRAP is not fixed or reproduced by that pass.

The 10/600/10-second diagnostic session A/B/A result concerns a harness-induced socket condition, not the shipped shared-session configuration. The separate instrumented lifecycle run has stopped. Root and Whale verified 40 complete receiver/store pairs with consumer progress and 92.451224–94.498574 seconds from receiver exit to consumer-loop completion. Other sequences are censored, so full lifecycle acceptance remains inconclusive. These observations do not isolate processing cost or prove a Charts cause.

The existing AnyView startup candidate has measured structural type-name effects, not physical background scene-create acceptance. The isolated real-Dashboard negative-control preparation remains pending execution.
