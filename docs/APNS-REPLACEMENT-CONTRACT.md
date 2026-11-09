# Hash Fleet scheduled push-check contract

Revised October 25, 2026 after the user's architecture clarification. This supersedes the initial uploaded-telemetry / separate-companion / browser-dashboard design. That initial implementation is retained in git history, not the shipping product.

## Product and limits

- Exactly the existing iOS app, primary Mac compatibility app, and CLI. No fourth always-on companion is required or installed.
- All notification switches and per-miner schedules stay inside the existing native Notifications settings group. Preserve the original `website/` React marketing/demo site. The website supplies a private scheduling API only, not browser settings.
- Proposed delivery: explicit native opt-in -> server cron -> standard APNs alert with `mutable-content: 1` -> a notification service extension bundled inside the iOS app attempts a short read-only LAN check -> the alert shows a freshly obtained summary or an honest unavailable message.
- This is not Apple's declined Network Extension Local Push API. No NetworkExtension entitlement, NEAppPushProvider, SSID/location requirement, continuous background poller, hardware changes, or implied approval.
- The phone still needs internet/APNs access, a route to the saved miner, and previously granted Local Network and notification permission. Apple controls delivery and grants the extension about 30 seconds. Exact hourly execution, delivery, device availability and off-LAN access are not guaranteed.
- The specific push-to-LAN path needs signed physical-device acceptance. Simulator/fixtures/compilation are not that proof. APNs acceptance is not presentation or a successful miner check.

## Cloud privacy and wire version

Base: `https://hashfleet.app/api/v1.php?action=ACTION`. HTTPS, JSON, no secrets in URLs or logs, no CORS wildcard, `Cache-Control: no-store`. Maximum 128 KiB request/response and 64 miners per installation. Unknown/missing fields are rejected.

Private calls use `X-HashFleet-Installation: <lowercase UUID>` and `Authorization: Bearer <32 random bytes base64url>`. Native Keychain stores the secret. Server stores its hash, scopes all data by installation and enforces token uniqueness and rate limits. Never put installation credentials into website fragments, clipboard or browser storage.

**Cloud data is scheduling metadata only:** installation credential hash, APNs token/environment, opaque miner UUIDs, switches and intervals. No miner names, LAN addresses, readings, wallets, pool/Wi-Fi credentials, or raw firmware responses are uploaded by the native app.

- `POST register`: exactly `{mode:"device_check_v1", device_token:<hex>, environment:"sandbox"|"production", miners:[{id:<UUID>}]}`. Known UUID requires its current credential; another installation cannot take a device token. New installation is globally off, miner defaults on/hourly. Re-register preserves saved choices and removes no unrelated installation. Return wrapper below.
- `GET preferences` / `GET status`: authenticated wrapper `{ok:true, mode:"device_check_v1", provider_ready:bool, settings:{enabled:bool,miners:[{id,enabled,interval_minutes}]}}`. Status may also include sanitized schedule timestamps and token validity, never token, credential, local readings or names.
- `PUT preferences`: exactly `{enabled:bool, miners:[{id:<UUID>,enabled:bool,interval_minutes:60|180|360|720|1440}]}`. Replace this installation's catalog, preserve isolation, cancel removed/disabled/changed queued jobs and reschedule from now rather than bulk catch-up. Wrapper response.
- `DELETE register`: confirmed native disconnect only. Delete this installation's server records. Never another installation's records. Native local disable takes effect before awaiting the server; retry offline deletion rather than claim success.
- `GET health`: minimal public service/mode/provider readiness only.
- Remove/reject old `telemetry` and `relay` write endpoints. There is no public HTTP send action.
- Safe additive migration: legacy rows remain inactive and MUST NOT become eligible for new push-check delivery without an authenticated `mode:device_check_v1` registration. Old relay access cannot read or manage schedules. When that installation explicitly migrates, clear its old uploaded readings/relay credential. Do not silently convert legacy schedules or destroy unrelated records.

## APNs / cron

Private CLI dispatcher and P-256 ES256 key remain outside webroot. Fixed Apple HTTPS/HTTP2 endpoints, TLS validation on, exact topic `app.hashfleet`, sandbox/production per token, provider readiness false until genuinely configured. Keep sends and live cron unconfigured until explicit operator activation. Do not create/revoke Apple keys, install cron, submit a release or send pushes without authorization.

