# Native Mac Frequency shortcut freeze, 2026-11-01

## Reproduction and scope

On the native macOS build 12, opening a demo miner through the dashboard,
then **Tuning settings**, showed the expected editable frequency/voltage fields.
Returning and pressing **Frequency & voltage** instead left the process alive
at approximately 100% CPU with an unresponsive accessibility tree. A main-thread
sample showed AppKit layout, SwiftUI navigation and AttributeGraph updates.
This was a native UI hang, not the earlier iOS Simulator dyld startup crash.

The two entrances previously used different navigation mechanisms. The card's
Tuning settings link used a destination-closure `NavigationLink`. The shortcut
set an optional `MinerDevice` binding consumed by `navigationDestination(item:)`.
Only the Mac shortcut now uses the working destination-link route. Its link is
behind an `AnyView` boundary because this custom Layout has a separately recorded
opaque NavigationLink copy failure. The iOS binding route is unchanged.

This isolates the trigger and validates the workaround. It does not establish an
internal SwiftUI framework root cause. No voltage/frequency parsing, payload,
review, hardware-write gates, saved fleet or app installation identifiers changed.

## Regression check

The previous tests did not exercise this actual native-window transition. The
new external accessibility check exercises both routes from both parent contexts:

```sh
python3.12 Scripts/tests/native_mac_navigation_smoke.py \
  --app '/absolute/path/Hash Fleet.app' \
  --work-dir "$PWD/build/native-navigation-acceptance"
```

Run in a logged-in macOS desktop with Xcode command-line tools and Accessibility
permission for the invoking terminal/agent. The test opens an isolated
`--ui-testing --demo` instance, so its window will briefly appear. Do not interact
with that instance while the test runs. It never presses Apply or reads a saved
fleet. It only terminates its own launched PID.

The test checks all six round trips: Tuning settings once and Frequency twice,
first from a dashboard miner link and then from a sidebar miner link. Each must
show enabled frequency and voltage text fields with the expected demo values,
keep demo Apply disabled, retain the demo restriction, and support Back. Every
AX subprocess has an eight-second timeout, so a frozen UI cannot indefinitely
block the test runner. JSON accessibility snapshots are saved in the work directory.

The same test fails on the preserved pre-fix Release app immediately after the
Frequency shortcut, after successfully completing the Tuning settings round trip.
It passes all six round trips on the repaired Release app. Early harness attempts
were corrected for cold startup and initial window restoration before this
red/green comparison. No route or safety assertion was removed.

## Additional verification

- Native Mac suite: 118 tests passed, zero failed/skipped. Parameterized device
  summary contains 198 invocations. Result: `build/release-readiness-20261101/mac-frequency-tests.xcresult`.
- Strict SwiftLint passed for both changed production Swift files.
- Final native Release product passed `Scripts/validate-native-mac-app.sh`.
- iOS Simulator app build passed with the existing iOS route preserved.
- Existing chart-test Environment warnings, duplicate Xcode resource-group warning,
  and intent API deprecation remain visible. These checks do not mean warning-free
  builds or full iOS release acceptance.

Local evidence is under `~/.jcode/scratch/hashfleet-mac-frequency/`:
`before-frequency.sample.txt`, `red-final.log`, `green.log`, and AX snapshots.
This targeted fix is not a claim that all remaining release checks are green.

## Recurrence confirmed November 6, 2026, 14:51 UTC

- The operator again identifies the trigger as clicking Frequency. This exact action, not a guided-tour success or idle monitoring interval, is the repair acceptance target. The original report also described a blank Frequency window, inability to switch to Advanced, and inability to edit the Easy frequency value. Those requirements must not be lost between investigations.
- macOS recorded a new hang from 14:51:09.912 to 14:51:19.462 UTC, duration 9.55 seconds, with 2.80 seconds sampled after seven seconds unresponsive. It names canonical PID 96754, UUID `A3E9BC1B-6186-3678-B064-5633D46151AD`, the same G binary handed back after commit `4a3dcc3`. All 28 main-thread samples share AppKit display/layout ancestry, 26 include NSHostingView layout; one sampled application branch constructs MinerDetailView toolbar content. A NavigationRequestObserver multiple-updates-per-frame warning occurs at 14:51:05.917271 UTC. This establishes a real remaining busy-main failure on the delivered build, not just an unresolved diagnostic warning. It does not prove that the sampled toolbar helper caused it. The process was already absent at the 14:52 inspection and was not relaunched.
- Original report preserved locally at `hashfleet-frequency-freeze-20261106T1451.noindex/original-frequency-click.hang`, SHA-256 `dff08a4c0477db1f51e4336dc9e31e131117e70bfe2caa6b2cdf9ca09ed00d0a`, with exact PID-scoped logs alongside. The one-hour watcher had ended normally at 14:22:50, about 28 minutes before the new hang. The OS report, not that expired observer, captured this failure.
- Earlier native smoke checks really did press both `detail.tuning.settings` and `detail.quick.tuning` from isolated demo parents. Those narrower passes do not override the new failure or establish the operator’s full failing state/sequence. Most other tests and the idle observer do not exercise the Frequency click. Prior overall fix claims were overstated.
- Current source retains different native entrances: the shortcut uses workspace-owned `FleetMinerSettingsRoute`, while the card gear still uses a destination-closure NavigationLink; the dashboard menu uses an item-bound destination. The workspace also adds its branding toolbar around a tuning page that defines its own principal item. These are concrete source differences to discriminate, not proven causes or permission to combine speculative patches. No new production patch or repeat broad suite was made during this review.
- The operator’s 13:23 noninterrupting-screen instruction remains in force. Inspection used stored diagnostics, source and read-only process/log commands only, with no new agents, live ASIC calls, GUI launch/focus/input, app replacement or production-state reset. Exact interactive red/green reproduction needs a separately approved short testing window. Do not silently replace that requirement with a passing off-window render or another tour run.

