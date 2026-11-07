# Appearance acceptance · 2026-09-09

> **Latest revision:** [White light mode, black/graphite dark mode and rim-free logo](research/neutral-palette-2026/README.md). This replaces the later cream/bronze proposal as well. All installation records below concern historical revisions only.

> Historical acceptance below. The subsequent user-requested complete logo-color revamp supersedes the white/black ticker and earlier palette restrictions. Current colors, single-miner header variants and validation are documented in [Single-miner logo palette](research/logo-palette-2026/README.md), with [light/dark native examples](research/logo-palette-2026/index.html). Earlier device installation evidence below does not imply installation of this newer revision.

## Delivered scope

- Persistent Light/Dark preference, default Dark. Sun/moon control at the dashboard's right edge, plus Settings → Preferences → Color mode. The appearance control yields space to inline miner search.
- Approved icon-derived orange-gold and neutral graphite. Main fleet total and individual miner hashrate are gold in dark mode, charcoal in light mode, without decorative borders.
- Solo · 30-day comparison and both dashboard/detail Best Shares cards receive the requested outline: white in dark mode, gold in light mode, 0.5 pt at 25% opacity.
- Marquee uses a full-width pure-black strip in dark mode and pure-white strip in light mode. Existing moving/static, pause/resume and accessibility behavior is preserved.
- Native sheets, form backgrounds and prominent button text adapt to appearance. No new artwork, onboarding artwork, miner commands or networking behavior.

## Palette provenance

Read the existing `selected-logo-master.png` directly using Core Graphics in sRGB. Rectangular sample averages from its 1254 × 1254 pixels:

| Region (x, y, width, height) | Color | Use |
| --- | --- | --- |
| Right casing (895, 258, 45, 60) | `#E9921D` | Gold accents and dark-mode hashrate surfaces |
| Hub (600, 620, 80, 80) | `#363636` | Graphite cards |
| Dark blade (785, 693, 10, 20) | `#201F1E` | Canvas / dark ink |
| Fan highlight (590, 385, 45, 30) | `#484646` | Secondary dark surfaces |

Light-mode gold text is shaded to `#8A5000` for readable contrast on white. Brand imagery and coin icons remain unchanged. Semantic online/warning colors remain distinct.

Approved image SHA-256 values stayed unchanged during this work:
- AppIcon: `6f693a92e6ce491f9bbd83441bbe860002a7b889a42d2a3008da5de97ec8a119`
- HashFleetBrand: `411b8ba0b82ab040e75f30fad8cc250953b1b6a150552543ed49613c0e34527c`

## Real native acceptance

Final `xcodebuild test`, iPhone 17 Pro simulator, serialized, passed 11 native preference/palette tests and these 3 UI tests with zero failures:
- `HashFleetUITests.testAppearanceSwitchUpdatesDashboardDetailsAndSettings`
- `CompactDashboardUITests.testStatusTickerCyclesAndPauseReallyStopsSelection`
- `CompactDashboardUITests.testAccessibilityTickerExposesStaticUntruncatedMinerSummaries`

Result bundle: `/Users/USER/.jcode/scratch/HashFleetDarkPass/Logs/Test/Test-HashFleet-2026.09.08_21-04-03--0400.xcresult`.

The actual app was launched in its built-in, explicitly labeled read-only demo. UI actions switched dark → light → dark, opened/dismissed Add Miner, navigated to a miner and Preferences, and checked the preference remained selected across navigation. Pause froze the real ticker, resume restored it, and accessibility sizes exposed complete static miner summaries. Unit tests separately verified persistence across preference instances, invalid-value recovery, exact gold/outline/marquee colors and at least 4.5:1 for the tested text/background pairs.

Earlier in this same pass, search/local preferences, nested read-only miner tools and largest Dynamic Type navigation also passed. The first dark-only nested navigation run had an intermittent failure, which did not recur in subsequent focused and combined runs. This is targeted acceptance, not a claim that the entire app regression suite was rerun.

## Observed visual result

Final real screenshot exports are in `/Users/USER/.jcode/scratch/HashFleetAppearanceFinalScreens/` with `manifest.json` mapping each image to its test.

Visually inspected:
- `1F2D6EBB-2755-41AD-9A7F-7F74CC0D96EC.png`: dark dashboard. Black marquee reaches both screen edges, gold total is distinct from graphite cards, Solo has a faint outline, titles and coin icons stay aligned.
- `694C0B2C-F10E-462B-9856-20D1A5892B7F.png`: light dashboard. Full-width white marquee, charcoal total, white cards and subtle gold Solo outline. The toolbar changed to the moon icon.
- `772587E3-14C2-4FDA-90C9-C3FF85327C83.png`: dark miner detail. Matching gold hashrate card without a white border, readable pool/coin, uptime, accepted/rejected and freshness labels.

Earlier light sheet/detail screenshots were also inspected. Card and sheet corners blend with their surrounding surfaces rather than showing pale rectangular backgrounds.

## iPhone delivery and limits

The final revision was built for generic iOS, signed and passed `codesign --verify --deep --strict`. `devicectl` confirmed installation of `app.hashfleet` on the paired iPhone 14 Pro Max at approximately 01:04 UTC. Existing app data was retained; no uninstall was performed.

Automatic launch was denied by iOS because the phone was locked. Installation succeeded, but phone-screen visual acceptance could not be observed. Unlock and open Hash Fleet to view it. No hardware writes were performed. The approved app-icon/logo assets and unrelated Xcode project changes were preserved and excluded from this appearance commit.

## Follow-up restoration and palette review · 01:31 UTC

The user briefly requested inverse marquee colors, then explicitly requested the normal colors back. Final source therefore retains the original black-in-dark and white-in-light strip. Graphite canvas/cards remain layered rather than all-black. Removed the extra HStack spacing and redundant Spacer before Pause, while preserving the 44 pt button target. Added the Solo-style outline to dashboard and detail Best Shares cards.

The first inverse-color run failed a native pixel assertion. It is not counted as passing evidence. The final normal-color run passed all 11 FleetPreferencesTests and the same 3 native UI acceptance tests listed above, with zero failures. This run additionally validates marquee text contrast in both appearances, verifies scrolling glyphs enter the last 8 pt before the Pause hit area, and captures the dashboard Best Shares outline after navigation. The screenshot crop excludes Pause by its actual frame, avoiding the combined SwiftUI accessibility row bounds. Existing moving, five-second-paused, resumed and static accessibility checks remain intact.

- Result: `/Users/USER/.jcode/scratch/HashFleetDarkPass/Logs/Test/Test-HashFleet-2026.09.08_21-29-32--0400.xcresult`.
- Screenshot exports: `/Users/USER/.jcode/scratch/HashFleetRestoredScreens/manifest.json`.
- Signed generic-iOS build and strict signature verification succeeded. `devicectl` confirmed the restored build installed at 01:31:29 UTC on the paired iPhone 14 Pro Max. No uninstall, miner write or app-data reset. Phone-screen appearance remains unobserved.
- New light-mode palette proposals are research artifacts only at `docs/research/light-mode-2026/index.html`. None has been applied to app or widget source. They include dated 2026 mobile references, exact existing role values, explicit extra RGB declarations, source call sites, and calculated contrast checks.
