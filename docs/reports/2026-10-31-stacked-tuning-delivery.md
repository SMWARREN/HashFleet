# Stacked Easy tuning correction, October 31, 2026

## Delivered

At approximately16:05 UTC, signed production **0.1.0(11)** was installed and launched on the user's iPhone. Installed metadata confirms build11. Source commit: `1e4dadf`.

This supersedes build10's rejected side-by-side layout. In **Easy**, Frequency is above Core voltage at every text size. Both remain visible without opening a disclosure. The fields have equal widths and aligned edges, including their scaled unit columns. The separate optional Technical details disclosure remains, but neither tuning field is inside it. Direct entry and all existing draft, validation, confirmation and hardware safeguards are unchanged. No miner settings were changed.

## Fresh verification

- **118 affected iOS tuning unit/render tests passed** across8 suites, with no failures or skips.
- **7 native UI tests passed**, including vertical order, equal widths and left edges, both controls in the initial standard-size viewport, >=44-point native fields, largest-text reachability, direct focus changes, reset, invalid-input blocking, mode continuity, and single confirmed loopback writes.
- **118 native Mac tests passed**, no failures or skips.
- **Strict SwiftLint: zero violations.**
- Production app and both extensions have build11, valid signatures, debugger disabled and the expected shared app group. Main app APNs environment remains production.
- Installation, launch and installed-version receipts passed. Existing app data was retained.

The whole1446-test iOS suite and Sonar scan were **not rerun for this bounded layout-only correction**. Their previous results belong to build10 and are not fresh build11 results. The previously documented secondary-simulator raw OCR sensitivity remains unchanged.

## Evidence

- `build/stack-build11-units-20261031-1559.xcresult`
- `build/stack-build11-ui-20261031-1559.xcresult`
- `build/stack-build11-mac-20261031-1600.xcresult`
- `build/sonar/stack-{units,ui,mac}-summary.json` and `stack-swiftlint.json`
- `build/HashFleet-stacked-20261031.xcarchive`
- `build/stack-distribution-20261031/Hash Fleet.ipa`
- `build/stack-phone-{install,launch,installed-app}.json`
- Verified screenshot: `~/.jcode/scratch/hashfleet-stacked-layout/4742C629-C99F-4C23-BE4E-710549371560.png`
