# HashFleet native UI implementation handoff to Cow

Date: October 8, 2026

## User request and approved direction

The user has explicitly approved the new HashFleet website and asked that Cow implement some of its UI ideas in the app. Their highest priorities are **hashrate charts** and **better organization**.

Interpretation: improve the native app using the approved web UI as the first design reference, while preserving the app's identity, real capabilities, and native interaction patterns. Keep the website and app recognizably consistent. This is not a request to replace SwiftUI with a web view, copy a landing page into the app, or present fictional browser readings as real telemetry.

This handoff authorizes native UI implementation work. It does not authorize miner operations, a domain deployment, purchases, or installation/replacement of the user's running app without a separate review of that action.

## References

Repository: `/Users/USER/dev/hashfleet`

- Interactive website reference: `http://127.0.0.1:4174/` if the existing local preview is running.
- Website source: `website/src/components/AppDemos.tsx`, `website/src/components/HashChart.tsx`, `website/src/app-demos.css`, `website/src/styles.css`.
- Desktop screenshot: `website/output/playwright/desktop-final.png`.
- iPhone screenshot: `website/output/playwright/iphone-375.png`.
- Mobile landing screenshot: `website/output/playwright/mobile-375.png`.
- Terminal screenshot: `website/output/playwright/terminal-375.png`.
- Original artwork: `App/Resources/Assets.xcassets/AppIcon.appiconset/AppIconDark.png` and `App/Resources/Assets.xcassets/HashFleetLaunch.imageset/LaunchMinerTransparentDark.png`.
- Website implementation and acceptance: commits `beda486`, `708113e`, `a30f153`, `d5bf4b0`; details in `website/ACCEPTANCE.md`.

The website's 83 unit tests, 91 browser checks, and 24 HTTP checks verify the website only. They do not validate new native changes. Public domain publication is separately blocked and is not needed for this UI work.

## Source observations to build on, not duplicate

Read-only inspection at this handoff found:

- `App/Features/Dashboard/DashboardView.swift` initializes `showingHistory` to false.
- `DashboardView+Sections.swift` puts `FleetHistoryCard` inside a `DisclosureGroup("Fleet hashrate history")` below the miner list, secondary cards, and summary metrics.
- `FleetHistoryCard.swift` already uses native Charts, history signatures, a window pager, selection, and historical-data loading.
- `FleetChartSelection.swift` currently defines daily, weekly, monthly, and yearly windows: 24h, 7d, 30d, and 365d.
- The README describes recent in-memory history limits. Inspect the current persistence/store implementation before promising retention or changing copy, because the source also has historical database-series wiring.

Verify these against the current tip before editing. Preserve useful existing long-history functionality rather than replacing it with the website's shorter illustrative ranges.

## Implementation priorities

### 1. Make hashrate charts a first-class feature

- Put a useful, visible trend near the top of the fleet overview rather than behind a default-collapsed section at the bottom.
- Use a clear chart title, legible current reading and unit, restrained grid, gold accent, and subtle area fill where appropriate. The web UI is a visual reference, not a source of chart data.
- Reuse and improve existing native chart/history logic. Support inspection of a reading and its timestamp, understandable range controls, and per-miner trends in detail screens.
- Retain supported longer windows. Add short-window controls only if they fit actual retained data and the current architecture.
- Keep SHA-256 ASIC rates and RandomX CPU rates separate. Do not sum incomparable algorithms into one misleading fleet total. Format low CPU rates in H/s or kH/s instead of rounding them to zero in GH/s.
- Real screens must use actual app observations and timestamps. Demo charts must stay explicitly labeled as simulated.
- Handle no history, one point, partial history, offline/stale readings, gaps, and a selected sample that rolls out of a bounded buffer. Do not invent points or imply uninterrupted recording across missing intervals.

### 2. Give the fleet a clear information hierarchy

Suggested reading order: fleet title/status and freshness, headline metrics, visible trend, searchable/sortable miners, then secondary insights and tools.

