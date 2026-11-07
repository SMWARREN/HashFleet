# Actual product to website parity

Goal approved by the user on October 25, 2026. The actual iOS app, primary Mac app and CLI are the source of truth. The website must match the products, not redesign them to match a browser mockup.

## Baseline and provenance

- Repository baseline: `f814c5e`. This goal changes only the existing `website/` and this documentation, not the native apps, miners or notification service.
- iOS: current actual app running in an isolated iPhone simulator, `--ui-testing --demo`, dark appearance and normal system text size. Screens include fleet overview, gear menu, App settings, Fleet preferences, scrolled miner cards, Office Gamma detail and About.
- Mac: the primary Designed-for-iPad Mac application, not the menu-bar companion or the website. Current-source capture-only package launched locally using an existing development certificate/profile. `mac-runtime-provenance-v2.log` verified the running process executable hash against that package. No production app was replaced. Capture-only signing deliberately omits APS and the rejected NetworkExtension entitlement. This is UI capture evidence, not APNs runtime acceptance.
- CLI: actual current `hashfleet` binary built and executed against three synthetic HTTP fixtures bound to `127.0.0.1` only. Capture audit requires exactly nine `GET /api/system/info` requests for table, details and JSON. No configured fleet or discovery is used. Help requires no request. Hostnames, names, UUIDs and timestamps are sanitized as documented in `website/src/lib/cli-captures.json`; formatting and status fields otherwise come from the real binary.
- Private local evidence root: `/Users/USER/.jcode/scratch/hashfleet-product-parity-20261025/`. Source native PNGs are under `native/`; build/runtime receipts are under `receipts/`. Only reviewed lossless derivatives and non-secret hash metadata are published.
- `website/Tools/prepare-native-captures.py --verify` compares the decoded 8-bit RGBA bytes of every source PNG and published WebP. `native-captures.json` records original PNG, WebP and RGBA SHA-256, dimensions and byte counts. No app content is repainted or rearranged.

## Mismatch to acceptance map

| Area | Old mismatch | Corrected presentation | Required check |
|---|---|---|---|
| iPhone home | Invented bottom tabs, tiny recreated cards and separate metrics | Actual header, gear/add, demo and safety banners, one sample-fleet summary, native 1m trend, solo odds and expanded cards | Native pixels equal source; real phone overview used in hero and tour; no recreated tab bar in rendered DOM |
| iPhone navigation | Browser-only Fleet/Settings/About tabs and a global Restart in Settings | Real gear menu to App settings/About, Fleet preferences and miner detail, with explicit captured-screen navigation | Hotspot journey and picker, Back/reset, keyboard focus and image identity |
| iPhone settings | Invented sections and functional-looking native switches | Exact captured Notifications and banners, Your fleet, Across iOS and native preference form | Transcript compared to actual capture; browser makes no preference/device requests |
| Primary Mac | Simplified made-up workspace, search and cost slider | Actual fleet/miner sidebar, expanded cards, detail views, Network, Energy, Achievements, Reports, Backup, Settings and About | All 11 screen assets checked and selectable; sidebar journeys match corresponding native screen |
| Hero | A second fake phone with bottom tabs and synthetic terminal summary | Same real app images as the tours and actual CLI status header | Hero image sources equal tour sources; no fake phone UI remains |
| CLI | Older table missing session best and diagnostic format | Captured native table, `--details`, full JSON and help; native-shaped explicit-host selection | Actual binary recapture, direct fixture equality, host/order/parser cases, bounded input/history and no I/O |
| Browser capability | Lookalike controls implied native apps could run on the site | Captured screens, not an app stream; only outlined capture navigation/picker is active; switches/export/add/refresh/hardware controls in images are inactive | Persistent disclosure, accessible descriptions and no device/file/notification calls |
| Marketing | Copy implied an approximation was the real product | Platform-specific and safe preview copy, current CLI diagnostics, no continuous background monitoring or release availability claim | DOM assertions, FAQ/privacy/download review and real browser checks |
| Responsive/accessibility | Original tabs/dialogs and site branding must remain usable | Original gold/graphite site, tab keyboard behavior, tour picker, focus/scroll restore, fit/enlarge, transcript and clear image-failure message | Desktop/mobile sizes, light/dark, reduced motion, keyboard, back/reset, failed-image recovery |
| Publication | Local changes alone do not deliver the website goal | Narrow allowlisted upload to the existing `hashfleet.app` site with overwritten-file backup | Production bytes/CSP/MIME and public browser acceptance, plus unchanged backend/config/database/crontab |

## Scope boundaries

These are honest captured-screen walkthroughs, not a native app running in the browser. They preserve exact rendered native pixels and provide bounded tour navigation. A capture can show a retained reading or stale label; it is not current telemetry. The terminal is an allowlisted browser simulation using native captured fixtures, not a remote shell. Browser-only `help` and `clear` remain explicitly separate from `hashfleet` syntax.

No miner contact or hardware operation is needed to validate this goal. No firmware, settings, wiring, APNs credentials, signing profiles, notification enrollment, sending cron, physical-device installation or store release is authorized by the website work. Existing backend activation limits remain unchanged.

## Acceptance receipts

Observed local results on October 25, 2026 UTC:

