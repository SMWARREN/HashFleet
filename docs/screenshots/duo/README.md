# iPhone Duo App Store Screenshots

Screenshots of Hash Fleet on the foldable iPhone Duo, captured by `AppTests/iPhoneDuoScreenshotCaptureTests.swift` (demo fleet, rendered at @3x). Open `preview.html` to see them all.

## Files

| File | Screen | Points | Pixels | Size class |
|---|---|---|---|---|
| `iphone-duo-outer-dashboard.png` | Folded outer display | 466 × 678 | 1398 × 2034 | Compact |
| `iphone-duo-inner-dashboard.png` | Unfolded inner display, dashboard only | 669 × 951 | 2007 × 2853 | Regular |
| `iphone-duo-inner-menu-split.png` | Unfolded inner display, menu open on left | 669 × 951 | 2007 × 2853 | Regular |
| `iphone-duo-inner-detail.png` | Unfolded inner display, miner detail | 669 × 951 | 2007 × 2853 | Regular |

## Every page (`all/`)

`AppTests/iPhoneDuoFullGalleryCaptureTests.swift` renders 11 pages on both screens offscreen (22 images, demo fleet): overview, miner detail, network, energy, achievements, reports, backup, preferences, about, support and add miner. Files are named `NN-inner-<page>.png` (2007 × 2853, menu docked left) and `NN-outer-<page>.png` (1398 × 2034).

## Layout behavior

- **Folded (outer):** single-column phone layout.
- **Unfolded (inner), menu open:** the menu is docked on the full left panel and the page fills the right panel, so the seam lands on the fold. The page is never covered or dimmed.
- **Unfolded, menu closed:** the sidebar button hides the menu and the page uses the full screen in two columns. The button then sits at the top left of the page to reopen it. The choice is remembered per window.
- iPad and Mac keep the standard split view. The fold rule only applies on iPhone widths of 560 to 820 pt (`FleetLayout.foldSidebarWidth`).

## App Store upload

These sizes are the iPhone Duo display sizes, not one of App Store Connect's standard iPhone screenshot sizes (for example 6.9-inch at 1320 × 2868). Confirm in App Store Connect which display slot accepts them before uploading. If no iPhone Duo slot exists, re-render at a supported size.

The `hashfleet-mac-*.png` and `mac-*.png` files are reference captures from Mac testing, not App Store-sized.
