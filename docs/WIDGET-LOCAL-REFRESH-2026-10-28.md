# Explicit local widget refresh, 2026-10-28

## Scope and outcome

This change adds an optional, explicit **Refresh fleet** action to the small, medium and large iOS widgets. It is not continuous monitoring, a remote refresh service, a hardware-control action or a promise about WidgetKit scheduling.

Ordinary widget sharing remains aggregate-only. A separate **Allow widget refresh** preference is off by default. Only an opted-in foreground app can prepare the minimal local connection metadata needed by the bundled widget extension. The timeline provider still reads saved files only. Accessory widgets remain links to the app.

No real fleet requests, SSH sessions, miner writes, restarts, firmware operations, pool or power changes, production installation, APNs/server changes, account changes, App Store submission or deployment were performed for this work. All network-shaped validation used injected readings or private `URLProtocol` fixtures. Installed UI checks used the dedicated test simulator and synthetic data.

## Enablement and privacy contract

1. In the app, connect to the real fleet in the foreground and permit Local Network access if requested.
2. Enable ordinary widget sharing in Monitoring settings.
3. Separately enable **Allow widget refresh**. Preparation in the foreground requires a recent complete observation for every supported miner. The settings status explains whether preparation succeeded.
4. Use the refresh arrow on a system-sized widget while on the miners' local network. The intent declares local-device authentication.

Supported preparation is deliberately narrow: 1–16 credential-free ESP-Miner ASICs, canonical literal RFC1918 IPv4 HTTP(S) root URLs, unique device IDs, endpoints and MAC pins. Hostnames, public or ambiguous addresses, URL credentials, paths, query strings, fragments, XMRig devices, conflicting or malformed MAC aliases, incomplete, cached, reconnecting and stale observations are rejected. A changed address, kind, credential binding or Demo transition invalidates older identity observations, including address and Demo ABA round trips.

The separate state contains only a versioned target list (`id`, `baseURL`, `expectedMAC`), generation and permission dates, transactional lease/cooldown, fixed outcome codes and an optional complete fleet aggregate. It does not include device names, user credentials, wallet addresses, raw firmware replies or raw network error descriptions. MAC comparison prevents accidental target substitution but is not cryptographic authentication against a malicious LAN peer.

Permission lasts up to 24 hours from preparation or renewal. An unchanged valid foreground fleet can renew it at most hourly, without rotating its generation or writing at live-frame cadence. Background updates cannot prepare or renew permission, but still invalidate unsafe metadata and revoke on Demo or consent changes. Expiry disables new reads without discarding the newest valid saved aggregate. Turning ordinary sharing off also resets the separate opt-in and removes refresh metadata. A failed filesystem revocation is surfaced as an error, not falsely reported as successfully off. If removal fails, the earlier on-disk permission may remain until a successful retry or expiry.

## Execution and persistence

- `RefreshFleetWidgetIntent` is parameterless, not discoverable and does not open the app when run. It declares `.requiresLocalDeviceAuthentication` and awaits the same runner path exercised by integration tests before returning.
- Each explicit attempt reuses the existing production `FleetScheduledCheckReader`: only `GET /api/system/info`, no redirects, no retry, no credential or cookie storage, no URL cache or proxy, and a bounded 131,072-byte streamed reply. The existing transport uses 8-second request and 12-second resource limits.
- At most 16 targets are attempted with at most 4 concurrent reads. A structured, cooperative 10-second attempt deadline cancels outstanding work. This is not a hard promise about total operating-system or uncooperative-reader execution time.
- Every target must supply finite nonnegative hashrate and power. True zero is valid. Any failed, partial, invalid or cancelled target prevents a replacement aggregate. Offline miners are not silently dropped and missing telemetry is not invented.
- A successful aggregate retains the earliest request-start observation time. Failed attempts preserve the last reading and its timestamp. Provider rendering and timeline creation never relabel saved observations as new measurements.
- One atomic JSON state file is capped at 65,536 bytes. Reads fetch at most cap plus one byte before decoding. State is owner-only, excluded from backup and uses iOS protection until first user authentication. No new unchecked-Sendable annotation was introduced.
- App and extension serialize short file transactions with a fixed, never-deleted lock inode, opened using Darwin `O_EXLOCK | O_NONBLOCK | O_NOFOLLOW | O_CLOEXEC`. Acquisition retries for at most approximately 25 ms, then declines rather than blocking indefinitely behind a suspended process. Network work never holds this lock.
- A lease and cooldown are persisted before any read. A late completion must match both the random configuration generation and lease ID. Revocation, reconfiguration, expiry, cancellation and revoke/re-enable with identical targets cannot recreate removed state or accept an older completion. Lease/cooldown duration is 15 seconds.
- The legacy six-field `FleetGlance` definition and its existing store are unchanged. The provider selects a newer valid refresh observation only for a compatible real inventory, never over a newer app observation or Demo. An inventory-count mismatch disables the action.
- Timeline generation is cache-only. It includes the existing one-minute stale boundary and an upcoming permission-expiry boundary when appropriate. The requested next timeline is 15 minutes later, not a continuous polling guarantee.

