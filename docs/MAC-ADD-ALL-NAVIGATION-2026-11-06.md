# Add All → miner → menu freeze: six-review investigation

Started November 6, 2026, 16:27 UTC. This is an investigation receipt, not a repair acceptance.

## Operator's new sequence

The operator reports the fresh-state failure appears after **Add All → open a miner → press any button**. The impression that navigation does not know where to go is a hypothesis, not a verified cause. Do not restrict acceptance to Frequency entry or substitute a guided-tour run.

The operator explicitly requested six independent reviewers, superseding the earlier no-new-agent limit for this investigation. The operator retains screen control. No worker may launch/focus/resize/click, take screenshots, restart/install/terminate the app, call miners, spawn agents, build or edit production code. Root owns integration. Reports must distinguish evidence, inference and counterevidence.

## Actual clean recurrence capture

- Canonical app PID 73193, start November 6, 11:25:21 EST, SHA-256 `3f6cc8e68dcf188bb05b77dc7ce5bd6be3da2c69944e20da4532513c1e55b41b`, UUID `61C3E80F-D522-3045-B8B0-3682FCEAEB26`.
- Recorder attached 16:25:22.291 UTC and finished 16:28:24.751 UTC on its duration limit. Actual observation span 182.458 seconds, 34 successful samples, 59,208,646 bytes. No relaunch or app termination by the collector. Recorder is no longer active.
- Recorded CPU was 17.5% at 16:25:44 and 99.9% at 16:26:11, then approximately 99% with RSS rising to approximately 1.1 GB. The same process remained at 98.4% CPU at 16:28:47. Sampling adds overhead and is not a performance benchmark.
- PID-scoped log: 16:25:54.245929 UTC, `NavigationRequestObserver` multiple updates per frame. At 16:27:20.586494 UTC AppKit reports `layoutSubtreeIfNeeded` continued for 300 iterations because layout/constraints remained dirty, with future iterations artificially limited. This directly supports a repeated layout/constraint loop, not the identity of its writer or the Add All causality.
- Complete originals: `~/.jcode/scratch/hashfleet-clean-operator-walkthrough-20261106T1624.noindex`, including manifest, per-file hashes, continuous samples and `navigation-layout-log.ndjson`.

## Six original independent scopes and actual routing

The configured `agents.swarm_model = auto` high-effort approved pool was preserved. No global model/account switch or pool redesign was made. The local read-only preflight reported readiness/evidence gaps. Availability and persisted selection alone are not proof of successful inference. These are actual selected routes, not a claim that every provider's newest or globally highest-ranked model was used.

| Scope | Worker | Actual model/provider | Original report |
| --- | --- | --- | --- |
| Add All mutation, stores and task lifecycle | sabertooth | Gemini 3.8 Flash tiered / Antigravity | `hashfleet-addall-data-independent-20261106T1628.md` |
| Navigation/path ownership and registrations | microbe | GLM 5.3 Flash / NVIDIA NIM | `hashfleet-addall-navigation-independent-20261106T1628.md` |
| Captured stack transition and evidence limits | cactus | Sonnet 5.5 / native Anthropic OAuth | `hashfleet-addall-stack-independent-20261106T1628.md` |
| Relevant Git behavioral regressions | clover | Sonnet 5.5 / native Anthropic OAuth | `hashfleet-addall-history-independent-20261106T1628.md` |
| Observation/defaults/layout invalidation | mushroom | GPT-6 Astra / native OpenAI OAuth | `hashfleet-addall-invalidation-independent-20261106T1628.md` |
| Exact regression and acceptance checks | sunflower | Opus 4.8 / native Anthropic OAuth | `hashfleet-addall-acceptance-independent-20261106T1628.md` |

All original reports are under `~/.jcode/scratch/`. Missing, failed or incoherent reports must remain missing/failed, not counted as independent successful review. Integration is pending. No source patch is authorized by consensus alone without a concrete mechanism and a narrow falsifiable check. Prior candidate hangs and the three failed strict sidebar-dismiss warning gates remain failures.

## Partial integration, 16:41 UTC: five originals received, sixth recovering

Original data-lifecycle, stack, history, invalidation and acceptance reports have been read. Their appended corrections remain with the originals. No production source change, GUI interaction, new app launch, termination, or hardware call was made during this review.

The original navigation reviewer, microbe on NVIDIA NIM GLM 5.3 Flash, produced no assistant response, tool use or report in approximately twelve minutes. Its persisted transcript still contained only three user messages and had not changed since 16:28:34 UTC. Root stopped that stalled attempt at 16:40 UTC. This is an incomplete execution, not a successful independent review or proof of permanent model failure. The same sixth scope was recovered with an unpinned spawn through the configured approved automatic pool. Replacement hibiscus selected Gemini 3.8 Flash tiered / Antigravity. Its required original is `hashfleet-addall-navigation-independent-20261106T1640-recovery.md`. No provider pool/account changes were made, and no claim of six successful reports is made yet.

