# Miner fan artwork

The onboarding fan graphic is `MinerFans`, a single image set in the app's existing catalog:

`App/Resources/Assets.xcassets/MinerFans.imageset/`

## Artwork

- Two overlapping ASIC axial cooling modules, with sculpted graphite blades, amber-gold enclosures, brushed hubs and inset silver screws.
- True transparent background. There is no baked-in white, beige, black or checkerboard tile.
- Matches the graphite and gold in `FleetTheme` and the existing single-miner brand artwork.

## Why there is no light/dark pair

**This artwork is deliberately appearance-independent.** The onboarding card it sits on is
`FleetTheme.charcoal`, which is `0x111111` in *both* light and dark mode. A light-appearance
variant is therefore unreachable: it can never be composited onto a light surface.

An earlier revision shipped `miner-fans-light@Nx.png` and `miner-fans-dark@Nx.png`. Measured on
decoded pixels, those two files differed by an average of only **14.6/255** per channel over
opaque pixels. For comparison, `HashFleetBrand`, which is a genuinely inverted pair, differs by
**166/255**. The "light" variant was effectively the same image at slightly lower luminance, so
it was removed in favour of one master.

`LaunchBrandTests.onboardingFanSurfaceIsIdenticalInBothAppearances` pins the invariant that
justifies this. If `FleetTheme.charcoal` ever becomes appearance-dependent, that test fails and
a real light variant is needed again.

Note that the **single-miner** marks (`HashFleetBrand`, `HashFleetHeader`, `HashFleetLaunch`) *are*
intentionally inverted by appearance, per commit `da8ecef`. Do not "unify" those to match this one.

## iOS integration

| Scale | PNG dimensions | Logical size |
| --- | --- | --- |
| @1x | 96 × 96 | 96 × 96 pt |
| @2x | 192 × 192 | 96 × 96 pt |
| @3x | 288 × 288 | 96 × 96 pt |

Three universal renditions, no appearance slots. The catalog and SwiftUI view both use original
rendering, so surrounding tint cannot recolor the artwork. `FleetMinerFansImage` keeps its `size`
API, aspect fit and decorative accessibility behavior. No onboarding layout change or project
regeneration is needed because this catalog was already in the resources build phase.

## Source and reproduction

The transparent sRGB 1254 × 1254 master is in [`docs/design/miner-fans`](docs/design/miner-fans/).
To regenerate every PNG and `Contents.json`, run from the repository root:

```sh
xcrun swift Tools/export-miner-fans.swift
```

This uses only Apple's CoreGraphics and ImageIO. Exports are sRGB RGBA PNGs, resized from the
master with premultiplied-alpha drawing and high-quality interpolation. The exporter emits a
single appearance-independent set by construction, so the redundant pair cannot be reintroduced
by re-running it.

## Validation

- `LaunchBrandTests.minerFansResolveBothAppearancesForEveryRequestedScale` checks both trait
  appearances at 1x/2x/3x, logical and pixel dimensions (including device-thinned fallbacks),
  transparent edges, meaningful opaque coverage, and that both appearances resolve the same master.
- `LaunchBrandTests.minerFansRenderInSwiftUIWithoutPlaceholderOrTint` checks real SwiftUI
  rendering at 96 and 200 points, meaningful gold hardware pixels, and original rendering despite
  a pink foreground style.
- `LaunchBrandTests.onboardingFanSurfaceIsIdenticalInBothAppearances` pins the charcoal invariant.
- The existing compiled launch-brand regression remains in the same suite.

Real app screenshots: [dark onboarding](docs/design/miner-fans/onboarding-dark.png) and
[light onboarding](docs/design/miner-fans/onboarding-light.png).
Captured from the running app on the iPhone 17 Pro simulator after this change. Note that in
light mode the page canvas is white while the onboarding card stays black, which is exactly why
the artwork needs no light variant. Cropping the fan region from both screenshots yields
byte-identical PNGs (md5 `9ea137d0...`).

### Full suite status

The whole `HashFleetTests` target now builds and passes: **427 tests in 39 suites**. The baseline
blockers previously recorded here (`MiningInsightsClient` scope, `MiningSetupTests` actor
isolation, `FleetPreferencesTests` / `FleetFixtureProtocol` access) were fixed in `0720c4d`, and
stale insights fixtures plus a real counter-sorting precision defect were fixed in `9d5739f`.
The temporary `MinerFansValidation` scheme and its source exclusions are gone; the standard
scheme is sufficient.
