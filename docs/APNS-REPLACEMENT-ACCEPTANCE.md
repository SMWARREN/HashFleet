# Scheduled APNs check acceptance

Checked **October 25, 2026 UTC**. This record supersedes the uploaded-telemetry, separate LAN companion, and replacement browser dashboard acceptance from the initial October 24 implementation. Those earlier receipts remain historical evidence, not proof of the corrected product.

## Outcome and activation boundary

- Native iOS and primary Apple Silicon Mac compatibility app Notifications settings own the global switch, miner choices, and 1/3/6/12/24-hour intervals. New installations are off. The CLI remains the existing read-only product.
- The declined Network Extension Local Push target and entitlement, SSID/location setup, standalone Python LAN companion, and browser schedule controls are removed.
- The original `website/` React marketing site and its Mac, iPhone, and Terminal demos are restored on **hashfleet.app**. The private backend now accepts scheduling metadata only in `device_check_v1` mode.
- Proposed runtime path is server scheduler to standard mutable APNs alert to the app's bundled notification service extension, which attempts a short, pinned, read-only local check. A failed check is unavailable, not proof the miner is offline. A push already accepted by Apple may still appear after opt-out.
- **Not activated or certified for production delivery.** No APNs key was created/configured, no sending cron was installed, no signed app was installed on a physical device in this correction, and no real push was sent. Provider readiness remains false. The physical iPhone push-to-LAN path and primary Mac notification extension runtime remain unverified. Simulator results and an unsigned compatibility build cannot establish those outcomes.

## Requirement-to-check traceability

| Requirement | Observed check and result |
| --- | --- |
| Remove rejected capability and setup | Shipping `App/` source search returned no NetworkExtension, NEAppPush, old compilation flag, location import, SSID API, or rejected setup identifier. Generated project embeds `HashFleetNotificationService.appex` with `com.apple.usernotifications.service`, not PushProvider. Ordinary local alerts remain available in UI acceptance. |
| Correct push signing configuration | Actual `xcodebuild -showBuildSettings` resolves both Debug configurations to `development` and both Release configurations to `production`; all select the standard app entitlement file. App and new extension use `group.app.hashfleet.shared`. Real signed provisioning remains a separate activation gate. |
| Controls in the apps, not the site | Native UI test `testScheduledSummariesStayInlineOffAndDisabledInDemo` passes and its screenshot was visually reviewed. It asserts no browser management or companion export controls. The primary Mac app builds from the same settings source. |
| Opt-in, permission, credentials, token and races | Focused `FleetRemotePushTests` cover default-off, demo/test isolation, denied permission, token wait/refresh, serialization, server opt-out/revocation, offline disconnect retry, per-miner choices, and unprepared/malformed local identity. Actual DTO bodies are inspected for the metadata-only schema. |
| Real native HTTPS boundary | `FleetRemotePushHTTPTests` run the real URLSession client against an injected URLProtocol. They cover fixed origin/methods, private headers, exact response wrapper, canonical credentials, redirects, auth/rate/server errors, oversized bodies, deprecated endpoints, and cancellation. No public enrollment or miner calls occur. |
| Safe local read | `FleetScheduledCheckTests`: **11 tests passed**, including **34 parameterized URL cases**, plus storage, typed version/time/request validation, MAC identity, optional finite metrics, HTTP/JSON/body limits, timeout/cancellation, and before/after-I/O selection changes. Every request uses a fixture. Only fixed GET `/api/system/info` is available. |
| Extension lifecycle and expiry | Six `FleetScheduledNotificationServiceTests` compile the exact shipping extension source in a test-support framework. Concurrent completion, late task installation, invalid/disabled configuration, successful local formatting, transport fallback, and the actual expiry callback pass. No shared production defaults or live network are used by the tests. |
| Existing native behavior and primary Mac packaging | Final simulator run: **163 tests in 15 native suites plus 8 UI tests passed**. Original header, quiet session popup opt-out, largest-text actions, local preferences/search and notification previews remain covered. Primary Mac compatibility app build with bundled extension: **BUILD SUCCEEDED**, signing disabled. |
| CLI/shared-core regression | Final complete `swift test`: **271 tests in 28 suites passed**. This includes the new reader suite; do not add its 11 tests again to this total. |
| Metadata-only server and safe migration | Independent PHP run: **143 real SQLite/backend checks passed**. New registrations/defaults, strict fields, auth/isolation/token ownership, native preferences, no-reading due eligibility, mutable alert schema, additive legacy-inactive migration, removed telemetry/relay routes, retry/claim exhaustion, token-generation-aware 410, cancellation and retention are covered. |
| Actual API HTTP behavior | **25 actual loopback HTTP checks passed** against a real isolated PHP server. No external requests, public enrollment, physical miners, or Apple sends. |
| Preserve original website and three demos | **82 website unit tests passed** and production build succeeded. Existing browser acceptance passed **95 checks locally** and **95 checks on the restored public host**, including actual server CSP, all three demos, narrow screens, keyboard/focus, themes, charts, search, local-only demo behavior and rendered assets. These are two runs of the same acceptance, not independent feature counts. |
| Retire the second dashboard and fourth companion | **9 retired-endpoint checks passed**. Old `app.js` executes in a trapped VM with no network/storage/credential/notification effects. Fallback pages expose no forms/scripts; old Python download is denied by Apache. The obsolete dashboard behavior tests were intentionally replaced because the user rejected that interface. Original-site behavior is tested separately, not waived. |
| Narrow deployment, preservation and actual rollback | **10 real installer tests passed**, including a mid-promotion permission failure restoring existing bytes and modes and removing newly created configuration. Other cases cover SHA-256/allowlist failures, executable/unhashed asset rejection, symlinks, missing webroot, backups, unrelated files and repeated config/database preservation. |
| Fresh live site and API verification | **35 read-only HTTPS checks passed** after deployment: original homepage and hashed assets, no-store without conflicting max-age, security headers/no public CORS, retired controls, authenticated private endpoints, disabled telemetry/relay, private-file/index denial and denied old companion download. No production enrollment, private API mutation or APNs send. |