### Stronger findings from the original artifacts

- Sample 005 contains the continuous `addAllButton` → `addAllDiscovered` → `AddMinerMultiSelection.addAll` → `FleetStore.add` stack. Thus Add All is observed, not merely inferred from the collector filename.
- Sample 006 contains a sidebar row mouse-down, the first miner-detail frames and the 16:25:54.245929 UTC navigation observer fault. Tuning content first appears in sample 008. The exact later button and its timing remain unrecorded.
- By sample 009, starting approximately 16:26:06 UTC, main-thread observations are almost entirely inside AppKit layout and SwiftUI rendering. The stack review found no event-source servicing in samples 009–034. This explains unresponsive buttons without proving that each button independently starts the freeze.
- The fault backtrace has only one application-image frame. With the matching UUID dSYM it resolves to `main`, not an app-level navigation writer. The 300-iteration warning has only an AppKit frame. More symbolication of those same records cannot identify the initiating app write.
- Sampled detail, history and chart bodies identify repeatedly evaluated work, not the invalidating writer. Other threads are predominantly idle. The earlier menu failures show the same saturated shape on a different binary.

### Source-backed candidates and counterevidence

1. Add All uniquely combines `dismiss()` with a synchronous `FleetSystemNavigation.request()` publication. The receiver resets the path/sidebar and calls the main-window-opening helper. This is a concrete navigation-ownership asymmetry worth isolating, but neither the request nor its receiver is observed executing in the captured Add All stack. The navigation warning occurs after detail construction begins. Direct causality remains unproven.
2. Shared native stack identity, toolbar updates and detail layout are plausible convergence boundaries. The window-frame warning does not prove a toolbar/principal-item initiator. The previous principal-brand candidate did not reliably fix the menus.
3. Real fleet publication can invalidate ancestors despite per-miner snapshot cells: the notification layer reads `reconnectingDeviceIDs`, which reads whole-fleet snapshots. Shared connection/capability collections add fanout. However, live publication is coalesced, monitoring identity is stable and inspected tasks are bounded. This is a plausible amplifier, not a demonstrated unbounded writer.
4. The explicit width-to-State edge has threshold quantization and 16-point hysteresis. There is no measured alternating-width evidence. The custom grid has no observed-state write, and native chart-height writeback was already removed. Do not declare either causal merely from body/layout frames.
5. Add All keeps the same store instance and creates stable UUIDs. Discovery has cancellation on disappearance and is disabled while scanning. N persistence writes are finite, not evidence of a sustained defaults loop.

One precise constructor gap in the invalidation report was resolved by root: `Shared/FleetGlance.swift:263–302` defines `FleetMenuBarPreferenceStorage`; its initializer only assigns `self.defaults`. Writes occur in explicit save methods, not construction. This specific per-access constructor is not an unconditional defaults writer.

### Test-gap findings and rejected overclaims

The native smoke uses demo state and presses tuning entrances, not the real non-demo post-Add-All workflow. It does not toggle Easy/Advanced, expand Technical details, edit Easy input, or traverse the other detail destinations. Pure bulk-add tests and window-less hosted graphs do not cover native window convergence. Passing those tests never established acceptance of the operator's workflow.

The lifecycle report originally claimed a definitive navigation collision and cause. Its author explicitly retracted that wording in section 7. Source overlap remains a hypothesis, not a finding. The acceptance report originally proposed uncalibrated numeric gates and a decisive off-window probe. Its section 7 corrects both: the proposed numbers are advisory, and a window-less graph cannot certify the NSThemeFrame path. No numeric or off-window pass is accepted as repair evidence.

Quick identify/pause/resume/restart buttons open review forms. Confirm/apply must never be pressed against real hardware under this investigation. Remove is also a local state mutation, not part of read-only acceptance. Future automation should use mocked endpoints and still exercise the real native window; it must not substitute demo-only or an idle/tour check for the failing workflow.

Pending the sixth original, the narrowest proposed comparison is the same fleet populated through individual discovered-row adds versus Add All, then the same miner destination and control, with timestamped navigation/identity/width traces. That experiment is not run or authorized by this document. No further screen interruption is permitted without the operator's explicit testing window.

## Six-review integration complete, 16:51 UTC

The sixth original scope was completed by hibiscus and root read the recovery report and its section 7 corrections. Its source map confirms the additional Add All completion transition, stack/split identity resets and both view-destination and value-destination links. It does not identify the runtime writer.

