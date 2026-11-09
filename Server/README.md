# Hash Fleet notifications service

Standard APNs provides scheduled, metadata-only check alerts. This service stores explicit per-installation schedules and submits due generic alerts to APNs. It does not accept miner readings, connect to a user's LAN, or claim instant block-found detection. The bundled iOS notification service extension can attempt a short read-only LAN check when Apple delivers an alert. The complete wire contract is in `docs/APNS-REPLACEMENT-CONTRACT.md`.

## Private deployment layout

Only deploy to the verified Hash Fleet site. Do not touch sibling websites or use `rsync --delete`.

```text
~/hashfleet.app/                  Existing Apache document root
  index.html, assets/, images/, .htaccess   Original website/ production build
  app.js, style.css, companion/index.html Inert retirement compatibility files
  api/v1.php
~/hashfleet-private/              Mode 700, outside every public document root
  Service.php, APNs.php, dispatch.php, config.example.php
  config.php                     Mode 600, never committed or replaced on redeploy
  hashfleet.sqlite               Mode 600, not a public download
  dispatch.lock, apns-jwt.json    Private runtime files
  backups/                       Scoped overwritten-file backups and deployment receipts
```

The API defaults to the sibling `hashfleet-private` directory. `HASHFLEET_PRIVATE` may override that path only through trusted server configuration. PHP 8.4 with PDO SQLite, OpenSSL, and cURL HTTP/2 is required. Apache must permit the included `.htaccess` rules and security headers. The verified host uses `/usr/local/bin/php`, not the local Mac's Homebrew path.

The site uses one React entry for its public demo routes and ordinary unavailable pages. A local error-document rewrite also applies the intended headers to the host-generated `/.env.local` and `/.git/config` responses while preserving their real 403 status. Missing assets, API and private namespaces do not become successful SPA pages. `docs/WEBSITE-REACT-ENTRY.md` records the contract and live evidence, superseding the earlier administrator-only inference in `docs/WEBSITE-HOST-HEADERS.md`. The optional `Server/apache/` include was not applied and is not required for the verified site-level fix. Do not disable a blocking rule or change global/sibling configuration to normalize error headers.

### Package, inspect, then install

```sh
python3.12 -B Server/tools/build_bundle.py --output /private/scratch/fresh-hashfleet-bundle
```

Use a fresh scratch output path. The package is an exact allowlist with SHA-256 integrity metadata. Configurations, keys, databases, and test fixtures are never included.

Upload the archive into a new mode-700 staging folder under the hosting account's home, outside the document root. Extract there, inspect the manifest, lint PHP, then run:

```sh
/usr/local/bin/php /home/USER/private-staging/install.php /home/USER
/usr/local/bin/php /home/USER/hashfleet-private/dispatch.php --check
```

The installer requires the existing `hashfleet.app` webroot, refuses symlink destinations, backs up only files it will overwrite, and uses atomic file promotion. It never deletes unrelated files or replaces existing `config.php` or SQLite data. New configuration has a random private rate-limit salt and **no APNs signing credentials**. If file promotion fails, promoted files are rolled back. Inspect and retain the private deployment backup. This is not a cross-file transactional web release, so use a controlled deployment window.

### Scheduler

This is an activation procedure, not deployment permission. Do not configure a key, install a sending cron, or send a push without explicit operator authorization. After that authorization and verification of HTTPS, API authorization, private-file denial, and `dispatch.php --check`, back up the account's current crontab privately and append only this marked line, preserving all unrelated jobs:

```cron
* * * * * /usr/local/bin/php /home/USER/hashfleet-private/dispatch.php >/dev/null 2>&1 # hashfleet-notifications
```

A nonblocking process lock prevents overlapping cron processes. SQLite transactions, unique period keys, and expiring claims also guard duplicate work. Retryable transport/429/5xx outcomes have a maximum five-claim budget, including an expired final lease after a crash. A 5xx waits at least 15 minutes. A matching-generation 410 invalidates that token, not a newly refreshed token. Other provider configuration errors do not incorrectly revoke the device. APNs acceptance is not device delivery, and an ambiguous transport failure can still result in a duplicate notification.

## Activation requires a real Apple key and signed app

1. Enable standard **Push Notifications** for `app.hashfleet` in the Apple Developer account, and use matching push-enabled development/distribution provisioning profiles. The removed Network Extension capability is not needed.
2. Obtain an authorized APNs `.p8` signing key and its 10-character Key ID and Team ID. An App Store Connect API key is not a substitute. Confirm the key covers `app.hashfleet` and the intended sandbox/production environment. Never paste a key into the website, source control, a chat response, or logs.
3. Store the key under `hashfleet-private` with mode 600. Securely edit the existing private `config.php` to set `apns.key_file`, `key_id`, and `team_id`. Keep the fixed topic `app.hashfleet` and private JWT-cache path. Do not regenerate the existing privacy salt or overwrite the database.
4. Run `dispatch.php --check`. `provider_ready: true` validates local key format, required fields, P-256 curve, permissions, and HTTP/2 support only. It is **not proof Apple accepts the key**.
5. With permission, install a correctly signed app including `app.hashfleet.notification-service` with the matching App Group. Grant the containing app Local Network and notification permission, refresh a supported private-IPv4 miner to prepare its pinned identity, and opt in using native Notifications settings. Verify matching-environment enrollment, then test an authorized alert with the phone locked on the miner's LAN and again off-LAN. Record APNs response, extension execution, local request, expiry/fallback, opt-out, and device presentation separately. No separate companion is used. The specific signed-device path and primary Mac extension runtime are not proven by simulator tests or compilation. No broad user send or release submission is implied.

