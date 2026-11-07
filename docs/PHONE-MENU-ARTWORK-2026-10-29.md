# Phone menu spacing and literal three-miner playback

Checked October 29, 2026. Implementation commit: `ca38dbe`.

## What the previous pass missed

1. **The separator clearance fix was Mac-only.** Both the shared settings row and navigation-row helpers returned the original control on iOS. On the installed iPhone simulator, the Widgets and Live Activity rows had a measured **0-point gap**. Native section rules also ran into the gray surfaces. Reviewing the Mac layout was not evidence that the phone menu had been fixed.
2. **The initial fan burst was only about four seconds.** The old artwork scheduler used two 2.016-second loops, followed by recurring rests and bursts. It did not provide the requested approximately ten-second automatic entrance.
3. **The image player could lose an active playback request.** Detaching its UIKit view stopped the display link, but reattachment did not resume it. A new regression reproduced an unchanged image until another configuration update or tap. AppKit had the same lifecycle structure.
4. **Add Miner did not contain the requested picture.** Its introduction used a vector network diagram. That is not the literal three-miner illustration the user meant.

All four defects were reproduced against unchanged production code before implementation in `red1.xcresult`. This was a focused review of the requested menu and artwork paths, not a new audit of the entire app.

## Changes

- Shared iOS settings Lists and Forms now have **12-point spacing between rows**, outside their tappable regions. Each section supplies independent rounded row backgrounds, with section rules hidden and row rules hidden by default. Explicit row-separator overrides remain meaningful.
- Removed redundant flat row-background overrides from App settings and its Widgets page. Native Mac minimum control heights and existing separator geometry are unchanged.
- The actual `FleetClusterArtLoop` illustration automatically plays **five complete loops, 10.08 seconds**, each time its view appears. It then rests. The same behavior is used by onboarding, the fleet-summary picture and Add Miner.
- Tapping or using the artwork's accessibility action still requests a shorter **4.032-second replay**. Appearance resets do not trigger tap haptics. Disappearance and inactive scenes stop playback. Reduce Motion leaves the picture still, including after a tap.
- UIKit and AppKit players retain requested playback across temporary window detachment. Explicit stop/dismantling clears the request, so paused or stopped images do not accidentally resume.
- No artwork assets, miner cards, status badges, device settings, discovery behavior or firmware were changed. Opening Add Miner for playback verification did not start discovery.

## Observed acceptance

All final checks ran after the last source edit, using strict Swift concurrency. No checks were skipped.

| Receipt | Observed result |
| --- | --- |
| `green1.xcresult` | 8 mobile WebP/timing test definitions and 3 installed phone-simulator UI tests passed |
| `green-accessibility.xcresult` | 79 retained tuner/chart unit and render definitions and 6 more installed phone-simulator UI tests passed |
| `native1.xcresult` | All 112 existing native test definitions passed, including settings clearance and accessible labels |
| `repeat-followthrough.xcresult` | All 3 selected UI definitions passed twice: 6 executions, 0 failures or skips |

The bounded follow-through completed October 29, 2026 at 08:10 UTC against the exact already-built app, without rebuilding or editing source or assertions. It repeated automatic approximately ten-second playback, both Add Miner presentations and Accessibility XXXL menu-gap/navigation checks. All three cases passed in both iterations, providing additional evidence against timing or view-reentry nondeterminism. This does not extend the physical-device or OS-background guarantees below.

Swift Testing parameterized invocations are not counted as separate test definitions in the table.

### Requirement-to-check map

- **Visible menu gaps:** actual row accessibility frames, at least 10 points of separation with the 12-point implementation, minimum 44-point control heights, actual exported screenshots and successful navigation to Widgets.
- **Large text:** repeat the settings gap/navigation check at Accessibility XXXL, with scrolling to reach full labels. Existing onboarding artwork and Bitsy accessibility-size test also passed.
- **Automatic playback, not tap-only:** compare cropped pixels of the actual onboarding picture without tapping, including beyond the old four-second entrance. Confirm later cropped frames are identical after the bounded entrance has settled.
- **Correct Add Miner picture and repeat loads:** check actual fan-pixel changes on two separate presentations of Add Miner, and verify discovery remains idle.
- **All existing picture placements:** check the fleet-summary illustration starts automatically as Demo loads. Onboarding and Add Miner use the same playback component.
- **Retained manual behavior:** existing tap-start, moving pixels and subsequent still-frame assertions passed unchanged.
- **Reduce Motion:** existing onboarding still-frame test and new Add Miner still-frame test passed, including taps.
- **Player lifecycle:** real two-frame WebP advances after detach/reattach without reconfiguration. Paused and explicitly stopped cases stay still. The bundled cluster's measured frame timing matches the selected complete-loop durations.
- **Shared-code compatibility:** full existing native suite passed. Existing native render-harness environment-read warnings remain in the receipt and are not claimed fixed.

The old recurring-automatic-burst expectation was deliberately replaced because indefinite automatic restarts conflict with the newly requested bounded load animation. Its replacement checks the real dashboard picture's automatic entrance. The original tap/reduce-motion/accessibility assertions were not weakened.

## Evidence and limits

Evidence directory:

`/Users/USER/.jcode/scratch/hashfleet-menu-motion-20261029-0727/`

Before/after menu captures, Add Miner captures, onboarding captures and large-text/reduced-motion captures are in the exported attachment directories beside the result bundles. Actual normal-size menu and artwork pixels, and large-text phone captures, were inspected rather than inferring appearance from source or accessibility identifiers alone.

The installed UI checks used the owned 402-by-874-point iPhone simulator. **These changes have not been installed on the physical phone.** No physical-phone reinstall, reset, permission changes or data cleanup was performed for this request. No real miner or mining Mac was contacted, and no pool, wallet or firmware settings were accessed or changed.

All **74 unrelated tracked patches** and **24 original untracked files** remain unchanged. Only the eleven menu/artwork implementation and test files belong to `ca38dbe`.