Root rejected the original report's causal wording and its suggestion that a failed request-removal experiment would confirm mixed links as the cause. The reviewer appended corrections: timestamps establish ordering only, mixed links are not thereby proven illegal, and persistence after removing the request leaves numerous alternatives. Root does not adopt those original causal claims. The `...navigation-independent-20261106T1628.md` file was written as an extra recovery copy by hibiscus, not an original from microbe, and lacks the later corrections. Use the `...1640-recovery.md` original with its section 7 instead.

All six required independent scopes now have original reports that root has read. The failed/stalled first navigation attempt remains recorded, not counted as a seventh successful review. All review workers have been explicitly stopped. The resulting decision is **no proven initiating writer and no accepted repair**. Add All's overlapping completion ownership is the most concrete narrow discriminator, not a consensus-proven cause or a reason for a broad navigation rewrite.

## Diagnostic-only follow-through, 16:56 UTC

Root prepared opt-in writer tracing in source, without installing or launching an app:

- Flag: `--trace-fleet-navigation`, off by default. Unified-log subsystem `app.hashfleet.mac`, category `NavigationTrace`, marker `HF_NAV_TRACE`.
- Native navigation state setters record old/new sidebar values or path counts and up to 24 compact return addresses. Match the exact diagnostic binary UUID and dSYM before symbolication. Path counts do not encode route identity, and addresses may include framework frames.
- Existing Add All boundaries record begin, dismissal, request and completion. Native request receiver/consume, root reset callbacks and measured/settled detail width record their existing execution. No navigation operation was removed, delayed or reordered.
- Budget: 256 admitted events, at most one additional writer-stack record per event, then one explicit exhaustion notice. Later absence after exhaustion is never evidence of no writes. Detail values are lazy and not evaluated when disabled or dropped. No miner names, addresses, credentials or payloads are logged by these hooks.
- The trace has no View/Observable storage, defaults writes, timers, file collector or hardware calls. Diagnostic logging and stack capture still add overhead and can perturb timing. This is not a performance benchmark or universal invalidation detector. It does not intercept internal framework writers or every observable property.

Standalone verifier: `Scripts/tests/NativeMacNavigationTraceProbe.swift`, compiled together with the actual `MacApp/FleetMacNavigationState.swift` under Swift 6 strict concurrency. It substitutes a minimal sidebar enum solely to compile that state owner, creates no NSApplication/NSWindow and never contacts a miner.

Executed after the last source edit:

1. Production trace/state compilation passed after correcting an initial compiler-detected escaping-autoclosure lifetime error. The failed first compile is retained as task `117055j8km`, not described as a pass.
2. Default-off run passed: opt-in matching, lazy details not evaluated, finite budget with one exhaustion, zero/negative budgets and path/select semantics.
3. Opt-in run passed the same checks with detail evaluation enabled.
4. The five remaining changed call-site files passed `swiftc -parse`; `git diff --check` passed.

The verifier is a CLI under `~/.jcode/scratch/hashfleet-writer-trace-verify-20261106T1655.noindex`, not an app bundle. At this 16:56 checkpoint the full native application had not yet been rebuilt or installed with these hooks. The later compile receipt follows below. The canonical installation remains the earlier clean binary. No GUI or exact Add All regression was run in this follow-through, and none of these diagnostic checks closes the defect.

Next execution requires a separately authorized testing window and diagnostic app launch, with a short timestamped Add All/individual-add comparison. Preserve the same native window, control and fleet population between arms, and never confirm hardware commands. Capture these writer records alongside the first observer fault and first saturated sample. A trace that stays stable before starvation demotes these explicit writers but does not prove a framework-only cause. No hour-long idle run is proposed.

## Full native diagnostic compile verified, 17:03 UTC

The complete native Release target for source commit `8a97752` compiled successfully on arm64 in 117.7 seconds, task `329037dcaa`, with code signing disabled. This type-checked the actual native call sites and trace implementation together, beyond the earlier standalone verifier and syntax parse. Existing pinned package checkouts were reused without package updates. No app was installed or launched.

- Generated executable SHA-256: `e3449542a8ba8aff292a89e3f4fbcdc600ca5e610fb51023cb99de67ed8f0345`.
- Matching executable and retained dSYM UUID: `592D165C-DB8C-3611-B17F-730F75CFED8A`.
- Build log, unbundled diagnostic executable, dSYM and `verification-receipt.json` are preserved under `~/.jcode/scratch/hashfleet-writer-trace-build-20261106T1658.noindex`.
- Xcode registered its generated staging bundle. Root successfully unregistered only that exact staging path, then deleted only the newly generated `.app` after preserving its executable and symbols. The generated bundle is verified absent; the dSYM remains.
- Canonical `/Applications/Hash Fleet.app` SHA-256 remains `3f6cc8e68dcf188bb05b77dc7ce5bd6be3da2c69944e20da4532513c1e55b41b`. Settings and the operator screen were not touched. No package resolution file changed.

