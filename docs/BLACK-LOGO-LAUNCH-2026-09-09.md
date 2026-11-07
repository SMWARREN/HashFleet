# Fixed black logo launch and lighter graphite Solo · 2026-09-09

## Latest correction at 23:45 UTC

The user wants the black icon, black splash and single miner logo only because the previous branded splash visibly jumped. Solo should be a little lighter, still within the established graphite palette.

## Changes

- Home Screen icon catalog uses the existing `AppIconDark.png` as the sole default icon. No light variant is selected by the app catalog. iOS-controlled user tinting remains outside the app's control.
- Both native `LaunchScreen.storyboard` and `FleetStartupSplash` use the same fixed `HashFleetLaunch` image, copied byte-for-byte from the existing dark header artwork. Both use a 220 × 220 point image centered on the entire screen, not the safe area.
- Both stages have an opaque black background in every appearance. Removed the in-app wordmark/VStack, which had shifted the image upward compared with the native centered launch image.
- Existing two-second hold, tap-to-skip, cancellation, Reduce Motion dismissal and once-per-process behavior are retained. The in-app toolbar single-miner artwork and its existing theme behavior are unchanged.
- Only Solo becomes slightly lighter: #111111 → #21201E in both modes. This is the existing sampled blade graphite from the logo palette, not a new hue. Rounded layout, gold accents, calculations and other card surfaces remain unchanged.
- Unused old artwork files are not deleted or overwritten.

## Acceptance

Native checks exercise the compiled storyboard in both appearances and portrait/landscape, comparing the actual image with the shared launch asset, exact 220-point dimensions, full-screen center and black background. UI checks verify no wordmark, centered fixed-size miner, black splash in both modes, skip, automatic continuation and no warm-resume replay. Solo tests check its exact new graphite RGB, contrast, no blue/orange gradient and separation from the lighter miner cards.

Results and device delivery are recorded after validation.

### Passing validation

- 322 native tests across 29 suites passed, including compiled storyboard centering, black appearance, image identity, dimensions and palette contrast.
- All three focused UI tests passed: both-theme appearance/navigation, fixed black logo-only splash with exact full-screen geometry plus skip/warm resume, and automatic continuation.
- Result: scratch `HashFleetBlackLogoLighterSolo.xcresult`. Screens: `HashFleetBlackLogoScreens`. Reviewed the light-mode black splash image, with no wordmark or white surround.
- Static asset checks confirm a single default black app icon and a single launch image with no theme override. Launch image bytes match the existing dark artwork.
- Signed iPhone build and strict deep signature verification passed. Physical transition and Home Screen cache observation remain device-dependent.

### Device delivery

Executable source `e3ad7c6` installed and launched successfully on the paired iPhone 14 Pro Max at 23:52–23:53 UTC. Installation receipt `hashfleet-black-logo-install.json` records sequence 2368; `hashfleet-black-logo-launch.json` confirms launch. No device lock blocked this launch. Physical on-screen transition and Home Screen icon cache were not directly captured. No real miner settings were modified.
