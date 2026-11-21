# Animated WebP playback

HashFleet keeps the bundled fan animation and prepares its moving frames away from the UI executor. This change does not replace the artwork with a different animation or change miner behavior.

## Playback design

- `App/Design/WebPFrameStore.swift` owns ImageIO sources in one serial actor. A bitmap-context draw realizes each frame before UIKit or AppKit receives it. The UI clock selects an authored frame index and presents the prepared image.
- Prepared pixels are keyed by animation, frame, display size, backing scale, and platform geometry. UIKit preserves aspect-fit. AppKit preserves the earlier logical-size behavior, including its existing non-square presentation.
- The shared prepared-frame LRU has a **16 MiB** budget, charged using actual bitmap row stride. Displayed and in-flight frames hold leases and cannot be evicted. At most three ImageIO sources are retained.
- Each view has one metadata-preparation task and one frame task. Playback skips obsolete indices rather than accumulating decode tasks. Generation checks reject results from an old asset, size, scale, or playback lifecycle.
- A fully leased cache returns a temporary busy result. One cancellable task retries at 100 ms intervals without exceeding the frame budget. A non-busy failure stops the clock and leaves the poster or previous frame visible rather than retrying every tick.
- Data, size, scale, pause, detach, and stop transitions reset the failure latch. Merely changing a failed view from paused to playing is not a reset. A transient decode failure can therefore leave it still until another reset transition.
- The existing named PNG is visible while the first WebP frame prepares asynchronously. UIKit reports the requested logical intrinsic size during this poster phase so the native image view does not inherit the PNG's larger source dimensions.

The bundled artwork remains **640 × 640**, with **48 frames at 42 ms** per frame, a **2.016 s** loop. The load-art entrance remains five loops (**10.080 s**), and tap replay remains two loops (**4.032 s**). Reduce Motion, visibility, scene-phase, static fallback, and teardown behavior are preserved.

## Native regression tests

On macOS with the repository's supported Xcode toolchain:

```sh
export JCODE_SCRATCH_DIR="$HOME/Library/Caches/HashFleetPlayback"
Scripts/test-webp-playback.sh
```

The script compiles the actual production player, frame store, and art wrapper in a temporary Swift package. It executes `MacAppTests/AnimatedWebPPlaybackTests.swift` without an app host, saved fleet, network, Simulator, installation, or display activation. It rejects an empty test run.

The suite contains 13 methods. Coverage includes all three assets in both platform geometries, timing and alpha, shared and scale-specific frames, cache bounds and concurrent consumers, cancellation, resize, detach/reattach, explicit stop, stale results after asset replacement, temporary cache pressure, permanent-failure latching, and abandoned-view lifetime. The six asset/geometry cases perform 288 frame comparisons. Their reference uses the same drawing approach, so these checks establish internal consistency, not independent proof of identical historical Core Animation sampling.

The same test source belongs to `HashFleetMacTests` in the Xcode project. `build-for-testing` checks that integration, but is not evidence that hosted Mac tests executed.

## Hosted UIKit checks

Use **method-level selectors** for Swift Testing. Selecting only the target or suite has previously produced a successful command with zero tests executed. Inspect the actual executed count, not just the exit status.

Set `SIMULATOR_ID` to an available iPhone simulator from `xcrun simctl list devices available`, then run:

```sh
xcodebuild test \
  -project HashFleet.xcodeproj -scheme HashFleet -configuration Debug \
  -destination "platform=iOS Simulator,id=${SIMULATOR_ID:?Set SIMULATOR_ID first}" \
  -derivedDataPath "$HOME/Library/Developer/Xcode/DerivedData/HashFleetPlayback" \
  CODE_SIGNING_ALLOWED=NO \
  '-only-testing:HashFleetTests/AnimatedWebPTests/frameDurationIgnoresZeroDelayAndPrefersUnclampedTiming()' \
  '-only-testing:HashFleetTests/AnimatedWebPTests/decodesTheBundledBrandLoopFromTheApplicationAssetCatalog()' \
  '-only-testing:HashFleetTests/AnimatedWebPTests/decodesTransparentAnimatedWebPFramesAndTiming()' \
  '-only-testing:HashFleetTests/AnimatedWebPTests/rejectsStaticPNGAsAnAnimatedWebP()' \
  '-only-testing:HashFleetTests/AnimatedWebPTests/playerDisplaysTheOpeningFrameWhenMotionIsPaused()' \
  '-only-testing:HashFleetTests/AnimatedWebPTests/requestedPlaybackResumesWhenTheImageIsReattachedToItsWindow()' \
  '-only-testing:HashFleetTests/AnimatedWebPTests/fleetEntranceUsesFiveRealBundledFanLoops()' \
  '-only-testing:HashFleetTests/AnimatedWebPTests/pausedOrExplicitlyStoppedPlaybackDoesNotResumeOnReattachment(explicitStop:)' \
  '-only-testing:HashFleetTests/AnimatedWebPTests/approvedPosterIsVisibleImmediatelyWhileTheColdLoopPrepares()' \
  '-only-testing:HashFleetTests/AnimatedWebPTests/coldPosterKeepsRequestedUIKitBoundsBeforeAnyFramePrepares()'
```

The cold-poster regression mounts the real SwiftUI representable in a hosting controller and synchronously checks the **UIKit player's bounds**, before a prepared frame arrives. It covers three assets in light and dark mode. The initial regression reproduced six incorrect native bounds; the intrinsic-size fix made all six match their requested dimensions.

The existing held-splash motion and splash-dismissal UI checks are:

- `HashFleetUITests/HashFleetUITests/testBundledBrandLoopChangesFanPixelsOnTheHeldSplash`
- `HashFleetUITests/HashFleetUITests/testThemedHashFleetSplashCanBeSkippedAndDoesNotRepeatOnResume`

The held-splash comparison alone cannot distinguish poster replacement from continuous motion. Native and hosted UIKit lifecycle tests separately check actual frame advance.

## Focused rendering benchmark

```sh
Scripts/benchmark-webp-playback.sh
```

This compiles the production store and compares two forced AppKit drawing paths at 2× scale. The baseline is an inline reconstruction of the previous uncached ImageIO path, not a separately checked-out historical binary. Both paths use the same assets, sizes, and destination surface.

Interpret the JSON fields separately:

- `baselineUI` and `preparedUI` measure main-thread rendering-path work.
- `asynchronousRequest` measures frame-request/preparation latency, excluded from `preparedUI`.
- `coldFirstFrameMS` includes metadata preparation and the first request/draw.
- `peakPreparedBytes` accounts for retained prepared bitmaps, including leases, not total process memory.

Median and p95 values use simple sorted-sample positions and are approximate. The benchmark does **not** establish whole-app hitch rates, total CPU, total RAM, launch responsiveness, iOS device performance, or the behavior of an installed binary.

## Validation and known costs

The implementation was checked on November 21, 2026 with 13 native test methods, 10 hosted iOS methods, and two existing splash UI tests passing. The native app and real Xcode Mac test target also compiled. Hosted Xcode Mac tests were **not run**. The public PR checkout repeats the native suite and strict lint; CI provides the public-source build checks.

Manual iPhone and Mac feedback described the update as snappier. This is user-observed feedback, not a controlled whole-app performance measurement or proof that every historical navigation hang is resolved.

Known limitations:

- There is no memory-warning or background trim hook. Unleased prepared frames can remain near the 16 MiB budget, and source objects remain separately retained.
- Compressed asset data, ImageIO state, temporary decode surfaces, the PNG poster, and compositor allocations are outside that prepared-frame budget. A loop larger than the cache can have no cache hits and still decode every frame off main.
- Initial PNG loading/drawing and possible Core Animation pixel-format conversion are not measured by the WebP benchmark.
- The named poster is not necessarily pixel-identical to WebP frame zero, particularly in light mode. No artwork was changed to hide that transition.
- These changes do not alter networking, polling, layout algorithms, telemetry persistence, miner configuration, signing, or release automation. A source PR is not an app-store submission or release.