- Borrow the web preview's clear separation of overview, miners, and energy information, adapting it to existing native navigation rather than creating duplicate destinations.
- Group related readings together. Keep hashrate, connection state, power, and necessary attention indicators easy to scan.
- On Mac, use available width for a stable native sidebar and organized content where the current app supports it. On iPhone, use a focused vertical overview and existing native navigation.
- Preserve search, sort, compact cards, error handling, add/discovery flows, and detail navigation. Return to the previous miner/list position rather than resetting the user to the top.
- Preserve access to advanced tools and their confirmations. Move visual clutter out of the primary monitoring hierarchy without deleting capabilities or hiding important warnings.
- Keep existing app personality and identity, including Bitsy where appropriate, but do not let decorative content displace the primary monitoring information.

### 3. Carry over the visual language without copying fake device chrome

- Gold/amber highlights, graphite surfaces, clear typography, consistent card spacing, restrained borders, and compact metric groups.
- Preserve native controls, current branding, light/dark appearance, Dynamic Type, VoiceOver, keyboard/focus behavior, and Reduce Motion.
- Use the provided artwork efficiently. Do not introduce repeated high-cost image decoding, broad unnecessary layout work, or additional polling merely to animate a chart.
- Keep the web and native app's naming and hierarchy consistent with implemented capabilities. Coordinate any proposed website edits rather than independently changing the approved site.

## Non-negotiable data and operation boundaries

- Missing temperature or power is Not reported, not 0. Partial power remains a clearly labeled subtotal. Reported board power is not calibrated wall power, and constant-power cost estimates are not profit forecasts.
- No credentials, wallet addresses, private keys, or real fleet network details in public screenshots, commits, fixtures, or web output.
- Read `/Users/USER/ESP-Miner-profit-switch/docs/FLEET-OPERATIONS-PLAYBOOK.md` before any fleet operation. It is a safety reference, not live telemetry.
- This UI request gives no authorization for miner restart, self-test, OTA, voltage/frequency/fan/pool changes, recovery-policy changes, wiring changes, or service changes. Preserve all existing explicit confirmations and safety limits.
- Prefer the real native demo/test entry point for UI acceptance. It is labeled and does not contact miners. If a live-fleet status claim becomes necessary, perform the playbook's complete read-only checks first and keep evidence private.
- Respect concurrent work and the configured worker routes. Do not overwrite unrelated changes or expand this UI handoff into firmware, monitoring-service, or deployment work.

## Deliverables and acceptance

1. A brief implementation plan tied to the current native files, followed by scoped commits implementing the chart and organization priorities.
2. Native tests for algorithm/unit separation, history ranges and gaps, empty/single-point/stale states, selection rollover, and relevant existing navigation/safety regressions.
3. Exercise the actual built app's demo mode, not only an isolated chart harness: open Fleet, inspect the visible chart, change its range, inspect a timestamp, search/sort miners, open a miner, return to the preserved list position, toggle compact cards, and verify missing CPU sensors remain honest.
4. Observe the native end-user path on available iPhone simulator and Mac runtime, including narrow/wide layouts, light/dark appearance, large text, and reduced motion. Record any unavailable platform or blocked real path honestly.
5. Before/after screenshots of the same dashboard and detail workflows, showing that the chart is easier to find and the hierarchy is improved. Do not claim a measured frame-performance gain from screenshots or source inspection alone.
6. Map each changed requirement to an observed result. Run the final relevant build/test/UI checks after the last edit, preserve failures, and report commits, checks, screenshots, remaining limitations, and any untested physical-device boundary.

Please acknowledge receipt and ownership of this implementation request. Report back with the plan or completed work and evidence. Delivery of this brief is not a claim that native implementation has already happened.

## Receiver acknowledgement

Cow replied at **October 8, 17:30:40 UTC** that it received the handoff and will finish its active demo-only coverage acceptance before planning native work around the existing history components, algorithm-separated metrics, prominent charts, and calmer hierarchy. It requested that shared native production sources and app build/simulator operations remain untouched during that run. The sender acknowledged those boundaries at 17:31:20 UTC.

This is actual receiver acknowledgement and queued follow-up, not a completed native implementation or native acceptance result. No native edits, app builds, simulator jobs, hardware operations, installed-app replacement, purchases, deployment, or website changes by Cow are claimed by this handoff.