The provider signs ES256 JWTs and reuses a private cached token for 50 minutes across cron invocations. Requests use fixed Apple hosts, verified TLS/HTTP/2, alert push type, priority 5, a five-minute expiration, and a stable installation/miner collapse identifier. Notifications route to miner details, not a block/session celebration.

## User behavior and privacy

- New installations are globally off. Suggested per-miner cadence is 60 minutes, with 3, 6, 12, and 24-hour choices. The existing native app's Notifications settings are the only schedule-management UI; the website is not a notification dashboard.
- The server stores only an installation credential hash, APNs token/environment, opaque miner UUIDs, notification switches, intervals, and delivery-job metadata. It accepts no miner names, LAN addresses, readings, wallets, pool passwords, Wi-Fi secrets, or raw firmware responses. Due checks do not require uploaded readings.
- Opting out disables scheduled delivery, not unrelated local app behavior. An alert already accepted by Apple may still appear. The extension attempts a bounded local read only when delivered, and reports a safe unavailable message if it cannot validate a response. No instant or exact-hour delivery is guaranteed.
- Legacy installations remain inactive until an authenticated explicit `device_check_v1` registration. That migration clears only the installation's old uploaded readings and relay credential. Old relay and telemetry endpoints are disabled.
- Terminal jobs and sanitized provider audit records expire after seven days. Inactive installations expire after 90 days. Dispatch performs retention cleanup even while the provider is unconfigured. Hosting access logs and deployment backups have their own account retention policies.
- There is no private browser connection or browser management UI. The app sends credentials only in authorization headers, never API query strings, website fragments, clipboard, analytics, cookies, or browser storage. Confirmed native deletion is installation-scoped and cascades its token, schedules, and jobs. Deployment backups do not contain the live database or `config.php`.
- HTTPS, body/count limits, exact schemas, installation authorization, salted request-rate buckets, no CORS, no third-party scripts, CSP, no-referrer and no-store headers are enforced. Hosting administrators remain trusted with the private database.

## Verification commands

```sh
php Server/tests/run.php
node Server/tests/website.cjs
python3.12 -B Server/tests/http_smoke.py --php /path/to/php --scratch /private/scratch
HASHFLEET_TEST_PHP=/path/to/php python3.12 -B Server/tests/deployment_test.py
python3.12 -B Server/tests/apache_headers_test.py
python3.12 -B Server/tests/react_entry_test.py
cd website && npm run check && npm run build
# Open a production preview on 127.0.0.1:4174 and run Tools/browser-acceptance.js
# with the existing Playwright CLI run-code --filename workflow.
```

The backend tests use real in-memory SQLite and injected APNs outcomes. HTTP smoke checks run a real PHP server on loopback only. Installer tests use temporary local home directories. `website.cjs` guards the retired dashboard endpoints, not a replacement settings product. The original website has its own unit, build, and browser acceptance. None is real APNs delivery certification. Live deployment observations and acceptance receipts belong in `docs/APNS-REPLACEMENT-ACCEPTANCE.md`.

## Operational check, November 9, 2026

At 09:53 UTC, read-only inspection found saved hourly schedules but no HashFleet
entry in the hosting account's crontab and no recorded dispatch jobs. Provider
readiness was true. These observations are dated, not an assertion of current state.
One operator-authorized test request to the recently active production installation
received APNs HTTP 200 at 09:53:48 UTC. No other installation was contacted and no
schedule was changed. Physical presentation and extension results still require
the operator's observation. The operator was given the cron setup command, but
automatic scheduling has not been verified by this receipt.

Fresh offline checks passed: 145 backend checks, 10 Retry-After cases, valid DER
conversion and five compatible rejection cases, and nine retired-endpoint checks.
The separate frontend publication did not deploy the refactored PHP backend or
change notification configuration. A future backend update requires its own
reviewed deployment and acceptance checks.

## Apple primary references

Checked October 25, 2026 UTC:
- Registering your app with APNs: https://developer.apple.com/documentation/usernotifications/registering-your-app-with-apns
- Establishing a token-based connection to APNs: https://developer.apple.com/documentation/usernotifications/establishing-a-token-based-connection-to-apns
- Sending notification requests to APNs: https://developer.apple.com/documentation/usernotifications/sending-notification-requests-to-apns
- Handling notification responses from APNs: https://developer.apple.com/documentation/usernotifications/handling-notification-responses-from-apns