## UI and accessibility

Small, medium and large headers reserve a 44-point action slot. The actual 44-by-44 button is a sibling outside the privacy summary's `children: .ignore` modifier, so the custom summary does not swallow the action. Its label and hint do not expose readings. Expired setup instead provides a link back to the app. Failure copy explicitly says that the saved reading is retained.

`FleetWidgetView` reads the real, get-only widget-family environment value and delegates to `FleetWidgetContent(entry:family:)`. The render tests exercise that same production content with explicit family sizes. They do not pretend to set the get-only environment property. The original acceptance file and the shared Vision/render harness are not changed.

The first direct image review found that a phone window's safe-area inset in the hosting fixture clips the small widget's timestamp. Those earlier captures were not accepted as footer evidence. The new fixture now uses the actual family rectangle and ignores only the host phone's safe area. It asserts the actual recognized saved-observation time, rate and header for all three families in both appearances, for both ready and failed states, and still captures paired privacy redaction. Direct inspection confirms the bounded small and medium failure-state footers fit. The original acceptance file and shared render harness are unchanged.

## Requirement-to-check ledger

| Requirement | Observed check |
| --- | --- |
| Separate, default-off consent and no escalation from aggregate sharing | Coordinator integration tests and installed Monitoring UI in both appearances |
| Foreground-only preparation and renewal | Regression test proves background updates cannot create or extend permission, while background Demo still revokes |
| Safe URLs, strict identity and bounded inventory | Engine rejection tests plus unchanged Core transport tests, including 28 unsafe-address cases |
| No reads with absent, malformed, oversized or expired permission | Injected-reader call counters remain zero |
| Exact limits, all-or-nothing telemetry and true zero | Up to 16 fixtures, observed maximum concurrency 4, no retries, complete sums and preserved prior timestamps |
| Consent/address/Demo changes during awaits | Actual intent helper, coordinator, private storage and separately compiled provider integration |
| Cross-process lease and revoke ABA safety | Twelve independent native CLI processes and two blocked-read revocation scenarios, using the actual production engine |
| Suspended-lock boundary | A private fixture holds the lock for 250 ms and the refresh declines without reads or a lease |
| Action awaits persistence before provider reload | Gated actual intent-helper path followed by the separately compiled production provider |
| Metadata and authentication declaration | Both built app and widget intent metadata, plus direct source/type assertions |
| Regular, failed and privacy-redacted layouts | Actual mounted production small/medium/large content in light and dark, observed through captured pixels and unchanged Vision OCR |
| Existing app, widget, activity and native behavior | Original mobile acceptance selection, installed widget/gallery/link/activity workflows and isolated strict native tests |
| Preserve unrelated work and frozen acceptance | Exact unrelated tracked-diff hash, 24 original untracked-file hashes, original acceptance and harness blob hashes |

## Validation receipts

Artifacts are under `~/.jcode/scratch/hashfleet-local-refresh-20261028-1940/`. Logs and result bundles are retained, including failures. Counts below are test definitions unless explicitly described as parameter cases or independent processes.

### Initial feature receipts (`f1068b6`)

| Check | Result |
| --- | --- |
| Final mobile Swift Testing selection, `mobile-final5.xcresult` | 188 definitions in 18 suites: 186 passed, 2 failed with 3 unchanged original spacing assertions, no skips. All 22 new refresh definitions passed, including foreground-only preparation and the strengthened timestamp checks. |
| Installed XCTest workflows on the final production sources, `mobile-ui-final3.xcresult` | All 5 installed tests passed with no skips: system-feature controls, separate default-off refresh UI, independent artwork, gallery/Home Screen/return-link flow, and synthetic Live Activity lifecycle. That combined bundle has 193 definitions: 191 passed and the same 2 original unit tests failed. Only the new test fixture changed afterward, not production sources. |
| Strict native Mac build and isolated tests, `native-final3-build.log`, `native-final3-tests.log` | Build succeeded with complete strict concurrency. 37 definitions in 6 suites passed. The loader opens derived test images, not the production app or production stores. |
| Unchanged production Core transport tests, `process-probe/transport-tests.log` | 11 definitions in 1 suite passed, including 28 parameterized unsafe-address cases. Actual two-file Core module, private fixtures only. |
| Independent-process persistence, `process-probe/results-final.json` | Passed: exactly 1 of 12 racers performed the injected read, 11 were busy. Revocation and revoke/re-enable rejected late results while retaining the fixed lock inode. |
| Final bounded-family footer image check, `mobile-final5.xcresult` | Passed for small, medium and large in light/dark, ready/failed states: 12 actual regular images with exact recognized observation time, plus 12 paired redacted images. No original acceptance or harness edits. |
| Project syntax and patch hygiene | `plutil -lint` and `git diff --check` passed. |

