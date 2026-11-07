# Hash Fleet website

The existing gold and graphite product site for `hashfleet.app`, built with React, TypeScript and Vite. The native products are the source of truth. The website does not change the apps to match browser mockups.

## Current previews

- **Mac:** 11 lossless captures from the actual primary Designed-for-iPad Mac app. Its real sidebar opens captured miner details, Network, Energy, Achievements, Reports, Backup, Settings and About.
- **iPhone:** seven lossless captures from the actual current simulator app. Follow its gear menu, App settings, Fleet preferences and miner detail. There are no invented bottom tabs or global Settings restart.
- **Apple Watch:** five unmodified native PNGs from submitted iOS/Watch build 20. The fourth product tab and hero Watch open a screen tour covering the fleet, miner readings, lower details, discovery empty state and manual setup. Step buttons, Next, history-aware Back, Reset and outlined captured navigation are interactive. Transcripts, current-step announcements and image-failure recovery support inspection. The pictured form does not accept an address or scan a network. Requires watchOS 26.5+ in the native product, not in this browser tour.
- **CLI:** an allowlisted browser simulation backed by output captured from the actual current `hashfleet` binary. Colored status, the transparent pixel logo, `--details`, full `--json` and native help use current binary captures. `hashfleet watch --demo` opens a keyboard-and-button dashboard: select miners, inspect four detail sections, navigate five settings sections, pause/resume, sort, view the logo, and quit back to the same command prompt. Command history and the existing suggestions remain interactive.
- The hero reuses the same actual native images and real CLI status header. Original artwork, branding, light/dark themes, FAQ, keyboard tabs, modal focus handling and responsive layout remain.

**The GUI previews are captured-screen walkthroughs, not native apps running in the browser.** Only outlined navigation, the screen picker and tour tools are active. Switches, add-miner, refresh, exports and hardware controls inside an image are not functional browser controls. Fit/enlarge, readable descriptions, Back and Reset support inspection without implying a live app stream.

Every miner reading is fictional. Captured stale labels and timestamps remain unchanged, not recast as current telemetry. No discovery, miner connections, notifications, settings writes, file exports, restart, tuning or firmware operations occur. Terminal `help` and `clear` are explicitly browser-only utilities. Status input is restricted to documented syntax and reserved `*.invalid` sample hosts. Watch/settings commands use the native CLI’s built-in fictional demo fleet (`*.example`). Its settings remain preview-only, matching native `--demo`. Captured snapshot ages and readings are not live polling.

The complete discrepancy map, capture provenance, acceptance results and remaining platform limits are in `../docs/WEBSITE-PRODUCT-PARITY.md`. Older lookalike-specific assertions in `Tools/browser-acceptance.js`, `ACCEPTANCE.md` and `NATIVE-PARITY-REFERENCES.md` are historical evidence, not the current capture-tour contract.

## Run locally

Dependencies are pinned in `package-lock.json`. Node 22.16.0 and npm 10.9.2 were used for the original setup.

```sh
cd website
npm ci
npm run dev
```

The development preview listens only on loopback, port 4173. For production-artifact acceptance:

```sh
npm run check
npm run build
./node_modules/.bin/vite preview --host 127.0.0.1 --port 4174 --strictPort
```

Deploy only the build contents, never the source directory or `node_modules/`. The public static product site needs no Node process, API key or fleet backend.

## Reproduce current acceptance

Keep the production preview running, then use the installed Jcode Playwright CLI skill through the checked-in runner:

```sh
node Tools/run-native-parity.mjs http://127.0.0.1:4174
node Tools/run-watch-acceptance.mjs http://127.0.0.1:4174
# After an authorized, validated deployment:
node Tools/run-native-parity.mjs https://hashfleet.app
node Tools/run-watch-acceptance.mjs https://hashfleet.app
# Separate strict build-byte, header and private-path audit:
node Tools/public-parity-assets.mjs
```

The runner injects the checked-in capture manifests into `Tools/native-parity-acceptance.js`, uses an isolated browser session and requires an actual passing browser result. Logs, structured results and screenshots are retained in a new timestamped directory under ignored `output/playwright/`. Unsupported origins are refused. Local Vite checks inject the restrictive CSP into the test response. Public checks require the real server's exact CSP without response interception.

The checks cover all 18 asset hashes, byte counts, MIME types and native dimensions, platform navigation, CLI fixture equality, keyboard focus, both-axis Back scroll restoration, modal dismissal, themes, five widths from 320 to 1440 pixels, no external/device/API calls, no browser persistence and deliberately missing-image recovery on a separate page. Browser checks are Chromium evidence, not physical Safari, WCAG certification or APNs delivery acceptance.

The original October 25, 2026 publication passed 112 unit tests, 186 local browser checks and 187 public browser checks. Its strict 40-response audit retained nine mismatches on two denied paths. The subsequent React-entry implementation adds 22 route tests and a real Apache fixture. Current publication and audit results are in `../docs/WEBSITE-REACT-ENTRY.md`, not inferred from the original receipts.

The earlier claim that site-level changes could not fix those responses was too broad. Reversible live rewrite probes showed that routing the inherited internal error-document request to the React entry applies the site headers without losing 403. React itself does not set HTTP headers. No administrator include or weaker access control is needed for this verified fix. The old receipts and corrected inference remain in `../docs/WEBSITE-HOST-HEADERS.md`.

### One React entry, status-preserving routes

`/` and `/index.html` retain the original homepage. `/demo` and `/demo/mac`, `/demo/iphone`, `/demo/terminal` internally serve that same entry and select the corresponding preview without changing the address bar. Unknown public pages show a generic, non-indexable recovery view with real 404. Protected-file denials remain 403. API, private, source and static-asset namespaces are excluded from SPA error presentation. Existing files, directory denials and service behavior remain intact.