Due selected miners no longer need uploaded readings. Preserve transactional job claims, retries/backoff, exhausted-claim handling, token generation checks, cancellation and bounded retention. One check request per due selected miner is acceptable for this implementation; no tight catch-up loops.

Payload schema: `aps.alert.title = "Scheduled miner check"`; safe fallback body = `"Open Hash Fleet on your miners' network to check current readings."`; `aps.mutable-content = 1`; `aps.category = "app.hashfleet.summary"`; stable thread; custom `app.hashfleet.deviceID` UUID, `app.hashfleet.checkVersion = 1`, `app.hashfleet.checkIssuedAt = <unix seconds>`, `app.hashfleet.checkRequestID = <UUID or stable opaque request ID>`. Never include a URL, command, miner name or metric in the remote payload. Priority 5, short 5-minute TTL, per-installation/miner collapse ID. Extension rejects unknown version, stale (>600 seconds), unreasonable future (>120 seconds), invalid request IDs and unselected targets. Do not describe rejected/unreachable data as a miner offline.

## Local extension safety

- New minimal app-group configuration separate from legacy shared device storage: global enabled and selected targets only, with miner UUID, display name, validated literal private IPv4 base URL, and pinned MAC identity learned from an app-observed miner response. No wallet, pool/Wi-Fi credentials, secure cloud credential or entire snapshots in this shared configuration.
- Target API is fixed GET `/api/system/info`. No discovery, arbitrary payload URL, redirects, proxies, cookies, caches, scripts, hardware writes, self-test, restart, OTA, pool or tuning operations.
- Permit only canonical RFC1918 IPv4 hosts, `http`/`https`, bounded valid port, root base URL, no userinfo/query/fragment. Unsupported/identity-unprepared miners remain unprepared, not silently probed.
- Pin/check the firmware MAC so a reused private address on a different LAN cannot be presented as this user's miner. Missing/mismatched identity returns unavailable, never false live/offline. All metrics must be finite, within bounds and optional. Missing metrics stay unavailable, never zero.
- Ephemeral bounded network read, short request deadline comfortably below extension expiry, maximum 128 KiB response, no response/error/raw telemetry logging or cloud upload. Only format an allowlisted local summary after validated successful HTTP/JSON/identity.
- Shared config disabled/cleared immediately for opt-out, demo/test mode, removal and disconnect. Recheck selection before rendering after async I/O. A remote alert already accepted by Apple may still appear; never promise it can be silently cancelled by the extension.
- Notification handler completes exactly once on success, error, cancellation and expiration. Preserve safe generic fallback if extension is never run. Keep existing local alert and deep-link routing; scheduled summaries are not block-found/best-share celebrations.

## Requirement-to-check gates

1. Source/project audit: no declined shipping target/entitlement/SSID-location UI; extension embedded and app-group permissions match; debug/prod APS environment resolved correctly.
2. Native opt-in, denied permission, Keychain failures, token wait/refresh, per-miner schedule, serialization/opt-out races, demo/test isolation, disconnect retry. Assert actual outbound bodies contain only scheduling schema and no telemetry or local target data.
3. Core local reader: allowed/private and rejected URL boundaries, UUID/time/version validation, corrupt/disabled/removed config, identity mismatch/missing, HTTP error, redirects, invalid/oversized JSON, finite/missing metrics, cancellation and callback expiry behavior. No actual fleet network calls in fixtures.
4. PHP real-SQLite/API: strict new schema/auth/isolation/token ownership, disabled/default/due/interval/removal, no-reading due eligibility, legacy rows ineligible, no telemetry/relay, jobs/double-dispatch/retries/410-generation safety and bounded retention. Keep negative assertions outside caught-error blocks.
5. Original website build/unit/browser acceptance, original three demos, narrow screens, no leaked fleet data. Public site must not be a replacement notification dashboard. Only minimally update optional-push privacy copy without redesign.
6. Deployment allowlist and actual-file rollback/backups, private source outside webroot, config/database preserved on repeat deploy, no unrelated deletion or host-wide edits. Verify fresh HTTPS responses after deployment.
7. Focused iOS tests/UI, primary Mac compatibility build, embedded extension compile, final verifier after last edit. Preserve any unrelated compact-switch failure and don't weaken tests to obtain green.
8. Real signed APNs/physical iPhone validation remains separately blocked if credentials or device access are unavailable. Report that boundary explicitly, not as completed production delivery.
