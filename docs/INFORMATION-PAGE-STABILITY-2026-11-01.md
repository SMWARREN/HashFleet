# About and Support stability repair, November 1, 2026

## Owner requirement

Use a common layout, avoid compressed content or moving informational pages, and test real scrolling viewports with screenshots. Preserve the existing phone installation and the single canonical native Mac installation.

## Implementation

- About and Support now reuse `FleetSettingsIntroduction`, built from the existing settings section and row primitives. Artwork no longer determines text height. Text wraps naturally without shrink-to-fit.
- Removed About's repeating ambient animation, the broad animation transaction, fixed 250-point decorative layer, and entrance state that replayed after scrolling away and back.
- Currency headings and address/network text are more readable. Copy labels have a minimum 44-point height and grow with Dynamic Type. Immutable destinations, copy-only behavior, storefront revalidation, and payment policy are unchanged.
- About keeps a compact link to the separate Support page. It does not duplicate the entire currency/payment form.
- `CLAUDE.md` records the common-layout and actual-screenshot requirement for subsequent work.

## Visual evidence and checks

Private artifacts: `~/.jcode/scratch/hashfleet-stability-20261101.noindex/`. These include full result bundles, actual PNG attachments, logs, signing receipts, and private data backups. Do not commit private backups or wallet values.

The new `FleetInformationPageViewportTests` mounts the real production SwiftUI pages in a non-key observer window. It captures the presented hierarchy, not just a model layer, at 375x812, 430x932, 932x430, and 768x1024 points. About is photographed initially, after 3.2 seconds idle, at the bottom, and after returning to the top. Support is photographed through ordinary scrolling, including accessibility3 text at 390x844. Real OCR must observe every currency copy label. A deliberately moving control proves screenshots detect motion with system Reduce Motion disabled.

### Preserved investigation failures

- The first attempt did not compile because the accessibility Reduce Motion environment property is read-only. The actual system setting is now required to be off.
- `viewports-real.xcresult` executed all four tests and found three check/harness issues. The 375-point initial/idle images differ at only 187 pixels in the system glass Done button border, bounding box 860,186 through 1075,317 pixels. The largest decoded channel difference was 0.00851. No content pixels moved. Decoded content below the actual navigation bar is now compared exactly, with no content tolerance or artificial stabilization. The negative control remains unmasked.
- A scroll-view finder incorrectly rejected a list before its lazy content size grew. It now locates the real scroll view and inspects every visible page. Large-text copy labels naturally wrap, so actual adjacent OCR words are accepted across line breaks rather than requiring one baseline.
- `viewports-final.xcresult` preserved intermittent UIKit auto-promotion of the observer window to key status. The harness now explicitly prevents that promotion rather than removing the original key-window assertions. An attempted readiness gate also waited for a task owned by an offscreen lazy section. That deadlock was removed without bypassing the final requirement to see all three real currency controls.
- Prior task's unrelated Backup-page OCR failure remains documented in `SUPPORT-ABOUT-LAYOUT-REPAIR-2026-11-01.md`. This task does not claim the entire app test suite passed.

## Delivery

### Passed visual and policy acceptance

`viewports-verified.xcresult` executed four tests, including both four-size parameter matrices, and passed in 121.784 seconds. The moving negative control, exact idle content pixels, scroll-return geometry, currency visibility through ordinary scrolling, and accessibility3 wrapping all passed. Final portrait, landscape-shaped, tablet-size and large-text PNGs were extracted for inspection. These are mounted simulator viewports, not physical-phone or real device-rotation screenshots. Nine core support-policy tests and two native/website destination-parity tests passed.

### Phone build15

Installed in place over build14 and launched normally. All three signed bundles retained the same identities, shared group, existing profile-authorized certificate and production push entitlements. No app was uninstalled and the app inventory did not change.

The strict byte-for-byte comparison against the earlier snapshot failed and remains preserved. Four accessible files remain present, but background monitoring between snapshots added 1,753 history readings and changed runtime observation caches. All 29 preference key names remain, saved miners, appearance, notification inbox, push settings and every other durable preference are semantically unchanged. The push-settings byte difference is only JSON serialization, not changed fields. Every previous database row is identical, checked with SQL `EXCEPT` across readings, achievements, connectivity and pool-switch history. Database quick-check passes. The receipt truthfully records `all_accessible_files_byte_identical: false`. No prior data was restored over new observations. Keychain contents were not independently read.

### Native Mac

The canonical `/Applications/Hash Fleet.app` was updated using the normal atomic installer. Stopped-state preferences and history database were byte-identical across installation, with private consistent SQLite backup. The actual repaired About window was photographed through the desktop helper at 1835x1227 points. This caught the short Support link stretching to match its taller grid neighbour, so a final Mac-only refinement uses the existing full-width-row primitive. The conditional Mac-only modifier does not change phone build15 layout. Earlier stale-PID/window screenshot failures and two SIGTERM process exits are not counted as visual passes. No crash root cause is asserted.

No separate native Mac test app is used. Before the final Mac-only refinement, physical path, LaunchServices, Dock, process, saved-miner and signature checks found only the canonical installation, with six generated bundles reversibly retired. Final Mac refinement installation and single-copy recheck are pending.
