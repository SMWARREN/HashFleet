# Terminal guide

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
unavailable message. See [PayPal support setup](PAYPAL-SUPPORT.md).

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

The UI tests use isolated preferences, demo data, and an in-process HTTP fixture bound only to `127.0.0.1`. They do not contact real miners. Use loopback fixtures and mocks for testing. Do not run mutation tests against physical miners without explicit permission.