Diagnostic preparation and non-GUI verification are complete. **The freeze is not fixed or accepted.** Three prior strict Settings sidebar-warning gates remain failed. The next useful step is a separately authorized brief native-window test with the operator retaining control, not another idle watcher or another review swarm. No automatic recording, install or launch is armed.

## Native completion ownership correction, 17:46 UTC

At 17:34 the operator directed root to continue fixing the app rather than stop at diagnostic preparation. Root corrected its overly broad interpretation of the screen restriction: code changes and non-GUI checks remain authorized. The restriction still prevents silently replacing/restarting the operator app or taking screen control.

The candidate changes one mechanism: native Add All completion no longer executes both child `dismiss()` and the external `FleetSystemNavigation.request()` path. On macOS it calls `AddMinerMultiSelection.completeInWorkspace`, which selects exactly one completion owner. Dashboard clears its own Add Miner binding. Split workspace clears its Add Miner binding and nonempty path and selects Overview if necessary, preserving return-to-fleet behavior without the system request, window reopening or UUID reset. A standalone presentation without a workspace callback dismisses once. iOS retains its previous dismiss-then-request path. Bulk add, naming, partial failures, discovery, manual adds, external Open Fleet intents and hardware-write paths are unchanged.

This removes a confirmed source-level competing-completion pattern. **It is not proof that this pattern initiated the recorded hang or that the candidate cures every menu freeze.** Earlier failures without Add All remain counterevidence to any universal claim.

### Executed checks

- `Scripts/tests/test_native_add_miner_completion.py` runs the same four source-contract checks against baseline `08176db` and the candidate. Baseline fails the two native ownership checks and passes the unchanged iOS/error contracts. Candidate passes all four. These are explicitly structural source-contract checks, not native interaction tests. Original before/after logs are preserved.
- `Scripts/tests/NativeMacAddMinerCompletionProbe.swift` was compiled with the actual production `MinerDiscovery.swift` and `AddMinerMultiSelection.swift` and existing pinned HashFleetCore/GRDB objects under Swift 6 strict concurrency. The application FleetError declaration was copied verbatim from `FleetStore+Totals.swift` into scratch and equality-verified before compilation. No production state/store or error semantics were substituted. The executable checks mutually exclusive workspace/dismiss callbacks, ordering, custom-name use, duplicate handling, already-added no-op, partial failure, retry and empty input. All checks passed. It creates no NSApplication, NSWindow, network scan or hardware request.
- Initial standalone probe builds exposed three harness dependency omissions: GRDBSQLite module search path, the app-local FleetError declaration and the profile runtime required by existing package objects. These failures remain in tasks `823428vbuh`, `908319fzd5` and `032781x2wd`. They were corrected without changing assertions. Final task `079299trah` passed; profile output stays in scratch.
- The complete native arm64 Release app compiled successfully in 121.2 seconds, task `943464f7nu`, using two build jobs and no package updates, signing, install or launch. All four production call sites were type-checked together. The two new app-hosted unit tests were syntax-parsed, not executed by launching a test app. Their callback assertions were separately executed by the CLI probe.
- Candidate executable SHA-256 `fd487f8101b464e2a2e978e5733755c8e841a46eebb52cd163b59ba38c9465e4`, matching executable/dSYM UUID `3A081EB1-AE47-31AC-A4A0-0C7D8758B334`. Original logs, exact error declaration, CLI probe, candidate executable and dSYM remain under `~/.jcode/scratch/hashfleet-completion-repair-20261106T1740.noindex`.
- Only the exact generated candidate app was unregistered from LaunchServices and removed after preserving its executable and symbols. Canonical SHA remains `3f6cc8e68dcf188bb05b77dc7ce5bd6be3da2c69944e20da4532513c1e55b41b`. No settings or screen actions occurred. `git diff --check` passed.

### Remaining outcome check

At this 17:46 checkpoint the candidate was not installed or interactively accepted. Exact Add All → miner → Frequency, Technical details, Advanced/Easy and other destinations still need the real native-window check with timestamps, no hardware confirmations and the operator retaining control. The individual-add comparison remains useful if recurrence persists. Neither this compile, the source-contract red/green nor the CLI assertions replace that outcome check. Three prior strict Settings sidebar-warning gates remain failed.

## Authorized replacement and operator-controlled capture, 18:12 UTC

The operator explicitly approved replacement at 18:07:07 UTC. The canonical app was not running before installation. Root reconstructed the existing verified candidate, confirmed its unsigned SHA against the earlier receipt, preserved the current CLI byte-for-byte and signed with the existing identity and native sandbox entitlements. The transactional installer replaced only `/Applications/Hash Fleet.app`; native and deep/strict signature validation passed. Settings and saved miners were not cleared.