The process probe compiles the unmodified first 67 aggregate-definition lines plus the actual engine. Its engine SHA-256 is `17ee651c56dc0831e10e7066bd7e5e73fe6b26f78bb4e0c748d349163c165639`. It uses private local files and injected observations, not App Groups, widget dispatch or LAN access. It therefore proves independent-process file behavior, not a signed extension's entitlements.

The combined process/transport attempt `783761l569` exited nonzero after its process scenarios had passed because the manually compiled test launcher initially lacked the Swift Testing macro plugin. That overall attempt is not a green receipt. The corrected isolated launcher, with the installed compiler plugin explicitly loaded, subsequently ran the unchanged transport tests successfully (`151813cpu3`).

### Preserved red-to-green evidence

The first three implementation builds found and corrected actual compile problems: the Darwin `flock` import resolved to a struct, an observed property was read before initialization completed, and a nested testing macro inside another macro failed expansion. These failures remain in `refresh-first`, `refresh-second` and `refresh-third` logs/bundles.

`refresh-red.xcresult` then reproduced three real assertions in two new provider tests. Production fixes made an incompatible inventory disable the action and made expired permission retain the newest saved reading instead of reverting to an older cache. The failing assertions were kept, not weakened. `refresh-green.xcresult` passed all 20 definitions then present. Subsequent bounded-lock and foreground regressions brought the initial feature total to 22. The additional clock-boundary follow-up below brings it to 25.

The complete original selection is still **not green**. `WidgetActivityComponentCoverageTests` expects the literal `38W` twice for the medium widget and once for the large widget. Actual pixels and unbiased OCR contain the human-readable `38 W`. These are the same two original tests and three assertions. Neither the original assertions nor OCR normalization were changed to manufacture a pass. No claim is made that every selected acceptance test passed.

The strengthened footer assertion first failed in `mobile-final4.xcresult` because the expected CLDR time contained a narrow no-break space before AM/PM, while the unchanged OCR harness already normalizes whitespace. The expected formatter output now receives that same whitespace-only normalization. The exact hour, minute and AM/PM assertion remains. No OCR words, punctuation, casing, units, recognition settings or original acceptance assertions were changed. `mobile-final5.xcresult` verifies the corrected fixture and all 22 new definitions.

### Rejected worker output and preservation

A worker explicitly scoped to two new files produced incoherent output and edited unrelated source and package configuration. All of its proposed implementation and tests were rejected and replaced by root-owned work. The exact unauthorized package-target addition and legacy aggregate edits were restored. Two worker-created completion reports were quarantined with the rejected source under the artifact directory instead of being retained as authoritative reports.

The recorded worker also issued cleanup commands involving generated build state and a package-lock path. It is not possible to claim that generated-cache history was untouched or that every named path previously existed. This was a scope failure, not authorization to alter unrelated work. The worker was stopped. Two read-only review attempts also failed before useful review. There is no successful independent-worker review claim and no account, model-pool or provider change was made.

At the preservation checkpoint, the unrelated tracked binary-diff SHA-256 exactly matched `baseline.json`: `3f2157154a99c8e4387a61aa4293c7446688f19193da10f4fee5279975356793`. All 24 original untracked file hashes matched. The frozen acceptance and render-harness blobs matched `4a23e3bcc40587ca780b047e8e276ee45bea1eb7` and `836e2f3f147e95e4627a60c3e54afffa9b62a6b7`. `Shared/FleetGlance.swift` and `Package.swift` have no change from the starting revision. Only the twelve explicitly owned feature/test/report paths are eligible for the commit.

## Research and limits of the evidence

Official Apple documentation was checked for this design, separately from implementation tests:

- **Adding interactivity to widgets and Live Activities**: include an ordinary AppIntent in app and extension, complete asynchronous persistence before returning, and let the interaction trigger its timeline reload. The implementation does not issue a redundant timeline reload from the intent.
  `https://developer.apple.com/documentation/widgetkit/adding-interactivity-to-widgets-and-live-activities`
