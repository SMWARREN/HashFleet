# Single-miner logo palette · 2026-09-09

> Historical cream/bronze proposal and acceptance. The user subsequently preferred white-based light mode and black/graphite dark mode. See [the current neutral appearance](../neutral-palette-2026/README.md). Original logo extraction remains valid.

This implementation supersedes the earlier white/black marquee and white/charcoal light-mode palette. It follows the user's complete color revamp request and correction to use **the single miner**, not the three-miner concept.

## Sources and extraction

The exact existing dark master and user-supplied light master are preserved byte-for-byte in `App/Resources/Assets.xcassets/HashFleetHeader.imageset/`. The default header image is the ivory version. The asset catalog's dark-luminosity variant is the dark version. SwiftUI resolves the correct original-color image at the dashboard's top-left, inside a 44-point frame.

- Source filenames, SHA-256 hashes, dimensions, top-left sample rectangles, regional means, medians and nearest actual pixels: `extracted.json`.
- Extraction: `ExtractLogo.swift` decodes into **sRGB** before computing values. This deliberately corrects the earlier DeviceRGB-based rounding. For example, the same dark casing now resolves to `#E9931E`, rather than the earlier `#E9921D`.
- Regional means represent selected textured material, not a claim about globally dominant colors.
- `build_roles.py` documents and reproduces the blends. Blending occurs in encoded sRGB, with 8-bit rounding. Contrast uses linearized sRGB relative luminance.
- Sage is an explicitly separate functional success/online color. It is not falsely attributed to a gold/gray logo.

Reproduce extraction directly from checked-in header masters:

```sh
swift docs/research/logo-palette-2026/ExtractLogo.swift \
  App/Resources/Assets.xcassets/HashFleetHeader.imageset/HeaderDark.png \
  App/Resources/Assets.xcassets/HashFleetHeader.imageset/HeaderLight.png
python3 docs/research/logo-palette-2026/build_roles.py
python3 docs/research/logo-palette-2026/build_preview.py
```

When using the catalog filenames, only `sourceFile` labels differ from the extraction recorded under the original master filenames. Image hashes and sample values remain identical.

## Main roles

| Role | Light | Dark |
| --- | --- | --- |
| Canvas | `#EBE3DA` | `#21201E` |
| Cards | `#FDF7EE` | `#373737` |
| Raised surfaces | `#FEFDF8` | `#484747` |
| Main text | `#21201E` | `#FDF7EE` |
| Secondary text | `#5C5854` | `#D8CFC6` |
| Action text | `#743A03` | `#F1A922` |
| Hashrate surface | `#F19411` | `#E9931E` |
| Ticker surface | `#FADFB9` | `#473829` |

All 23 exact role pairs and derivations are in `roles.json` and the comparison page. No custom canvas, card, ticker or main-text token is pure white or pure black. The unchanged artwork, native iOS chrome and decorative shadows may still contain white/black. The two semantic roles `raised` and `controlBorder` also define safe values for future elevated surfaces and interactive boundaries. Decorative low-opacity card outlines do not claim 3:1 control contrast.

## Integration boundary

Theme roles apply to dashboard and detail cards, the moving/static ticker, onboarding insets, live logs, settings/preferences, About, endpoint/compatibility forms, chart series, standard widgets and Live Activity panels. Existing coin artwork remains unchanged and retains recognizable coin colors. Standard widgets follow the system's widget appearance, independently of the app's manual light/dark preference. Dynamic Island rendering and accented/tinted widgets remain subject to iOS styling.

No miner/networking behavior, credentials, hardware commands, permission decisions or persisted user data were changed. No uninstall or physical-device install is part of this pass. Pre-existing home-screen AppIcon, HashFleetBrand and Xcode project edits are not claimed as this task's changes.

## Validation

- Exact source extraction rerun successfully with identical output.
- 62 specified contrast checks pass. Normal text is at least 4.5:1, with a lowest tested ratio of 4.60:1. Control-boundary and fourth-chart-series roles are at least 3:1 on the three base surfaces.
- Final simulator app and widget extension build passed.
- Final serialized native run completed at 02:20 UTC on the iPhone 17 Pro simulator (iOS 26.5): **12 FleetPreferencesTests and 3 UI tests passed, zero failures**.
- Result bundle: `/Users/USER/.jcode/scratch/HashFleetLogoPaletteFinal.xcresult`.
- Unit coverage: all 23 light/dark role values, all 62 contrast pairs, no pure-white/black base surfaces or main text, distinct light/dark resolved header assets, preference persistence and invalid-value recovery.
- UI coverage: dark → light → dark, real canvas/ticker/card screenshot color differences, Add Miner sheet, miner details, Preferences, About in both modes, Best Shares, actual moving/paused/resumed ticker pixels, and static untruncated accessibility summaries.
- The first run passed all 12 unit tests and both ticker UI tests, but the new card-color assertion failed because its crop overlapped the miner title. The final test samples the card's actual 14pt padding, retains the original thresholds, recomputes geometry after scrolling, and throws rather than silently ignoring missing image data. The first failed run is not counted as successful acceptance.
- Eight unaltered native screenshots from the passing run are in `screenshots/`. `screenshots/manifest.json` maps them to test identifiers, exported attachment IDs and SHA-256 hashes. Both dashboard modes and the ivory About form were visually inspected. The side panel shows the actual light and dark examples.
- This is targeted native acceptance, not a full regression rerun or a whole-app accessibility certification. Widgets and Live Activities compiled successfully but their home-screen, tinted, lock-screen and Dynamic Island appearances were not visually revalidated in this pass. No physical-device installation or phone-screen observation was performed.