- Installed source `9b49cde`, signed executable SHA-256 `b16e93e6c33c88feeb687ab4e6da0fe90f1bf5d65fe876b37f7a1a09044fbf82`, UUID `3A081EB1-AE47-31AC-A4A0-0C7D8758B334`, matching retained dSYM.
- Bundled CLI remains SHA-256 `0b87d0f2e29ff81b5dc7babf9f5c17f201dfb377a8f7f8d012830f772dae274a` with its canonical symlink. The installer deleted its validated superseded app rollback. Root removed only the exact generated staging bundle and redundant CLI backup symlink after verification, unregistered that staging path and refreshed only the canonical registration. The administrator-only legacy Trash copy was not touched.
- Root opened the canonical app with `open -g` and `--trace-fleet-navigation`. Root did not click or navigate any app button. Candidate-bound recorder attached at 18:11:02.307 UTC to PID 35675 after verifying exact signed SHA and trace flag.
- Capture task `650464o9t6`, originals `~/.jcode/scratch/hashfleet-owner-operator-20261106T1811.noindex`. Maximum sampling span 180 seconds, five-second samples at ten-millisecond interval, total sample ceiling 64 MiB, per-file ceiling 8 MiB. Notice-level navigation-writer and layout records are collected for that PID at the end. A duration/byte/identity exit must be reported accurately. Sampling overhead is not a performance benchmark.
- Root told the operator recording was active and left Add All, miner selection and the failing controls entirely to the operator. Do not press Apply or confirm a device command. If Add All is unavailable with the preserved fleet, other menu observations cannot be called an Add All regression pass.

Install receipt: `~/.jcode/scratch/hashfleet-completion-repair-20261106T1740.noindex/install-receipt.json`. At the installation checkpoint, capture and operator result were pending. **Installed is not fixed or accepted.** No automatic relaunch or capture rearm is authorized.

## Bounded operator capture completed, 18:16 UTC

Task `650464o9t6` exited successfully. The attached collection ran from 18:11:02.307 UTC to 18:14:04.999 UTC, an actual 182.690 seconds. Its final five-second sample crossed the nominal 180-second boundary. Completion reason was `capture-duration-limit`, not an app crash or byte-budget stop. All 34 original sample sizes and SHA-256 hashes were independently checked against `events.jsonl`, with no mismatches: 50,286,909 bytes, below the 64 MiB ceiling. The collector left the app untouched. This records identity throughout the captured span, not a fresh post-capture liveness check.

The PID-scoped persisted-log query completed at 18:14:06.848 UTC with exit 0. The result is exactly `{"count":0,"finished":1}`, SHA-256 `6a105b91d25933f6c54289af691d9c991a86c63c340ca13a472b5a44aa88c346`. Thus it returned neither the requested writer events nor matching layout-warning records. This is not affirmative proof that no navigation writes occurred, or that logging instrumentation was exercised. No trace-based attribution can be made from this empty result.

Bounded inspection of samples 1, 6, 12, 24 and 34 found no `MinerDetailView`, `addAllDiscovered`, `FleetStore.add` or `MinerTuningSessionView` symbol in those inspected files. Samples 12 and 24 include event-source processing on the main thread rather than the earlier uninterrupted starvation shape. Sampling can miss short-lived calls, so these observations do not establish which controls were used or prove responsiveness. No operator click/result report has yet been received for this recording. **Collection passed, exact Add All/menu acceptance remains unverified, and the freeze task remains open.** Three prior strict Settings sidebar-warning gates remain failed. Recording has stopped and was not rearmed. No GUI, restart or hardware action was taken during this review.

At 18:17 UTC a follow-up search across all 34 saved samples likewise found none of those four application symbols. CPU values recorded before samples ranged from 50.9 to 79.1 percent, and RSS from 179,280 to 373,408 KiB. Diagnostic sampling overhead means these are not performance acceptance measurements. The production logger's subsystem, category and opt-in flag match the collector predicate and captured arguments. This excludes a simple source-level filter spelling mismatch, but does not establish delivery of trace messages or execution of instrumented actions. No additional recording, screen action or app restart was attempted. Exact workflow acceptance depends on the operator's actual action/result report or a separately authorized bounded interaction test; it cannot be inferred from these saved files.

## Candidate recurrence and history analysis, 18:29 UTC

The operator requested recording again at 18:21:42 UTC. The same unchanged recorder attached at 18:21:59.526 UTC to the same installed candidate, PID 35675. Task `31940144pq` stopped at 18:22:54.125 UTC after 54.599 seconds with `app-exited-or-identity-changed`, not its duration or byte ceiling. All 11 sample hashes verified; total 19,873,142 bytes. The collector did not terminate or relaunch the app, and a subsequent read-only `ps` found no PID 35675. The reason for process exit is not established.

