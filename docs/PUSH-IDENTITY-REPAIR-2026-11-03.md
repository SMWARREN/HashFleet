# APNs identity repair acceptance: November 3, 2026

## Authorization and result

At **2026-11-03 09:18:50 UTC**, the owner explicitly requested fixing the previously reported notification mismatch. The narrow live correction completed at **09:35:44 UTC** and its independent source, parser and HTTPS verification completed at **09:35:48 UTC**. This supersedes the earlier deployed-topic mismatch recorded in `STORE-URLS-ENCRYPTION-ACCEPTANCE-2026-11-03.md`. It does not certify physical notification delivery.

## Exact live changes

Only three private server files changed:

- `APNs.php`: the two legacy `org.axefleet.app` topic literals now use `app.hashfleet`, including the readiness allowlist and outgoing `apns-topic` header.
- `Service.php`: the five outgoing notification namespace occurrences now match the accepted native contract: `app.hashfleet.summary`, `app.hashfleet.deviceID`, `app.hashfleet.checkVersion`, `app.hashfleet.checkIssuedAt` and `app.hashfleet.checkRequestID`.
- `config.php`: only the single legacy APNs topic value changed to `app.hashfleet`. Every other parsed configuration value and every other original configuration byte was preserved, including relative-path semantics. No key, team, salt, token or database location was replaced.

The two corrected PHP source files are byte-identical to the original accepted backend at native audit revision `320510d645a7e5849d13deff73d312b25ef42781`. Their live read-back SHA-256 values are:

| File | SHA-256 |
| --- | --- |
| APNs.php | `e11776d40fc47d5aade4e2763b5263afec055c49f9b555e5deccaf5db08d3800` |
| Service.php | `2552f5fc90cf45e4a5312c52e662d22725736d1a34442e6d59f488b8fee68d06` |

## Validation and preservation

- **143 unchanged backend checks passed** against the exact candidate files, using SQLite fixtures and injected provider outcomes. No production APNs or miner requests were made by these tests.
- The actual PHP payload method was exercised without constructing the live service or opening its database. **14 cross-language checks** compiled the unchanged accepted native `FleetScheduledCheck.swift` parser: the legacy deployed payload was rejected, the corrected payload was accepted and version, timestamp, identity, request-ID and category boundaries remained enforced.
- **Four topic-allowlist boundary checks** confirmed only the current iPhone topic was accepted. The legacy topic, `app.hashfleet.mac` and the empty topic were rejected.
- **Two offline deployment cases passed**: successful exact promotion with `__DIR__`-relative configuration, and forced provider-readiness failure with restoration of all three original file hashes. The expected legacy-topic failure and forced rollback diagnostics were retained, not rewritten as successful old behavior.
- All promoted PHP files passed syntax checks. The dispatcher lock was held during promotion, each file was promoted atomically, and original mode-600 permissions were preserved.
- Private pre-change file backups and a consistent read-only SQLite backup were independently hash/logical-state checked. The live database remained logically identical during promotion and the immediate independent private verification, including the registration, schedules and job tables. The promotion and private verifier did not construct the live service, run a migration, register a device, write preferences, update tokens or invoke dispatch/send methods.
- **101 other protected files and their modes** remained unchanged, including the public website and private source/key boundaries. The account crontab hash was unchanged. No Hash Fleet dispatcher entry was present in the inspected crontab and none was installed. This does not assert that every possible external scheduler was inventoried.
- Freshly downloaded corrected live source generated a payload accepted again by the unchanged native parser. The real public HTTPS health response was HTTP 200 with `mode=device_check_v1` and `provider_ready=true`. Readiness validates local prerequisites, not Apple's acceptance or delivery. The separate health request uses the existing API initialization and may update its request-rate bucket, so database preservation above is scoped to the promotion/private verification window.

No native application source, installed app, uploaded iOS build 18, uploaded Mac build 19, App Store screenshots, store submission, Apple key, hardware configuration or recurring notification setting was changed by this repair.

## Remaining phone gate

A fresh read-only copy of the physical owner's app-owned preferences at **09:36:50 UTC** retained the same four saved device IDs and showed remote push **disabled**, with registration **unconfirmed**. No Keychain was read and no phone launch, preference write, reinstall or reset was performed. The current server's stored four-miner registration has **zero overlapping miner IDs** with that phone inventory. That is not sufficient evidence to target it, nor proof of who owns that older registration.

**No test push was sent.** A positively identified current owner-phone registration is still required. The repair does not silently enable recurring notifications or reuse an unverified device token.

Owner-private source snapshots, unchanged-suite logs, actual PHP payloads, original-parser verification, offline rollback tests, live repair receipts and the fresh phone check are under `~/.jcode/scratch/hashfleet-rights-push-demos-20261103T0825.noindex/push-mismatch-20261103T0926.noindex/`. The remote rollback backup remains outside the document root at `~/hashfleet-private/backups/push-identity-20261103T0926Z/`. No credentials or tokens are included in this document.

The independent configured worker route failed before returning findings. Acceptance above is based on coordinator-executed checks and recorded artifacts, not an invented worker review. The separately requested iPhone and Mac review demo attachments remain separately tracked and are not claimed delivered by this repair.