## Receipts

Local receipt root:

```text
/Users/USER/.jcode/scratch/hashfleet-apns-20261024/
  device-check-final-v3.log
  device-check-final-v3.xcresult
  device-check-mac-build-v1.log
  device-check-resolved-signing-v1.log
  core-acceptance-final-v2.log
  core-full-package-final-v1.log
  backend-metadata-independent-v1.log
  backend-package-final-v2.log
  deployment-rollback-final-v3.log
  original-site-packaging-v1.log
  original-site-browser-local-v1.log
  original-site-browser-public-v1.log
  device-check-deployment-live-v2.log
  device-check-https-live-v1.log
  corrected-native-review/manifest.json
  corrected-native-review/75CD61BE-60BA-4EA5-A3A3-4546F2017473.png
  corrected-preview/fleet-normal-size.png
```

The standard-size demo-only app was relaunched on the existing iPhone 17 Pro / iOS 26.5 simulator after UI acceptance. No real fleet was configured or queried. The existing browser tab was reloaded to the restored original homepage.

Source milestones:
- `7cd8d57`: native schedule controls and bounded local notification extension, rejected target and standalone LAN companion removal.
- `8d69dd5`: original website restoration packaging and metadata-only backend.

### Live deployment scope

The verified existing Hash Fleet webroot and sibling private service directory were the only deployment targets. **21 allowlisted files** were installed, with private overwritten-file backup:

```text
~/hashfleet-private/backups/20261025-014418-d728b89d/
```

Existing `config.php`, SQLite file, and complete crontab were checksum-compared before and immediately after file installation and were unchanged. The following `dispatch.php --check` applied the additive schema migration and reported `provider_ready: false`. There are **zero Hash Fleet sending cron entries**. No unrelated files were deleted, no host-wide configuration was edited, and existing private configuration was not replaced. Subsequent API GETs may update rate-limit rows; database byte identity is a file-installation preservation check, not a claim that ordinary service use is read-only internally.

The first deployment attempt used an incorrect `bundle/` path after archive extraction. PHP lint could not open that file and the installer was never invoked. The failure receipt is retained as `device-check-deployment-live-v1.log`; the corrected archive-root invocation produced the successful v2 receipt. No production safety check was bypassed.

## Retained failures and evidence limits

- Initial native integration v1 failed to compile a test helper's optional return inference. It was fixed without weakening assertions; v2 and the final v3 run passed.
- The earlier `native-final-v4` run from the rejected architecture had a compact-preferences UI failure. Its log/result and `preferences-failure-v4-review` artifacts remain. An isolated earlier retry and the final corrected full run passed. The exact cause was not established. The compact switch assertion, single control tap and persisted-state check were not removed, blindly retried, or changed to accept an off state.
- The first core worker scaffold was rejected for missing the actual HTTP reader and invalid boundaries. It was preserved privately under `rejected-core-worker/`; the coordinator replaced it and independently ran the final suite. Rejected worker output is not integrated acceptance.
- No App Store approval, real provisioning, physical-device extension execution, actual APNs response, phone presentation, away-from-home access, exact hourly cadence, guaranteed iPhone background availability, or primary Mac extension runtime is claimed.

## Additional Local Push removal validation