This time persisted writer records were actually returned. Their exact timeline, converted from the log's -0500 offset to UTC:

| UTC | Observed event |
| --- | --- |
| 18:22:11.732223 | Native path count 0 to 1 |
| 18:22:11.878941 | Detail width previous 0, measured/settled 1748 |
| 18:22:12.348467 | NavigationRequestObserver multiple-updates-per-frame warning |
| 18:22:16.562242 | Native path count 1 to 2 |
| 18:22:16.659 | OS hang report's unresponsive interval begins |
| 18:22:53.929 | OS hang interval ends |

Writer stacks matched to the installed UUID and retained dSYM resolve to the trace helper, Observation-generated path setter and SwiftUI key-path setter, not an Add All completion or explicit workspace reset callback. There are two path event records, two corresponding stack records, one width event and the observer warning. No trace exhaustion, Add All, sidebar activation, external reset or system navigation request is recorded during this capture. This demotes repeated writes through those particular instrumented reset paths for this recurrence. It does not exclude a prior Add All effect, uninstrumented state, framework navigation reconciliation or missed log delivery.

Sample 3 contains miner detail construction. Sample 4 includes tuning-view copy/initialization and substantial display/layout work. From sample 5 onward the main-thread display/layout branch dominates again, while other threads can still be idle. CPU reaches approximately 98 to 100 percent and RSS rises to 686,400 KiB before exit. These are supporting diagnostic observations, not performance benchmarks or proof that Charts or a particular body getter causes the loop. The exact button label is still not established by path counts or a destination's initialization alone.

The fresh OS report independently confirms a **hang**, PID 35675, canonical executable, duration 37.27 seconds, from 18:22:16.659 to 18:22:53.929 UTC. Original preserved as `operator-menu-recurrence.hang` beside the recorder artifacts under `~/.jcode/scratch/hashfleet-owner-operator-20261106T1822.noindex`. It reports all 11 sampled main-thread observations under the display/layout ancestry. An app exit following a hang report is not by itself a proven crash or proof of who ended the process.

### Relevant git boundaries, not a proven first-bad commit

- `c092100` on November 1 is the last documented passing *specific demo workflow*: both tuning entrances from dashboard and sidebar. It is not a known-good control for the operator's later live, post-discovery fleet. Its workaround used a destination-closure native Frequency link.
- `25b1087` on November 6 at 07:46 UTC replaced the Mac Frequency and Miner settings links with typed `FleetMinerSettingsRoute` values registered by the split workspace. iOS branches stayed distinct. This directly changes the implicated native push boundary and is a useful matched-comparison candidate, not a demonstrated first-bad revision.
- `4a3dcc3` at 13:13 UTC added environment-controlled `AnyView` decoration around native navigation titles and destination registrations to isolate guided previews. Ordinary Mac navigation uses the decorated branch. Earlier hangs predate this commit, so it cannot explain every historical failure, though it remains a possible contributor to the current route behavior.
- `8529f5e` removed the typed tuning destination's extra principal brand. The captured failure after that change rules out that single suppression as a sufficient fix. It does not prove all toolbar involvement absent.
- `9b49cde` made Add All completion choose one workspace owner. This latest recorded failure means that change is **insufficient to resolve the menu freeze**. Do not deploy it as an accepted fix or keep attributing this recurrence to a repeated Add All broadcast without evidence.

The next decisive comparison is a short, same-state native-window route test, varying one implicated boundary while retaining real-window layout and safe mocked endpoints. A source diff, off-window render, demo-only pass, arbitrary layout-iteration threshold or another long idle capture cannot locate the first-bad commit. No mass rollback, new speculative production patch, new review swarm or Mac GUI automation was performed during this analysis. The operator separately requested a current-source build/install on the paired physical iPhone; that delivery is tracked independently and is not Mac acceptance.

## Requested physical iPhone delivery verified, 18:33 UTC

The current application source was built with the standard `HashFleet` scheme, `Debug`, for the paired physical iPhone 14 Pro Max. Source checkout at build start was `7dfba1d`, with production application change `9b49cde`; intervening commits were documentation only. An explicit scoped git diff confirmed no application source drift during this build. Existing Apple Development signing/team and pinned dependencies were used; no package versions, entitlements, project settings or user data were changed. The full iPhoneOS build succeeded in 151.3 seconds, task `6262939ndp`. The first invocation had rejected a misspelled Xcode package-cache option before compiling; its log remains preserved.