- `frontend-final-v1.log`: TypeScript, all 112 tests in three files and the production build passed after the final modal-focus fix. Artifact: `index-SQCrJtWr.js` and `index-BUiLE7vo.css`.
- `prepare-native-captures.py --verify`: all 18 source PNGs and published WebPs have identical decoded RGBA. Total capture payload is 4,484,572 bytes.
- `cli-recapture-v1.log`: actual current native binary recapture required exactly nine loopback-only info requests. The normalized fixture matched the earlier reviewed fixture, with no native source change.
- `output/playwright/native-parity-20261025T045759769Z-native-parity-local/result.json`: all 185 actual Chromium checks passed, with zero browser errors or unexpected failed requests. CSP was injected for the local Vite test, not supplied by that preview server. Checks include every capture, real CLI output, focus/scroll/history, modal dismissal, both themes, five viewport widths and separate missing-image recovery.
- `deployment-local-v1.log`: existing installer fixtures, including actual rollback, and nine retired-endpoint guards passed against the expanded artifact. No network or production activation was used by those fixtures.
- Visually inspected actual landing, Mac tour, desktop iPhone, mobile iPhone and CLI browser captures against the source native captures.

Failed attempts remain failed: the first browser run stopped at image decoding before the current load-wait check; its root cause is not proven. A later 175-check browser pass had a shell-wrapper exit 127 because `rg` was unavailable, so that task is not labeled fully passing. The new fail-closed Node runner preserves timestamped logs and requires the actual browser result. Expanded modal checks then exposed reverse-Tab focus reaching the document body in Chrome with only one modal control. A focused production keyboard-boundary handler fixed that behavior. The original strict forward/reverse focus assertions were retained and passed in the final 185-check run.

The optional configured-route reviewer produced no bounded report and was stopped after a finish request. No independent-review pass is claimed. Older assertions requiring rejected lookalike tabs or sliders remain historical, not proof of native parity.

## Published result

Published the validated website to the existing `hashfleet.app` site at approximately **05:00:31 UTC on October 25, 2026**. Implementation milestone: `dd92a6f`. The tested installer promoted the exact 39-file allowlist and retained a private backup at `hashfleet-private/backups/20261025-050031-71175a16`. Archive SHA-256: `f6d19d1cce0ca8cb337c712339499cb474483df90e477b9fcd83bdf062a0b650`.

`deployment-live-v1.log` verifies all nine packaged service, retirement and host-policy files already matched the existing deployment before promotion. Private configuration, database bytes and permissions, service code, API and crontab hashes remained unchanged. No existing configuration was created or replaced. The post-publication check still reports `provider_ready: false` and zero sending-cron lines. A cPanel CLI wrapper warning remains in the raw receipt; the installer and protected-state checks completed successfully. No notification was sent.

Final post-implementation checks:

- **112 unit tests**, TypeScript and the final production build passed. No native app, shared-core, notification extension, server or project source changed from the task baseline.
- **186 local browser checks** passed in `output/playwright/native-parity-20261025T050302371Z-native-parity-local/result.json`.
- **187 public browser checks** passed in `output/playwright/native-parity-20261025T050302380Z-native-parity-public/result.json`. The extra public check requires the real server's exact restrictive CSP, with no CSP response interception. Both runs decoded both hero images before visual capture, checked all 18 native assets and all three product tours, and reported no browser errors or unexpected failed requests.
- The final actual landing, native Mac and mobile iPhone captures were visually reviewed. The published Mac overview was also opened and visibly inspected in the existing Chrome product tab, left ready for the user. The optional browser handoff route lacked credentials, so direct browser actions were used without account changes.
- `deployment-final-v2.log`: all **10 installer tests**, including rollback, and **nine retired-endpoint guards** passed against the final artifact.
- `public-assets-v2.json`: **31 actual build responses** matched the validated local bytes, MIME, no-store policy and all five expected security headers. All **nine protected/missing/directory paths** returned 403 or 404. This is not an entirely passing strict HTTP audit, as detailed below.

### Historical host-denial header limitation, superseded by React entry

`Tools/public-parity-assets.mjs` remains strict and exits 1, not a manufactured pass. Its 40-request receipt records nine mismatches on two denied paths. The existing host returns 403 for both `/.env.local` and `/.git/config`, with `X-Frame-Options: SAMEORIGIN` and no site Referrer-Policy, Permissions-Policy or CSP headers on those two denial responses. The Git path also returns 403 rather than the strict tool's expected 404. No requested private file was served. The homepage, every build asset and the other seven denial responses matched their expected policies.

The collector was changed only to finish recording all responses before enforcing the original assertions. The failing expectations were not removed or relaxed. No hosting-wide protection was disabled or global server configuration changed to make this ancillary audit green. This response-policy gap is recorded separately from the successful product-parity/browser acceptance and does not establish physical-device, Safari, WCAG or APNs certification.

Follow-up on October 25 at 05:17 UTC: a backed-up, automatically restored live `.htaccess` probe applied its diagnostic header and custom error body to ordinary site responses, but neither to the two affected 403s. The initial inference that no site-only solution was possible was too broad. Later rewrite probes at 05:36 and 05:41 UTC handled the inherited internal error-document request, applied all five headers and preserved the actual 403. `WEBSITE-REACT-ENTRY.md` records the corrected implementation and current publication receipts. `WEBSITE-HOST-HEADERS.md` retains the historical probes and optional administrator proposal, which was not applied. No blocking protection was relaxed, and the strict audit still requires its original Git-path status expectation to be reported honestly.

The corrected site-only React entry was published at 05:55 UTC and verified at 05:56 UTC. All 126 public routing checks and all 187 original product checks passed. All eight earlier header findings are fixed across the same strict 40-response audit, with 31 exact build responses. Its sole retained failure is the Git-path 403 versus expected 404. Protected files remain denied and private state is unchanged. Full deployment and acceptance receipts are in `WEBSITE-REACT-ENTRY.md`.