Further validation completed **October 25, 2026 UTC**, using new isolated derived-data directories rather than reusing the earlier build result. No native runtime edits were needed. The repeatable read-only guard is `Tools/verify_local_push_removal.py`, with **17 positive/negative tests** in `Tools/test_verify_local_push_removal.py`.

| Requested validation | Additional observed evidence |
| --- | --- |
| Remove `FleetLocalPush.swift` | File absent from disk and tracked project, no coordinator, rejected provider flag or lifecycle references in shipping Swift/project files. The guard also rejects reintroduced untracked/ignored source and dangling legacy symlinks. |
| Remove Local Push UI from `FleetPreferencesView.swift` | Full source check excludes the old toggle, unavailable-build instructions, SSID list and location setup. Actual `testRejectedLocalPushIsRemovedAndLocalNotificationsRemainAvailable` passed and still requires the ordinary local test-notification control. Diagnostic Wi-Fi labels from miner-reported data remain intentionally unchanged. |
| Remove `PushProvider.swift` and NetworkExtension code | Provider source/resources and target references are absent. All three new app bundles contain only the existing widget extension and standard notification service. Actual Mach-O dependency inspection, including Debug dylibs, found no NetworkExtension framework link. |
| Remove the `FleetSharedStore.writeDevices` mirror | No call remains anywhere in shipping `App/` source. The existing local fleet encode/save and recovery paths remain, and fresh persistence-boundary tests passed. The shared-core legacy API remains for compatibility, not as an app background-polling mirror. No real shared defaults were mutated for this check. |
| Standard `aps-environment` entitlements | Both app templates retain `$(APS_ENVIRONMENT)` and the existing App Group. Separate actual app and service-target captures cover all four configurations: Debug variants resolve `development`, Release variants resolve `production`, with no rejected compile flag. The service selects its own matching App Group template. These are configuration checks, not signed entitlement/profile proof. |
| Validate Swift compilation | Fresh Debug simulator run passed **69 native tests in six suites and both actual removal/inline-settings UI cases**. Fresh unsigned generic-iOS **Release** and primary Designed-for-iPad **DebugNoAppPush** builds both succeeded, compiling and embedding the standard service while retaining widgets. |

Receipt root: `/Users/USER/.jcode/scratch/hashfleet-local-push-validation-20261025/`. `verify-builds.sh` records the exact three build/test invocations. `capture-service-settings.sh` separately records all four explicit service-target settings captures. `focused-native.xcresult`/`.log`, `device-release.log`, `mac-compatibility.log`, the eight `settings-*.json` app/service captures, and `full-package-guard-v3.log` retain observed results. `guard-tests-v3.log` records all 17 guard tests passing. The guard was committed as `bcd2c1a` and performs no network requests, builds, signing, installation, defaults writes, enrollment or notification sends.

To repeat the source guard and its negative tests:

```sh
python3.12 -B -m unittest Tools/test_verify_local_push_removal.py -v
python3.12 -B Tools/verify_local_push_removal.py
```

For the actual captured configuration and compiled-package gate, additionally pass `--build-settings-dir` with all four `settings-CONFIG.json` and `settings-service-CONFIG.json` pairs, plus one `--app-bundle` per freshly compiled bundle. A source-only invocation explicitly reports zero configuration/bundle captures; it is not counted as a build or packaging pass.

Two early guard attempts remain failed evidence rather than being recast as passes. `source-guard-first.log` incorrectly classified empty historical `PushProvider/Resources` directories as source. Disk/tracked/ignored-file inspection established that they contain no files. The corrected guard permits empty directories but still rejects actual provider files/resources and symlinks, with explicit negative tests. No directory was deleted. `full-package-guard-first.log` correctly rejected missing service-target evidence because scheme-level `-showBuildSettings` returned only the app row. Explicit target captures supplied the missing evidence; no target-row assertion was removed. An optional read-only worker produced no bounded audit report and was stopped after about 13 minutes. It is not an independent-review pass or evidence that any model route is permanently unusable.

Existing AppIntent confirmation deprecation and extension metadata-extraction warnings remain in the successful build receipts. This validation does not claim a warning-free or whole-app audit. Signing/provisioning, physical iPhone and Mac extension runtime, actual APNs delivery, sending cron and release activation remain unperformed gates below.

## Remaining authorized acceptance gate

Before enabling real delivery, obtain explicit operator approval for private APNs key setup, matching app/extension signing and an isolated test push. Then test the paired physical iPhone with notifications and Local Network permission already granted, a refreshed pinned miner target, and native opt-in. Observe locked/on-LAN, off-LAN, permission-denied, stale/mismatched identity, expiry, opt-out, token refresh and generic fallback separately. Verify the primary Mac compatibility app's actual extension delivery/runtime separately as well. Record Apple acceptance and device presentation as different observations. Only after those checks should a separately authorized sending cron or release be considered.