Deep/strict signature verification passed. `devicectl` installed `app.hashfleet`, version 0.1.0 build 12, and an independent installed-app inventory confirmed that identity on the phone. Launch then succeeded without diagnostic/demo arguments or terminate-existing behavior. A later independent process listing confirmed the same launched PID 15437. The first process-query filter raised a devicectl predicate exception, not an app crash; an unfiltered query recovered the check without restarting the app. No app buttons were pressed, settings reset, uninstall or miner write performed. No Mac app was relaunched or screen control taken.

Receipt and original build/install/launch/query outputs are under `~/.jcode/scratch/hashfleet-phone-current-20261106T1826.noindex/delivery-receipt.json`. Exact executable and debug dylib were preserved unbundled and hash-verified before removing only this run's generated iPhone and Watch staging `.app` bundles. Their UUIDs are `D1D7EB89-5904-362B-9EB3-EB044C96A846` and `DF5817CB-68A2-3186-9FB8-2089E527149F`, respectively. The installed phone app and canonical Mac app were not removed. A final staging inventory found no remaining top-level generated `.app` products in this run's build-products directory.

**Phone build, installation and initial process launch are verified. Phone button-flow regression testing is not.** Frequency input, Advanced/Easy switching, Technical details and the remaining menu paths have not been interactively exercised on the phone. This delivery does not clear the native Mac hang or establish that iOS has no regressions.

## Root cause found and fixed, 19:00 UTC (commit `6295a7b`)

The operator authorized brief Mac control at 18:38 UTC. A bounded accessibility sweep of every non-hardware miner-page control on the live fleet reproduced the freeze deterministically at 18:42 UTC: **Raw API** left the app at about 100% CPU with no accessibility response. The same failure reproduced in an isolated `--ui-testing --demo` instance, enabling fast red/green builds with no miner contact.

Rejected candidates, all still red: moving the endpoint page's navigation modifiers outside its `TimelineView`; removing its confirmation destination on Mac; and reducing that page to a single plain text row inside the settings form or a plain `ScrollView`. Only an empty `Text` page passed. This ruled out the endpoint page's own content as the cause.

`Self._printChanges()` instrumentation, temporary and since removed, settled it. After one Raw API press, the log showed **446× `MinerDetailView: _dismiss changed.`** and **441× `MinerEndpointView: @self changed.`** The parent miner page read `@Environment(\.dismiss)`. Pushing a scrollable child changes that environment value, which re-rendered the whole miner page (charts, grids and links). That re-render produced a fresh child, which changed `dismiss` again. The result was a render loop on the main thread. This also explains the earlier recurring stacks dominated by `MinerDetailView` and chart frames under AppKit layout, and why the failure followed a push from the miner page rather than any one destination.

Fix: `MinerDetailView` no longer reads `dismiss`. Its only use, Remove from fleet, is now a small `MinerRemoveFromFleetButton` leaf view that owns the dependency. No navigation, tuning, write gate, iOS path or hardware behavior changed.

### Verification (all read-only, no Apply, identify, pause, resume, restart or remove pressed)

- Same _printChanges harness after the fix: zero invalidations after the Raw API press.
- Isolated demo, fixed build: all 13 pushed miner tools, each twice; all 5 in-place disclosures, each twice; Frequency → Technical details open/close → Advanced → Easy → Back from both sidebar and dashboard entries; the existing six-round-trip tuning smoke and full `--sidebar` route suite. All passed.
- Installed signed canonical app, same Apple Development identity and sandbox entitlements, CLI bytes preserved. Executable SHA-256 `2500a4fb64ee675e3d0a2e033549b00367b92e2322cbc00e5e4e2f6d1e7573cf`, UUID `087B5A97-03DB-3174-9A74-B377BAB6C1AF` with retained dSYM. Settings were not cleared.
- Live saved fleet on the installed app: all 13 tools, including Raw API twice, responded on the Naja Duo. A second miner also passed.
- **Exact operator workflow from clean state** on the installed binary, using the app's isolated UI-test storage, which starts empty and never touches the saved fleet: Add miner → allow local network → Scan → **Add all (4)** → every miner alternately via dashboard card and sidebar → all 13 pushed tools, Frequency's Technical details, Advanced and Easy, and all 5 disclosures. **193/193 checks passed, zero retries**, at 20:16 UTC. The previous run's single failure at 20:00 was a transient empty-window snapshot and is preserved. That run showed no stuck main thread and recovered within its retry window. Its harness now retries a missing control for 12 seconds and records attempts.
- Idle CPU with four live miners streaming stayed at about 45 to 70% in diagnostic conditions. This is live telemetry and chart rendering, not the 100% stuck loop. It is a separate performance observation, not a freeze.

