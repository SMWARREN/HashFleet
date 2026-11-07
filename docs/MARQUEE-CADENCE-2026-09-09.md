# Marquee cadence and restored numeric transitions

The user reported that the previous width fixes still looked like intermittent pauses and explicitly requested restoring the bouncing number effect. This supersedes the prior removal of numeric transitions.

## Changes
- Restored the existing `fleetNumericUpdate` effect on marquee text, retaining monospaced digits.
- Removed the explicit 30 Hz minimum-interval throttle from the animation timeline. SwiftUI now chooses the display cadence, subject to device/system scheduling.
- Constructed the repeated text track outside the per-frame timeline closure. Only the horizontal offset needs frame updates.
- Cleared inherited animation on the time-derived horizontal offset. Child numeric transitions still opt into their own animation, so scrolling is not repeatedly eased toward successive frame positions.
- Retained the existing measured-width position preservation, pause/resume, scene/visibility suspension and static accessibility layout.

The demo readings are static, so numeric updates cannot explain every reported pause. The frame cap is code-confirmed, but the exact physical-device hitch cause has not been established with an Instruments trace. These changes must not be described as a measured guarantee of 60/120 FPS or proof that every physical-device pause is eliminated.

## Validation
- 35 native ticker tests passed, including geometry rebasing and paused/running clock behavior.
- Three simulator UI tests passed: twelve consecutive motion sample comparisons with the seven-pool demo, actual pause/resume pixels, and full static accessibility summaries.
- The first new UI test attempt failed because a full swipe scrolled the ticker out of view. Replaced it with a bounded drag that centers the ticker. No motion assertion or pixel threshold was weakened.
- Screenshot samples establish motion across the sampled intervals, not frame-by-frame smoothness or live-telemetry animation fidelity.
- Signed iPhone build and strict codesign verification passed. The app installed at 20:27 UTC, but opening it automatically was denied because the device was locked. Real miner settings were not changed.

Evidence under `/Users/USER/.jcode/scratch/`: `HashFleetContinuousMarqueeRetry.xcresult`, `hashfleet-continuous-marquee-retry.log`, `hashfleet-continuous-marquee-device.log`, `hashfleet-continuous-marquee-install.json`, `hashfleet-continuous-marquee-launch.json`.
