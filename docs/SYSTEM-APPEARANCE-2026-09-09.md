# System appearance and automatic icons · 2026-09-09

**21:42 UTC follow-up:** opposite-mode neutral hashrate cards now replace orange fields, with contrast-safe text and no waivers. The newly supplied white miner replaces the light icon/header. A centered native launch storyboard follows system appearance. See `ADAPTIVE-HASHRATE-2026-09-09.md`.

**Historical 10:26 UTC follow-up:** the user requested plain text with no border. The contour described below has now been removed from both hashrate panels. System/icon behavior remains unchanged. Plain white on orange is recorded as a known contrast limitation, not an accessibility pass.

## Original requested behavior (superseded palette)

- The same bright orange `#FFA51F` hashrate surface in Light and Dark.
- Keep black readings in Light and white readings in Dark.
- Start the app in System appearance, then permit persistent Light/Dark overrides.
- Supply a light-background and black-background app icon for automatic system selection.

## Implementation

`FleetPreferences.Appearance` is now System / Light / Dark. System maps to a nil SwiftUI preferred color scheme, so the app and its existing header image variants resolve from the system environment. The dashboard toggle uses the **resolved environment**, not the stored preference, so it always selects the opposite visible mode. Settings can restore System.

A one-time migration changes the old forced two-mode setting to System on upgrade, as requested. The migration marker prevents subsequent launches from overwriting a new manual choice. Other defaults, saved miners and monitoring settings are untouched. Invalid appearance values recover to System. Tests use an isolated defaults suite. Existing appearance tests explicitly start Dark, while the new System test deliberately uses the production default.

The app icon catalog now uses `AppIconLight.png` and a `luminosity: dark` `AppIconDark.png`. Both are 1024×1024 opaque size derivatives of the **existing** HeaderLight/HeaderDark artwork, with no new artwork or recoloring. The unrelated modified `AppIcon.png` file is preserved, not overwritten. `assetutil` verifies both ordinary and `UIAppearanceDark` icon renditions for phone and iPad in the signed app's Assets.car.

**iOS controls Home Screen icon appearance.** Automatic icon mode follows system appearance. If the user pins Home Screen icons to Light, Dark, Tinted or Clear, the app does not override that choice. The in-app manual theme override does not change the Home Screen preference. No alternate-icon API, confirmation alert or system setting mutation is used.

## Orange text readability (historical contour, superseded)

The user explicitly rejected darkening the orange surface. White directly on this bright orange is only **1.97:1**, so it is not claimed to pass ordinary text contrast. A thin 0.4-point solid black contour is drawn around dark-mode white glyphs **before** the orange background is applied. This retains the requested white/black flip without changing the orange. Light-mode text has no outline.

The palette checks now distinguish the white-to-black-contour pair from the contour-to-orange pair. The former is 21:1, the latter 10.65:1. Light primary/captions remain 10.65:1 and 9.10:1. These are color-pair checks, not proof of whole-screen accessibility or a claim that plain white on orange meets 7:1. The first one-point contour looked too heavy in screenshot review and was reduced to 0.4 points.

## Verification

- `HashFleetSystemLight.xcresult`: all **13 preference unit tests and two UI tests passed** with the actual simulator system preference set to Light. Tests cover one-time migration, persistence, nil/explicit schemes, exact roles, appearance/navigation and System → Dark override → System. Attachment `System Light dashboard` confirms the requested OS setting resolved correctly.
- `HashFleetSystemDark.xcresult`: the System UI test passed after changing the actual simulator preference to Dark. It exercises System → Light override → System with canvas pixel checks.
- The generic iOS app and widget build passed. Compiled icon inspection found `AppIconLight.png` and `AppIconDark.png` / `UIAppearanceDark` for both phone and iPad. Both icon PNGs have no alpha.
- `HashFleetSystemFinal.xcresult` passed both UI tests on the final 0.4-point contour revision, including System Dark → Light override → System Dark. The final dark dashboard was visually reviewed. Current dashboard attachments and hashes are in `docs/research/neutral-palette-2026/screenshots/manifest.json`.
- Final signed build and strict deep signature verification passed. The app installed on the iPhone at **08:00 UTC** (`hashfleet-system-final-install.json` in local scratch). Normal launch without test flags was denied because the phone was locked (`hashfleet-system-final-launch.json`). The System migration will apply when the user opens the app. No app-data reset or miner write was performed.

Physical-phone appearance, automatic Home Screen icon switching and the previously reported detail crash still require unlocked-device interaction. No simulator evidence is presented as physical-phone acceptance.