To test actual Apache responses, build first, then run from the repository root:

```sh
python3.12 -B Server/tests/react_entry_test.py
python3.12 -B Server/tests/react_entry_test.py --serve
# In another terminal, from website/:
node Tools/run-route-acceptance.mjs http://127.0.0.1:4175
# After authorized publication:
node Tools/run-route-acceptance.mjs https://hashfleet.app
```

The route browser checks use the actual five server headers with no response interception or injected CSP, verify selected previews, real 403/404 statuses, keyboard recovery, 320px layout and absence of API calls or persistence. The isolated Apache fixture removes only the unchanged HTTPS redirect for loopback HTTP. Public acceptance verifies the real HTTPS site separately. The original strict HTTP audit is not relaxed to conceal the host's retained Git-path 403 versus its expected 404.

The React-entry update was published at 05:55 UTC on October 25, 2026. Its 134 unit tests, 126 local and 126 public route-browser checks, 186 local and 187 public original product checks passed. The strict 40-response audit now confirms every intended header and all 31 exact build responses. Only `/.git/config: HTTP 403, expected 404` remains, with the file still blocked. Private state and service behavior were preserved. The exact backup, archive and receipts are recorded in `../docs/WEBSITE-REACT-ENTRY.md`.

### Capture provenance

`src/lib/native-captures.json` records source PNG, published WebP and decoded RGBA SHA-256, full dimensions and byte counts. Reviewed source PNGs remain in private local task evidence, not the website. With those screenshots available:

```sh
python3.12 -B Tools/prepare-native-captures.py --source /path/to/reviewed/native-pngs --verify
```

The tool requires ImageMagick. Preparing new lossless derivatives also requires `cwebp`. It compares exact decoded 8-bit RGBA bytes and never repaints or rearranges app content.

The separate `src/lib/watch-captures.json` preserves all five original Watch PNG hashes and dimensions, tied to native release revision `a10fec115ba3f74ceed100f023eb235d4a009cd1`. `Tools/prepare-watch-captures.py --source /path/to/native-watch-attachments --verify` checks exact source/public byte identity. No image model was needed: genuine app captures already existed. CSS supplies only the decorative Watch case and strap. Captured times, sample-data notices, stale/empty labels and app pixels are unchanged. The local Watch suite checks real served bytes, tour controls, keyboard/focus, both themes at 320/390/768/1024/1440px, reduced motion and a separate deliberately invalid-image fixture. Public normal-operation checks do not intercept responses.

The Watch tour is selected through the hero or Apple Watch tab. It does not add a new `/demo/watch` server route or alter the existing route/security policy.

`Tools/capture-cli-fixtures.py` runs a supplied actual CLI binary against synthetic HTTP fixtures bound only to `127.0.0.1`. It requires exactly fifteen read-only info requests (three plain and two colored status runs) and normalizes ephemeral host addresses, UUIDs and timestamps as disclosed in `src/lib/cli-captures.json`. It never loads the configured fleet or uses discovery. Run `python3 Tools/capture-cli-fixtures.py /path/to/hashfleet` to recapture. `python3 Tools/capture-cli-dashboard.py /path/to/hashfleet` records the interactive views from the network-free native `watch --demo` mode. Both manifests include the binary SHA-256; ANSI SGR is rendered as React text/style spans, never executable HTML. The dashboard capture is loaded only when an interactive command runs.

## Existing-host publication

The original site was restored to the user's existing authorized host on October 25, 2026 UTC, and the product-parity update was published at approximately 05:00:31 UTC that day. Earlier IONOS/TLS observations in the historical acceptance document are not current hosting instructions. Publication status and receipts are in `../docs/WEBSITE-PRODUCT-PARITY.md`.

Use the verified existing `~/hashfleet.app/` document root only. Do not change DNS, sibling sites or hosting contracts. The tested allowlisted packaging and atomic backup/rollback workflow is documented in `../Server/README.md`:

```sh
python3.12 -B ../Server/tools/build_bundle.py --output /private/scratch/fresh-hashfleet-package
```

That package includes the existing API and private service files. Before promotion, verify those entries equal the already-deployed bytes. The installer preserves private configuration and SQLite data, makes a private overwritten-file backup and never deletes unrelated files. Verify configuration/database/crontab and service hashes before and after, then check public artifact bytes, security headers and all three demos. No sending cron, APNs key, notification send or release activation is part of website publication.

For a frontend-only update, do not install that full package when private/backend bytes differ. Use a narrow, exact-digest publisher with a private original-index backup, new static assets first, and the new index last. Keep previous hashed assets for rollback. Verify all unrelated public files and protected service/configuration hashes and permissions are unchanged. The Watch website delivery is recorded in `../docs/WEBSITE-APPLE-WATCH-2026-11-04.md`. App Store release settings are outside website publication and are not changed by it.

## Release links and privacy

Only set verified public HTTPS destinations in ignored `.env.local`: `VITE_MAC_DOWNLOAD_URL`, `VITE_IOS_DOWNLOAD_URL` and `VITE_SOURCE_URL`. Rebuild afterward. Invalid, non-HTTPS or credential-bearing values are ignored. Until actual public releases are configured, the page says **Coming soon**. A domain or capture does not prove release availability.

All `VITE_` inputs are public. Never include passwords, tokens, wallets, keys, real LAN endpoints or raw private responses. The site has no analytics, account forms, advertising, cookies or persisted demo choices. Hosting request logs follow the provider's policy. Optional native push settings and their activation gates remain separate from this website.