## Operator-controlled exact-click capture, November 6, 15:14 UTC

- The operator approved background-only capture and personally opened the canonical app and clicked Frequency. The first collector expired without detecting an app and collected no samples. The rearmed collector attached at 15:13:59 UTC to PID 42077, normal production arguments, the same G SHA-256 and UUID above. The operator confirmed the click at 15:14:48 UTC. No agent launch, activation, input, screenshot, app termination, state reset or hardware call was performed.
- Continuous five-second stack samples cover the transition, rather than waiting for a CPU heuristic. Sample 007 at 15:14:32 has idle main-thread observations; sample 008 spans the transition and the NavigationRequestObserver warning at 15:14:38.175679 UTC. Sample 009 has all 448 main observations under AppKit display/layout ancestry, with 431 through NSHostingView layout. Later samples retain that busy-layout shape and include both the parent MinerDetailView and the new MinerTuningEasyControls. This proves the Frequency destination starts constructing before the freeze. It does not identify the invalidating writer or prove a specific toolbar, geometry or input callback is responsible.
- A non-focusing AX windows query failed with error -25204 and probe exit 2. At 15:19 UTC the same process remained alive at 99.1% CPU. The collector stopped normally on its byte budget at 15:16:55 UTC after 175.38 seconds, 33 successful samples and 59,151,271 bytes, not a full three-minute run. Originals, per-file hashes, process manifest and PID-scoped warning log are preserved at `~/.jcode/scratch/hashfleet-frequency-operator-click-20261106T1513.noindex`. The app was left untouched. This is a reproduced failure, not a fix or passing acceptance result.
- Next bounded discriminator: the native workspace currently adds a principal FleetMacToolbarBrand around the tuning destination, while MinerTuningSessionView adds its own principal MinerNavigationTitle. Suppress only the wrapper's principal brand for the typed tuning route, retaining its leading artwork, environment and all non-tuning routes. This is a single candidate for matched operator-controlled red/green comparison, not an established cause. iOS, card gear routing, editor parsing and hardware-write paths stay unchanged. A compile or off-window render alone cannot accept the repair, and no app replacement or automatic GUI run is authorized by preparing the candidate.
- The one-change native Release candidate compiled successfully at 15:22 UTC in 110 seconds, with automatic package updates and code signing disabled. Unsigned candidate SHA-256 `5450aba4312479db72bf225813814e9963bf58d1c41b5824ce25779c583eb31b`, UUID `55E5667C-21FE-346B-8272-C7B40704EDC4`. This is build-only evidence, not an installed, signed or runtime-tested repair. The canonical installed G executable remains unchanged. The captured PID 42077 was absent at 15:23; the agent did not terminate it or relaunch the app. A matched operator-controlled test is still required.

## Candidate runtime failures and clean reset, November 6, 15:27–15:48 UTC

- The operator explicitly allowed a short foreground test at 15:25. Candidate `8529f5e` was signed and installed at 15:27, signed SHA-256 `829530b543666cc3ff1adb5787b2f8247c3adb7f0e1b73359ad98bc423ee314d`, UUID `55E5667C-21FE-346B-8272-C7B40704EDC4`. The agent opened the canonical app, selected Gamma 602 and pressed `detail.quick.tuning` at 15:29:10. A subsequent accessibility query failed. The operator reported that Frequency opened but Technical details then failed, so the later query failure cannot distinguish the two actions. The agent did not press Apply or send hardware settings.
- The operator took GUI control at 15:30. No subsequent agent GUI action, source change, restart or replacement occurred before the reset request. The first candidate collector preserved 21 samples, 34,430,981 bytes, and stopped after the process disappeared. A second operator-only retry preserved 10 samples, 16,364,515 bytes over 50.05 seconds and also ended on process exit or identity change. These are failures, not full three-minute acceptance runs.
- macOS reports both incidents as hangs, not proven crashes. The intact reports are preserved as `operator-technical-details.hang` under `~/.jcode/scratch/hashfleet-frequency-principal-check-20261106T1527.noindex` and `operator-other-menu.hang` under `~/.jcode/scratch/hashfleet-technical-operator-retry-20261106T1531.noindex`. Their originals are the 10:30:07 and 10:32:41 local-time reports in `/Library/Logs/DiagnosticReports`.
- A bounded read-only review at 15:47–15:48 found continued parent MinerDetailView/history/chart construction in both captures. The first OS report contains one custom-grid placement frame and one chart-mark frame. The grid measures and places children without an explicit state write; the parent width observer has threshold hysteresis. These observations do not identify an invalidating writer, establish a grid defect, or justify another speculative patch. The Technical details disclosure mounts payload, live-context, reference, ASIC and journal views. Source inspection alone cannot establish which action triggered the runtime loop.
- The operator's successful retry at 15:34 did not follow another agent code change and does not erase the earlier failures. Suppressing the extra principal brand has not been accepted as the repair.
- At 15:36 the operator authorized deleting the local app and settings for a clean build. See `MAC-CLEAN-RESET-2026-11-06.md` for exact deletion, fresh-build and installation receipts. The new canonical executable has SHA-256 `3f6cc8e68dcf188bb05b77dc7ce5bd6be3da2c69944e20da4532513c1e55b41b` and UUID `61C3E80F-D522-3045-B8B0-3682FCEAEB26`. It is freshly built from the existing candidate application source, not a new fix. It has not been launched or interactively tested. No collector is currently armed. Exact clean-state Frequency, Technical details, Advanced and Easy-input acceptance remains outstanding under the operator's GUI control.