Not covered: real pointer clicks rather than accessibility presses, writes or confirmations of any kind, and the three earlier strict sidebar-warning gates. Evidence is under `~/.jcode/scratch/hashfleet-ab-20261106T1839.noindex`.
- Phone: the fixed source `6295a7b` was rebuilt for the paired iPhone 14 Pro Max, passed deep/strict signature verification, was installed via devicectl and launched successfully at 20:18 UTC. Phone button flows were not driven by automation.

## Idle CPU reduction, 21:01 UTC (commit `7dfc238`)

With four live miners the installed app idled at about 57% CPU on a miner page and 50 to 61% on Overview, versus about 15% on About. Samples showed CPU-side drawing (`CGDrawingLayer.draw`, `vSepConvolve` blur) plus full graph updates. A SwiftUI Instruments trace showed about 97 transactions per second and roughly 10,000 `InterpolatedDisplayList<ResolvedStyledText>` updates per second. Those are animated text transitions.

Launch-flag A/B in isolated `--ui-testing` storage, after a real scan and Add all (4), with medians over 30 seconds:

| Variant | Overview | Miner page |
| --- | --- | --- |
| Unchanged | 50.0% | 57.3% |
| Live badge pulse off | 63.0% | 48.3% |
| Numeric digit transitions off | 35.6% | 19.7% |

The forever-pulsing Live badge was not the cost. The rolling `numericText` transitions on every label, republished each second by live telemetry, were. Fix: on native Mac, `fleetNumericUpdate` updates in place (`FleetNumericMotionPolicy`). iOS keeps rolling digits. The temporary diagnostic flags were reverted.

Verification:
- Native Mac test `FleetNativeNumericMotionTests` plus the navigation test passed.
- Two Release live runs: Overview 44.4% and 38.4%, miner page 22.4% and 26.8%.
- Installed with the same identity and entitlements, CLI bytes identical, settings kept. UUID `792344BD-90C8-3778-9BC6-F54FB31900DF`, SHA-256 `f6c9e436…68430`, dSYM retained as `fix-7dfc238.dSYM`.
- The exact clean flow passed on the installed build: scan → Add all (4) → every miner and control. **193/193 checks passed, 0 retries, PASSED, exit 0.** Its exit code now really reports failure. The run took 578 s against 917 s before.
- The phone was rebuilt at `7dfc238`, installed and launched.

Overview still idles at about 40%, so further reduction is possible: charts and the 30 fps ticker. This change is not a final performance baseline.

## Further idle CPU optimization, 22:00 to 23:00 UTC (commits `a3eefb8`, `90c4de8`)

The operator asked for lower resource use. The metric is now cumulative process CPU seconds over 45-second windows, instead of decaying `ps %cpu`. That earlier metric gave 28% and 40% for the same Overview build. Every run uses isolated `--ui-testing` storage after a real scan and Add all (4), on a fresh launch.

The kill-switch matrix used temporary launch flags, all reverted. Baseline at `7dfc238`: Overview 46%, miner page 25%, About 17%.

| Switch | Overview | Miner | About | Conclusion |
| --- | --- | --- | --- | --- |
| History chart hidden | 42 | 25 | 16 | Not the cost |
| Miner cards hidden | **21** | 24 | 17 | Cards are most of the Overview cost |
| Snapshot cache and block/best-share persistence off | 46 | 24 | 18 | Not the cost |
| Live publish every 5 s | 35 | **9** | **5** | Per-second publishing drives the miner and background cost |
| Fleet artwork animation off | 45 | 22 | 15 | Not the cost |

Fixes, both Mac-only:

1. `a3eefb8` merges all miners' live frames into **one fleet-wide publish per second**. Before, each miner published on its own unaligned schedule, giving four render passes per second. Final frames still flush when a socket closes, and cancellation clears pending work. Result: Overview 39%, miner 14%, About 6%.
2. `90c4de8` keeps the **Live badge steady** instead of a forever `phaseAnimator` on every card. That animation redrew each card at display rate. A real online/offline change still pulses once. iOS keeps the breathing badge. Result over two runs: **Overview 9.3% to 10.5%, miner page 13.2% to 13.7%, About 5.3% to 5.4%.**

Total since the morning: Overview about 60% to about 10%, miner page about 57% to about 13%, background about 15% to about 5%. Readings still update every second.

Verification:
- Full native Mac suite: 151 tests in 32 suites passed.
- iOS device build passed. Installed and launched on the iPhone.
- Mac app installed with the same identity and entitlements, CLI identical, settings kept. UUID `1F1DA2D5-9DBB-3863-BBA1-9F9EC986B829`, SHA-256 `b27caecc…53a968`. dSYM retained as `fix-90c4de8.dSYM`.
- Exact clean flow on the installed optimized build: scan → Add all (4) → every miner and control. **193/193 checks passed, 0 retries, PASSED, exit 0** (23:10 UTC).