- **IntentAuthenticationPolicy**: the chosen policy requires authentication on the local device. The source declaration and emitted metadata are checked, but these are not a physical-device authentication test.
  `https://developer.apple.com/documentation/appintents/intentauthenticationpolicy`
- **TN3179, Understanding local network privacy**: extensions generally share their containing app's privilege; undetermined background access may be denied without a prompt; Simulator does not validate Local Network privacy. This is why recent foreground setup and a physical-device gate remain necessary.
  `https://developer.apple.com/documentation/technotes/tn3179-understanding-local-network-privacy`
- **Keeping a widget up to date**: timeline reload policy is not continuous execution or a precise cadence guarantee.
  `https://developer.apple.com/documentation/widgetkit/keeping-a-widget-up-to-date`
- **Darwin open(2)**: `O_EXLOCK` atomically obtains an exclusive flock-semantics lock and supports nonblocking acquisition.
  `https://developer.apple.com/library/archive/documentation/System/Conceptual/ManPages_iPhoneOS/man2/open.2.html`

Still unproven here: signed physical-device App Group access, first-unlock file protection, actual OS dispatch of the new button, local authentication and locked-device behavior, denied/revoked/undetermined Local Network permission, off-LAN transitions, actual network cancellation timing, mirrored widgets, StandBy, tinted/clear rendering, accessory-family hardware behavior and delivery cadence. The actual intent helper and emitted metadata do not substitute for those tests. Passing private process probes or Simulator UI tests does not waive this physical-device acceptance gate. No deployment is implied.

## Remaining-hypothesis follow-up, 2026-10-28 21:19 UTC

A concrete remaining hypothesis was tested with private injected clocks: could a permission renewed after its original creation still authorize reads after the current clock moves backward before that renewal? No system clock was changed.

The hypothesis reproduced a real defect. The original predicate fenced the initial creation date but not the latest renewal. Three added test definitions failed against the unchanged `f1068b6` engine while its existing 11 engine definitions passed. They cover:

- 6-, 60- and 3,600-second rollback after renewal: zero reads must start, and re-preparation at the corrected time must replace the old generation and expiry.
- Exact validity boundaries: the existing five-second tolerance remains allowed, a 5.001-second rollback is rejected, and expiration remains exclusive at 24 hours.
- A future-dated renewal while a read is awaiting: the generation is deliberately unchanged, so rejection must come from the time fence rather than the existing ABA check. The late reading must not be published.

The production fix adds the latest renewal to the same five-second time fence already applied to creation. The shared `isEnabled(at:)` predicate protects read claims, late publication and configuration reuse. It does not change the persistence schema, transport, opt-in defaults, UI, authentication declaration or target scope. All new failing assertions were retained unchanged through the fix.

Fresh artifacts are under `~/.jcode/scratch/hashfleet-refresh-clock-20261028-2108/`:

| Follow-up check | Observed result |
| --- | --- |
| `clock-red.xcresult` | 14 engine definitions: the 11 existing definitions passed and exactly the 3 new rollback/boundary definitions failed, no skips. |
| `clock-green.xcresult` | All 25 feature definitions in 2 suites passed, no failures or skips. |
| `mobile-final.xcresult` | 191 definitions in 18 suites: 189 passed, the same 2 original `38W` widget tests failed with 3 assertions, no skips. No new failure remains. |
| `native-build.log`, `native-tests.log` | Complete strict-concurrency native build succeeded, followed by all 37 selected native definitions passing. |
| `process-results.json` | The exact new engine and actual two-file Core module were rebuilt. The unchanged 12-process race again yielded 1 refreshed and 11 busy, with exactly one injected read. Both revocation scenarios again rejected late results and retained the fixed lock inode. |

The latest independently exercised production-engine SHA-256 is `e5e19aba921009888d4bd317ca8ae5f83f28851c5590cadbcc5f2cbff028009a`. The relocated process verifier preserves every scenario and assertion from the earlier probe. Only its executable/fixture root and reference to the already-verified aggregate definitions were relocated. Earlier receipts were not overwritten.

The initial 5 installed UI workflow passes and 11 unchanged transport-test passes remain earlier receipts, not newly rerun physical-device evidence. This follow-up changes only the permission-date predicate and adds its private regressions. It still does not establish actual OS dispatch, signed physical-device App Group behavior, permission/authentication states or delivery cadence. No real fleet access, production installation, deployment or system-clock modification occurred. The original acceptance file and OCR harness remain unchanged. The two original spacing failures are retained rather than hidden or redefined as passes.
