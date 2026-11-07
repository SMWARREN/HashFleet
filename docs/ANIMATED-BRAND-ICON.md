# Animated Hash Fleet brand icon

## Current result

The startup splash now includes a locally authored, transparent animated WebP made from the existing approved Hash Fleet still. It is a deterministic image-processing loop, not an AI/video-model result and not an output from `3dicon`: the miner case and hub remain stationary, the fan-blade annulus rotates clockwise, and the amber status strip gently pulses. No OpenAI/OpenRouter request, API credential, ComfyUI model download, or rented GPU was used to create this asset.

The bundled asset is `App/Resources/Assets.xcassets/HashFleetBrandLoop.dataset/HashFleetBrandLoop.webp`. It is 640×640, 48 frames, 42 ms per frame (about 23.8 fps), 2.016 seconds per loop, lossless WebP with alpha, and approximately 2.8 MiB. It repeats indefinitely on the startup splash. The approved `HashFleetLaunch` still remains the fallback if the data set is absent or invalid. Reduce Motion pauses the WebP on its opening frame.

## Why this route was selected

The earlier request asked to look at [samyost1/3dicon](https://github.com/samyost1/3dicon) and prefer local generation over OpenRouter, with a rented Vast GPU as a possible fallback. The `3dicon` CLI supports direct OpenAI or Gemini for still generation, but its motion path is hosted: OpenRouter/Seedance by default or Replicate/Kling when selected. Neither motion provider runs locally. The historical Hash Fleet still prompt is available in Jcode's generated-image metadata, but no separate earlier motion prompt was found. The full still prompt is retained outside this repository alongside that generated image.

A scratch ComfyUI checkout and Python environment were prepared on the Apple Silicon M5 Max (48 GB unified memory). PyTorch 2.14.0 reports MPS available and a basic tensor smoke test passes. That only proves basic MPS availability, not Wan inference. No Wan weights were downloaded. The official Wan 2.2 14B first/last-frame graph requires roughly 35.6 GB of model files including the text encoder and VAE, and its FP8 path has reported MPS dtype failures. Other public reports describe corrupted Wan 2.2 output on M-series systems, including temporal artifacts on M3/M4, with behavior varying by chip and workflow. Relevant upstream reports: [ComfyUI #9255](https://github.com/Comfy-Org/ComfyUI/issues/9255), [#15010](https://github.com/Comfy-Org/ComfyUI/issues/15010), and [#15793](https://github.com/Comfy-Org/ComfyUI/issues/15793). These reports do not establish that every Wan configuration fails on M5, but they made downloading tens of gigabytes before a representative test a poor next step.

The repository also retains `Tools/prepare_hash_fleet_wan_workflow.py` as an optional graph-preparation adapter for the official [Wan 2.2 first/last-frame workflow](https://raw.githubusercontent.com/Comfy-Org/workflow_templates/main/templates/video_wan2_2_14B_flf2v.json). It prepares the prompt inputs only; it does not install models or execute ComfyUI. The procedural WebP is the route currently integrated and validated in the app.

Vast was not provisioned. No Vast CLI or API credential was configured, and a browser marketplace session was unavailable. Public listing prices are volatile and storage/bandwidth add costs, so an old price snapshot is not a safe basis for renting. The user asked to try a workable route, so the local deterministic transformation was chosen to deliver an actual tested animation without provider or marketplace spend. A future AI-generated motion version can replace this data set without changing the player interface.

## Regenerate the local loop

The generator is `Tools/generate_hash_fleet_brand_loop.py`. It reads the approved transparent still by default from `HashFleetLaunch.imageset/LaunchMinerTransparentDark.png`, applies fixed rotor/LED masks calibrated to that artwork, then writes a looping transparent WebP. It needs Python and Pillow only, no model, API key, network access, or cloud compute.

```bash
python3 -m venv .venv
.venv/bin/python -m pip install Pillow
.venv/bin/python Tools/generate_hash_fleet_brand_loop.py \
  --output App/Resources/Assets.xcassets/HashFleetBrandLoop.dataset/HashFleetBrandLoop.webp
```

Optional flags are `--source`, `--size`, `--frames`, `--frame-duration-ms`, `--rotor-center X Y`, `--rotor-inner-radius`, `--rotor-outer-radius`, and `--led-region LEFT TOP RIGHT BOTTOM`. The default mask coordinates are calibrated to the current 1254×1254 launch image. If that source artwork or its layout changes, inspect and retune these coordinates before regenerating. `Tools/test_generate_hash_fleet_brand_loop.py` covers rotation, fixed hub, alpha, looping output, and invalid inputs:

```bash
python3 -m unittest discover -s Tools -p 'test_generate_hash_fleet_brand_loop.py' -v
```

## 3dicon generation handoff

The checked-out upstream [`samyost1/3dicon`](https://github.com/samyost1/3dicon) CLI can animate the approved still, but its motion stage is not a local OpenAI call. The still stage supports OpenAI, Gemini, and OpenRouter image backends; motion uses hosted Kling through OpenRouter by default or Replicate when selected. An OpenAI API key by itself therefore cannot produce the motion clip. Do not run a paid motion request without an explicit budget/provider approval. The CLI's `--dry-run` composes the motion prompt without making an API request, and was exercised against the approved miner still.

From the Hash Fleet repository root, install the upstream skill and prepare a work directory. `ffmpeg` must be on `PATH`:

```bash
export REPO="$PWD"
git clone https://github.com/samyost1/3dicon.git "$HOME/.cache/3dicon"
cd "$HOME/.cache/3dicon/skills/3dicon"
python3 -m venv .venv
.venv/bin/pip install -r requirements.txt
export PYTHONPATH="$PWD"
export WORK="$HOME/.cache/hashfleet-3dicon"
mkdir -p "$WORK"
```

Review the composed prompt at no cost using the existing transparent still:

```bash
python3 -m iconloop --out "$WORK" animate \
  --still "$REPO/App/Resources/Assets.xcassets/HashFleetLaunch.imageset/LaunchMinerTransparentDark.png" \
  --motion 'Only the fan blades rotate smoothly inside the fixed grille; keep the miner case and center hub perfectly still.' \
  --strategy part --energy calm --via openrouter --dry-run
```

If a motion provider and budget are approved, rerun the same command without `--dry-run`, then produce and validate the transparent loop:

```bash
python3 -m iconloop --out "$WORK" animate \
  --still "$REPO/App/Resources/Assets.xcassets/HashFleetLaunch.imageset/LaunchMinerTransparentDark.png" \
  --motion 'Only the fan blades rotate smoothly inside the fixed grille; keep the miner case and center hub perfectly still.' \
  --strategy part --energy calm --via openrouter
python3 -m iconloop --out "$WORK" matte
python3 -m iconloop --out "$WORK" encode --size 384 --name HashFleetBrandLoop
python3 -m iconloop --out "$WORK" verify
```

Return to the Hash Fleet repository root. Inspect and validate the generated WebP before importing it. The importer checks for an infinitely looping animated WebP with transparency, timing, and visible frame changes. Stage it outside the asset catalog first; the current accepted asset is never replaced implicitly:

```bash
cd "$REPO"
python3 Tools/import_3dicon_webp.py "$WORK/HashFleetBrandLoop.webp" --dry-run
python3 Tools/import_3dicon_webp.py "$WORK/HashFleetBrandLoop.webp" \
  --output "$WORK/HashFleetBrandLoop-candidate.webp"
```

Only after reviewing the staged candidate should it replace the app's named data-set file. The explicit `--replace` is required, after which rebuild the app and repeat the focused animation unit and simulator UI tests below:

```bash
python3 Tools/import_3dicon_webp.py "$WORK/HashFleetBrandLoop.webp" --replace
```

No 3dicon-generated motion has been imported into the app. The current, user-approved splash remains the locally generated rotor animation described above. `Tools/import_3dicon_webp.py` and `Tools/test_import_3dicon_webp.py` provide the guarded handoff and tests for the imported-asset contract.

## Asset catalog and app behavior

The WebP is an Xcode universal Data Set:

```text
App/Resources/Assets.xcassets/HashFleetBrandLoop.dataset/
  Contents.json
  HashFleetBrandLoop.webp
```

`FleetStartupSplash` lazily loads the named data set once per app process and checks that ImageIO recognizes multiple WebP frames, avoiding an initial static-image flash and repeated reads of the 2.8 MiB payload. `AnimatedWebPImage` decodes only the current frame and uses ImageIO's per-frame timing, falling back to a sensible default for missing or zero delays. If the data set is missing, invalid, or static, the splash displays the approved `HashFleetLaunch` still with its native amber accent instead. When system Reduce Motion is enabled, the player shows the first frame without starting its display link.

The image view remains 220 points square at the existing centered layout. Decoded pixel dimensions are mapped to that logical size so accessibility geometry does not report the WebP's 640-pixel source dimensions. Replacing the WebP does not require a provider integration or a runtime network request.

## Validation

The generator tests cover deterministic frame creation, the packaged loop's stable alpha bounds, seam continuity, custom-source geometry, and invalid-input failures. App unit coverage decodes the actual named Data Set from the hosted application bundle, checks frame count, frame timing, alpha, visible frame change, static-image rejection, and paused playback. Simulator UI tests compare two fan crops from the running splash, then exercise 220-point layout in light/dark appearance, skip behavior, and no replay after resume.

Use the exact Swift Testing case identifiers below. In the current Xcode toolchain, selecting only `HashFleetTests/AnimatedWebPTests` can report success while running zero unit tests; these method-level selectors were verified to execute the suite. Substitute an available simulator UDID as needed. Run the app unit tests:

```bash
xcodebuild test -project HashFleet.xcodeproj -scheme HashFleet \
  -destination 'platform=iOS Simulator,id=DFEC3CE3-FCE6-45B5-BCCC-859021678733' \
  '-only-testing:HashFleetTests/AnimatedWebPTests/frameDurationIgnoresZeroDelayAndPrefersUnclampedTiming()' \
  '-only-testing:HashFleetTests/AnimatedWebPTests/decodesTheBundledBrandLoopFromTheApplicationAssetCatalog()' \
  '-only-testing:HashFleetTests/AnimatedWebPTests/decodesTransparentAnimatedWebPFramesAndTiming()' \
  '-only-testing:HashFleetTests/AnimatedWebPTests/rejectsStaticPNGAsAnAnimatedWebP()' \
  '-only-testing:HashFleetTests/AnimatedWebPTests/playerDisplaysTheOpeningFrameWhenMotionIsPaused()'
```

Then run the real app launch and splash interactions:

```bash
xcodebuild test -project HashFleet.xcodeproj -scheme HashFleet \
  -destination 'platform=iOS Simulator,id=DFEC3CE3-FCE6-45B5-BCCC-859021678733' \
  -only-testing:HashFleetUITests/HashFleetUITests/testBundledBrandLoopChangesFanPixelsOnTheHeldSplash \
  -only-testing:HashFleetUITests/HashFleetUITests/testThemedHashFleetSplashCanBeSkippedAndDoesNotRepeatOnResume
```

The full `HashFleetTests` target includes unrelated real notification-delivery tests that require simulator authorization; without it, those four cases fail even while the `AnimatedWebPTests` suite passes. The focused command above avoids confusing that environment-specific permission state with the animation acceptance result.

Also inspect the final asset directly with `webpmux -info` if libwebp tools are installed, or through ImageIO in the app test. Verify that the asset catalog compiles the named data set into the built app; the app-bundle unit test fails if it does not.
