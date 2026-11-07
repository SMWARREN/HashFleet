# HashFleet

**Your hash. Your hardware.** A native, open-source macOS, iPhone, iPad and Apple Watch companion for miners running [ESP-Miner / AxeOS](https://github.com/bitaxeorg/ESP-Miner).

SwiftUI, Apple Charts, Swift concurrency, and Foundation, with Lucide icons and GRDB local storage. No HashFleet account, subscriptions, analytics, or firmware modifications. Optional public HTTPS services provide chain and pool statistics with a local-only opt-out.

## What it does

- Monitor multiple miners by IP address, hostname, or `.local` address.
- Open the independent Apple Watch app to read a Watch-local fleet directly over reachable Wi-Fi, even with the iPhone off. Cached readings keep their original timestamps. See [Watch setup and limits](docs/WATCHOS.md).
- See fleet hashrate and power, individual temperatures, fan speed, accepted/rejected shares, uptime, and firmware information.
- Keep read-only miner readings live while Fleet is open, or use an HTTP snapshot on open and pull-to-refresh when Realtime miner readings are disabled. Sort your fleet, search locally and switch to compact cards in Settings → Fleet preferences.
- Access firmware operations through native miner tools, including the advanced endpoint explorer. See [API coverage](docs/API-COVERAGE.md) for the exact operation inventory and version caveats.
- Inspect statistics, ASIC data, scoreboard, Wi-Fi scans, and raw responses. Download logs, stream logs/live updates, edit settings/pool slots, and upload firmware or custom web UI binaries.
- Confirm device-changing operations before sending. Demo mode is explicitly labeled, uses sample data, and never contacts miners.
- A valid Info poll automatically checks ASIC once per device/firmware identity. Tap a miner → **Check compatibility** to retry, with separate support/error results and a timestamp. Unknown models are accepted based on reported fields, not a model whitelist. Missing fields are labeled rather than invented, and ASIC options are device-reported references, never safe overclock presets.
- See reported pause, thermal/power/hardware faults and fallback-pool notices without opening raw JSON. Partial telemetry is labeled as a subtotal or Not reported, not fabricated zero readings.
- Inspect supported firmware's per-ASIC domain rates, foreground sparklines and nominal references, plus safe pool error/banner and configured-transport details. Choose **Notifications**, **Session best**, or **Both** in the activity popup and dashboard menu. Notifications is the display default, and session-best alerts have their own off switch. See [firmware telemetry and activity](docs/FIRMWARE-TELEMETRY-ACTIVITY.md).
- Add small/medium Home Screen widgets and Lock Screen accessories after opting into aggregate snapshot sharing in Settings. Cached readings become stale after a minute.
- On macOS, one native app owns both the workspace and the menu-bar status item, sharing the same fleet store. Closing the window keeps the app running; Quit stops both surfaces. No separate companion or LaunchAgent is required. See [native Mac installation](docs/MAC-NATIVE-INSTALL.md).
- Find compatible miners with an explicit, bounded read-only Wi-Fi scan. Manual address entry remains available as a fallback.
- Start and end a local Live Activity for your Lock Screen and Dynamic Island. Updates are foreground-only, with no push server or background polling claim.
- Review native clock/core-voltage drafts, cooling, display, hostname and pool changes. Manual tuning has additional risk acknowledgment, no automatic overclock presets, and does not disable thermal protection.
- Match useful AxeOS Swarm edit controls, including on-device statistics logging and automatic-mode minimum fan speed. Firmware logging is separate from the app's optional live connection. See the [source-backed settings comparison](docs/SWARM-SETTINGS-PARITY.md) for intentionally advanced hardware-only fields.
- Store your fleet locally, with no pool or Wi-Fi credentials saved by the app. Advanced response views and exported logs may contain sensitive device information.

This directory is a **sanitized source snapshot**, not a signed app or a TestFlight delivery package. See [public source preparation](docs/PUBLIC-SOURCE-PREPARATION.md) for the exclusions, documentation placeholders, and validation limits. Historical read-only monitoring observations against two BM1370 miners (602 and 601a) are not a complete firmware/hardware compatibility matrix. Older firmware may return 404 for newer operations.

## Run on your iPhone

Requirements: a Mac with Xcode and SDKs supporting the deployment targets declared in `project.yml` and `Package.swift` (Swift 6, iOS 17+, macOS 14+, and watchOS 26.5 for the Watch targets). Historical October 24, 2026 checks used Xcode 27.1. Xcode resolves the packages declared in those manifests; this sanitized snapshot has not had a fresh app build or device test.

1. Open `HashFleet.xcodeproj` in Xcode. The project is included for convenience.
2. Select the **HashFleet** application target, then **Signing & Capabilities**. Choose your own development team and a unique bundle identifier.
   Also configure the embedded **HashFleetWidgets** target and a shared App Group. Read [widget setup](docs/WIDGETS.md) for matching identifiers and the no-App-Group fallback for teams that cannot provision this capability.
   The embedded **HashFleetWatch** target must use the same team, an identifier prefixed by the iOS app identifier, and the matching `WKCompanionAppBundleIdentifier`. See [Watch setup](docs/WATCHOS.md) before changing the identifiers.
   To retain your team across project regeneration without publishing it, create an ignored `Signing.local.xcconfig` containing `DEVELOPMENT_TEAM = YOUR_TEAM_ID`. The included `Signing.xcconfig` loads this optional local override.
3. Select your iPhone and run. A free personal Apple account can run development builds subject to Apple's provisioning limits, but may not support the App Group needed for widget sharing.
4. Allow the local-network permission prompt. Put your phone on the same network as the miners.
5. Tap **Add miner**, optionally choose **Scan nearby miners**, or enter `192.168.1.42`, `bitaxe.local`, or `http://bitaxe.local:80` manually. Addresses must not contain a path, credentials, query, or fragment.

You can explore the sample fleet without a miner. Leaving demo mode restores your saved real fleet.

### Generate and build from the command line

The Xcode project is generated from `project.yml` using [XcodeGen](https://github.com/yonaskolb/XcodeGen). Regenerate it after adding app/test files:

```sh
brew install xcodegen # only needed for project generation
xcodegen generate
xcodebuild -project HashFleet.xcodeproj -scheme HashFleet \
  -destination 'generic/platform=iOS Simulator' \
  -derivedDataPath build CODE_SIGNING_ALLOWED=NO build
swift test
```

Use a booted iOS simulator to inspect the app. Launch with the `--demo` argument to display fixtures without network access.

### Build and install the native Mac app

`HashFleetMac` is a genuine macOS SwiftUI/AppKit target, not Catalyst or a Designed-for-iPad wrapper.
The workspace and menu bar run in one executable. The iOS target disables Mac installation;
run iPad builds inside the iOS simulator when developing on a Mac.

```sh
Scripts/package-hashfleet-mac.sh
Scripts/install-hashfleet-mac.sh
```

The installer places `Hash Fleet.app` in `/Applications` and links the CLI
bundled at `Hash Fleet.app/Contents/MacOS/hashfleet` into `~/bin/hashfleet`.
The packaging script also creates `dist/Hash Fleet.pkg`; installing that package
places the primary app in `/Applications` and its CLI at
`/usr/local/bin/hashfleet` in one operation. Set
`HASH_FLEET_INSTALLER_IDENTITY` only when using an existing approved installer identity.
Local ad-hoc app signing and an unsigned PKG are not a notarized public release.
See [native Mac installation](docs/MAC-NATIVE-INSTALL.md) for validation, rollback and signing boundaries.
The old companion installer refuses new installations and remains available only for status/render/uninstall of legacy jobs.

### Terminal dashboard

Press **Shift+S** in the dashboard, miner details, or logo view to open **Support Hash Fleet**
without leaving the interactive CLI. It shows the optional PayPal developer-tip checkout
and the same approved **BTC (Bitcoin mainnet), ETH (Ethereum mainnet), and SOL (Solana mainnet)**
receiving destinations as the native apps and website. Use **↑/↓** or **j/k** to scroll,
**g/G** for top/end, **S**, **b**, or **Escape** to return to the previous view, and **q**
or **Ctrl+C** to quit. Long addresses wrap without being truncated. New dashboard polls
pause while this read-only page is open. No browser, wallet, clipboard, or payment action
is triggered by viewing it. Support destinations are real, including in demo mode.

`hashfleet support` prints that same PayPal and crypto information into normal scrollback
when a verified PayPal link is configured. It never opens a browser, contacts miners, or submits payment.
Until the recipient's checkout is configured, it exits with status 69 and an explicit
unavailable message. See [PayPal support setup](docs/PAYPAL-SUPPORT.md).

Run `hashfleet` (or `~/bin/hashfleet` when using the local installer), or run
`swift run hashfleet` from this repository, to open the live dashboard. It refreshes every five seconds after
the previous poll finishes and adapts to the terminal size, including narrow split
panes. Fleet totals identify partial readings as subtotals; offline miners stay visible.

Use **↑/↓** or **j/k** to select a miner, **d** or **Enter** for details, **e** for settings, **s** to sort
by name/hashrate/temperature, **Space** to pause, **r** to refresh, **l** to view the
larger logo, and **q** or
**Ctrl+C** to exit, and **Shift+S** to view Support. A manual refresh works while paused. Quitting restores the
terminal and cancels pending reads.

The dedicated miner page has **1 Overview**, **2 Mining**, **3 Hardware**, and
**4 Pool** sections. **Tab** changes section, **↑/↓** or **j/k** scrolls, **←/→**
changes miner, and **d**, **b**, or **Escape** returns to the fleet. Colored values
show current/averaged hashrate, share counters and records, efficiency, cooling,
clock/voltage readings, and the reported active pool. A bounded trend retains the
last 60 checks in this CLI session, with gaps for missing readings. Missing fields
remain unavailable; measured clock and voltage are never substituted with settings.
Pool notices appear only when supplied by the miner and may describe an earlier
preferred-pool attempt. Routine transport diagnostics and empty error fields are
omitted. The same read-only sections are available in `status --details`; JSON stays
unchanged. These views do not send hardware commands or fetch public pool accounts.

Press **e** to edit the selected ESP-Miner, or open it directly with
`hashfleet settings <miner-host>`. **1–5** or **Tab** changes section; **↑/↓** selects a
field and **Enter** edits it. **Ctrl+U** clears the input, **Enter** stages a value,
and **u** undoes the selected field. **r** reviews the changed values for that
specific miner; type **APPLY** and press **Enter** to send them. **Escape** goes back.
The editor includes hostname, on-device history interval, cooling, frequency/core
voltage, and display settings. In **5 Pools**, edit host, port, worker/wallet,
password and protocol. On modern firmware, **[** and **]** select a configured
slot by its persistent ID; Primary slot and Backup slot change its routing roles.
Legacy firmware uses the primary/backup fields instead. Passwords remain masked
and unchanged by default; entering an empty replacement explicitly clears one.

Modern pool updates preserve the complete reported TLS, certificate, difficulty,
extranonce, coinbase and SV2 configuration in each edited slot. Unedited slots are
omitted from the request. A missing, unfamiliar or malformed slot configuration
blocks the edit instead of resetting unreported options. New slot creation still
uses the miner's interface. Requests exceeding the firmware's 10 KiB body limit
must be reduced to fewer slots; certificates are never truncated.

Editing pauses dashboard polling. Apply reads fresh settings first, rejects changes
that conflict with another client's edits, sends the reviewed request once, then
reads settings again to verify both changes and preserved pool options. Pool changes
can reconnect mining. Password replacements are accepted but cannot be verified
because firmware hides their values. Accepted but unverified writes remain
explicitly unverified and are never retried automatically. Demo/offline miners and
XMRig are not writable here. Firmware input bounds and the app's Gamma 601a
1150 mV ceiling are enforced; clock/cooling changes are reviewed without resetting
thermal protection or automatically restarting the miner.

The original Hash Fleet image is converted to colored terminal block characters,
preserving the fan blades, gold casing, and display. It scales with the available
space; shallow panes keep a compact wordmark and provide the larger artwork through
**l**. Run `hashfleet logo` to print the same image-based logo into normal scrollback
without contacting miners. Gold branding, a bronze selection highlight, and green/red status colors use
true color when advertised by the terminal, with 256-color and basic ANSI fallbacks.
`NO_COLOR=1` uses a monochrome ASCII conversion of the same image. The pixel data is
compiled into the CLI, with no runtime image dependency. Regenerate it from the
checked-in brand image using `python3 Scripts/generate-cli-logo.py` with Pillow installed.

```sh
hashfleet watch gamma.local naja.local
hashfleet watch --interval 10
hashfleet watch --demo
hashfleet status
hashfleet status --details
hashfleet status --json gamma.local
hashfleet settings gamma.local
hashfleet logo
```

`status` shows the image-converted logo, colored miner states and readings, and a
layout that fits the terminal width. It prints a single snapshot into normal
scrollback, including in shallow panes. Redirected output stays plain, JSON stays
unchanged, and `NO_COLOR=1` disables styling while retaining the ASCII logo.
Redirected output defaults to status mode.
`watch` requires an interactive terminal; `--interval` accepts 5–3600 seconds.
`--demo` uses explicitly labeled samples without reading the fleet store or contacting
miners. With no explicit hosts, the CLI uses its legacy shared fleet configuration;
if that store is unconfigured, it discovers miners once when the session starts.
Subsequent dashboard refreshes poll only those discovered hosts. A corrupt store
does not trigger discovery. Viewing and refreshing are read-only; settings writes
require the explicit APPLY step in the selected miner's editor.

CLI acceptance checks use loopback fixtures and a real pseudo-terminal:

```sh
swift build --product hashfleet
python3 -B Scripts/tests/test_cli_firmware_activity.py --binary "$(swift build --show-bin-path)/hashfleet"
python3 -B Scripts/tests/test_cli_dashboard.py --binary "$(swift build --show-bin-path)/hashfleet"
python3 -B Scripts/tests/test_cli_settings.py --binary "$(swift build --show-bin-path)/hashfleet"
python3 -B Scripts/tests/test_cli_interactive_support.py --binary "$(swift build --show-bin-path)/hashfleet"
```

Run the native state, safety, and UI suites by replacing `SIMULATOR_UUID` with a device from `xcrun simctl list devices available`:

```sh
xcodebuild -project HashFleet.xcodeproj -scheme HashFleet \
  -destination 'platform=iOS Simulator,id=SIMULATOR_UUID' \
  -derivedDataPath build -parallel-testing-enabled NO CODE_SIGNING_ALLOWED=NO test
```

The UI tests use isolated preferences, demo data, and an in-process HTTP fixture bound only to `127.0.0.1`. They do not contact real miners. See [core validation](docs/VALIDATION.md) and [native app validation](docs/APP-VALIDATION.md) for evidence and untested boundaries.

## Firmware compatibility and safety

The API was audited against ESP-Miner master commit `2943d206f6c8a4b249bc74c820fb56c874ac316d` on September 6, 2026. The bundled upstream [OpenAPI document](docs/esp-miner-openapi.yaml) is a reference, not the sole source of truth. Some registrations are missing from the schema, while the README also mentions a historical dashboard-statistics endpoint. The coverage document explains these differences.

The [second source audit](docs/SECOND-FIRMWARE-AUDIT.md) and [model matrix](docs/MODEL-CAPABILITY-MATRIX.md) distinguish chip identity from board configuration. A manual Info/ASIC check treats HTTP 404, 405 and 501 as an unavailable operation. Access errors, timeouts, server errors and unrecognized responses mean **Could not check**, not unsupported hardware. Recognition is a compatibility heuristic, not authentication or proof that every field can be written. Results are in-memory and dated. Ordinary monitoring polls Info and performs one additional ASIC read per newly detected identity. Failures back off until explicit retry or identity change. No other endpoints are scanned automatically.

ESP-Miner generally exposes an **unauthenticated, plaintext local HTTP API**. This app is an operator tool, not a security boundary. Never port-forward miners to the internet. For remote access, use a trusted VPN to your home network. HTTP access is declared in the app's transport-security configuration because many miners do not serve HTTPS.

**Changing voltages/frequency or uploading the wrong firmware can damage hardware or make it inaccessible.** Back up your settings, verify your board revision and firmware source, and keep power stable. The app sends the binary you explicitly choose. It does not verify signatures, board compatibility, or upgrade safety. A completed HTTP request is not proof that the device successfully rebooted into the new firmware.

Pool edits, mining pause/resume, restarts, boot configuration, and other controls can interrupt mining. Advanced settings let you use the firmware's full payload surface and require you to understand those fields. This app does not automatically apply configuration suggestions.

## Limitations

- Continuous background polling is not available on iOS. Hash Fleet schedules best-effort background checks, persists detected alerts, and replays them in-app when opened; iOS may delay or skip those checks.
- Widgets and Live Activities display timestamps and stale state. They do not keep mining telemetry live while the app is suspended. iOS controls widget refresh and Activity lifetime.
- Charts retain the latest 360 successful observations per miner in memory, about an hour at the usual refresh interval. They reset when the app exits or demo mode changes. Firmware statistics require data logging to be enabled on the device.
- Wi-Fi discovery is opt-in and currently probes one bounded private/link-local /24 over `GET /api/system/info`; Bonjour discovery is not included until a firmware service type is verified. An empty scan does not prove local-network permission was denied.
- APIs vary between firmware versions and boards. HTTP errors are presented, not treated as successful operations. New endpoints require catalog updates.
- No physical miner has been used for write/OTA verification. Never test destructive actions on hardware you cannot recover.
- There is no published app repository URL or signed distribution configured yet. This folder is ready to publish under the included license.

## Project layout

```text
App/                    SwiftUI app, fleet store, screens, assets
AppTests/               Native fleet-state and controls-safety tests
MacApp/                 Native macOS workspace, in-process menu bar and lifecycle
MacAppTests/            Native lifecycle and PDF export acceptance
MacMenuBar/             Retired companion source retained for historical reference
Scripts/                Reproducible local delivery helpers
UITests/                Simulator navigation, loopback controls and ActivityKit acceptance
Shared/                 Aggregate-only widget snapshots and Activity attributes
Widgets/                WidgetKit and Live Activity extension
Sources/HashFleetCore/   Dependency-free API client, endpoint catalog, JSON types
Tests/                 Swift package tests with mocked networking
docs/                  Firmware API reference, coverage, validation notes
project.yml            Reproducible XcodeGen project definition
```

See [CONTRIBUTING.md](CONTRIBUTING.md), [SECURITY.md](SECURITY.md), and [PRIVACY.md](PRIVACY.md).

To create a shareable source-only ZIP and checksum from a clean commit, run `bash Tools/package-source.sh 0.1.0`. See [release preparation](docs/RELEASING.md). This does not upload anything. Audit committed contents before sharing, since already tracked private files would also be archived.

## License and attribution

GPL-3.0, see [LICENSE](LICENSE). The vendored ESP-Miner API specification is from the GPL-3.0 ESP-Miner project and retains its upstream attribution. HashFleet is an independent community project and is not affiliated with or endorsed by Bitaxe, ESP-Miner, or OSMU.

## Public chains and configured pools

Home now shows best-ever/session share difficulty, separate BTC/BCH price, difficulty and 30-day solo chance comparisons, and configured pool/account statistics. Mempool and full source details are one tap away, not another top-level tab. Known CKPool and SoloFury BTC/BCH/BC2/BCH2/XEC slots are recognized by exact hosts. Unknown pools remain visible without invented coin support.

Public data refreshes at most once per minute per configured account while the home screen is active. Providers see your internet IP and public payout address for account queries, never the worker suffix, local miner IP or pool password. Addresses are held only in memory. **Settings → Fleet preferences → Show external data** disables these requests. Demo always uses labeled offline samples.

Native solo-pool presets prepare a local slot draft with verified host and port. New slots do not automatically become primary or fallback. A different preset clears the old wallet draft. Full-slot replacement acknowledgement, exact JSON review and confirmation remain mandatory before any miner write.

See [third audit](docs/THIRD-FIRMWARE-AUDIT.md), [public data sources](docs/PUBLIC-DATA-SOURCES.md) and [expansion acceptance](docs/EXPANSION-ACCEPTANCE.md). No multi-vendor, solar, remote gateway, Watch or automatic profit-switching support is implied.
