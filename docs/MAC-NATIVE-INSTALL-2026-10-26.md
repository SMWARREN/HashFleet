# Native Mac installation and real monitoring, October 26, 2026

## Authorization and scope

- At 03:40 UTC the operator requested opening the newest staged preview.
- The exact navigation0119 preview was opened as PID61362 with isolated Demo/test flags. Its saved 03:41 AX receipt shows a 1280x860 normal Overview window, centered Hash Fleet title and a 44x44 settings Menu target.
- At 03:43:29 UTC the operator said the launched Mac app looked good. This approves that observed appearance, not every page or transition.
- At 03:47:20 UTC the operator authorized **both** installing the approved native build and connecting real fleet data. No miner settings, restart, OTA, self-test, pool, fan, power, wiring or recovery-policy change was authorized or performed.
- The operator wants one client and functional portion at a time. This operation accepts installation and sampled real ASIC monitoring only.

## Backups and artifact provenance

The fresh audit found no Hash Fleet or HashFleet app at the default system/user Applications locations and no running legacy menu helper or corresponding LaunchAgent. Earlier installation descriptions are historical, not evidence that those bundles still existed. The only app process was the exact isolated preview PID61362, which was stopped after checking its full executable path and flags.

Owner-private operation root: `~/.jcode/scratch/hashfleet-official-20261026-0347/`.

`pre-install-backup/manifest.json` records **117 checksummed files, 1,031,607,718 bytes**, including legacy and native preferences, history and shared/legacy helper preferences. The copied SQLite database passes `quick_check`. The source files were rehashed after copying and again at final acceptance, with no source change. No Keychain secrets were exported. The old dangling `~/bin/hashfleet` symlink was moved, not deleted, into this backup before the unchanged installer ran.

The existing migration tool passed **13 offline tests**; package/install tests passed **16 tests**. Its read-only dry run and apps-stopped execution copied only allowlisted preferences and the **1,031,479,296-byte** history database into the existing native sandbox. Destination backups and rollback receipts remain in `migration-rollback/`. Staged and destination SQLite integrity checks passed. Immediately after migration, all four original device UUIDs and addresses matched the legacy source.

The approved UI implementation is `3e66594`, with prior evidence commit `78234d4`. The reviewed executable SHA-256 was `29d6cdb527948618ef004087b50074ab3fc048030ace754dcafe2fc8a0eadf64`. Its review signature had no entitlements. A separate scratch copy was therefore signed with the repository's production entitlements before the prebuilt packaging path was used:

- `com.apple.security.app-sandbox = true`
- `com.apple.security.network.client = true`
- `com.apple.security.files.user-selected.read-write = true`

The packaging script compiled the release CLI, signed it separately, then resealed the host while preserving those entitlements. No UI source was changed or rebuilt for installation. Both the reviewed and installed main executables have Mach-O UUID `049B78E7-52E4-3C46-9A46-4FDCE80C1FC6`. The changed installed executable hash reflects re-signing, not a new claimed UI revision:

- Main executable: `d5c4ad0d35f16a5460dd5382857730210b96a9ead1476b3a9a4b188cc05a8275`.
- Bundled CLI: `e64631888ffe00fbe15053fc1075fe36cfbaa2d73aff407b4ef67b862800e797`.

The unchanged native validator passed for source, package, install staging and installed bundle. The actual resulting signature was inspected and retains all three entitlements. The installed app is `app.hashfleet.mac`, genuine macOS rather than Catalyst or a Designed-for-iPad wrapper. The new CLI link targets `/Applications/Hash Fleet.app/Contents/MacOS/hashfleet`, and its actual help command succeeds. This is a **local ad-hoc signed installation**, not notarized public distribution or an App Store release.

## Production launch and monitoring

At **03:59:35 UTC** the installed app opened as **PID70586** from `/Applications/Hash Fleet.app/Contents/MacOS/Hash Fleet`, with no arguments. Its actual working directory and open history database are in `~/Library/Containers/app.hashfleet.mac/Data`. No duplicate Hash Fleet process or legacy helper was running at final acceptance.

The first production launch unexpectedly restored a fullscreen workspace. A target-PID AX request set the workspace's fullscreen attribute false to avoid display takeover. The follow-up lookup failed after the transition, so that call is not treated as a passing window-state receipt. The later WindowServer observation shows the app back in Stage Manager while Chrome is foreground. No repeated activation, route selection, menu opening or full-display screenshot was forced. A window-only capture at 04:04 UTC is a 230x300 Stage Manager thumbnail, not a full-size visual acceptance image. A separate no-activation menu AX read timed out and does not establish an unresponsive app or a passing status-item review.

Independent complete fleet captures ran at **03:56:37-03:56:43 UTC** and **04:05:19-04:05:24 UTC**. Each fetched all four ASIC `/api/system/info` and `/api/system/logs` endpoints with HTTP200, plus documented M1 SSH/XMRig/process/LaunchAgent reads. Raw responses remain private because they can contain pool credentials or wallet data.

| Member | Closing 10m TH/s | Chip(s) / VR C | Accepted / rejected | MHz / set mV |
| --- | ---: | --- | --- | --- |
| Gamma 602 (.215, 5 V only) | 1.529 | 59.125 / 54 | 647 / 0 | 750 / 1135 |
| Gamma 601a (.221, 12 V) | 1.121 | 51.125 / 40 | 3379 / 0 | 550 / 1100 |
| Original Naja (.226, 12 V) | 10.153 | 45.746 / 51.509 / 67 | 29645 / 6 | 735 / 1160 |
| Naja Duo 2 (.232, 12 V) | 9.536 | 50.432 / 54.994 / 64 | 19729 / 4 | 690 / 1155 |

All four still report `v2.15.2rc0-59-gd8511a14`, unchanged frequency/set voltage, advancing uptime and accepted work, `miningPaused=false` and `overheat_mode=0`. Closing reported ASIC sum is approximately **22.339 TH/s / 285.81 W**, not pool-calibrated throughput or outlet power. This monitoring check did not independently validate every domain or prove long-term stability.

The tracked M1 independently runs **XMRig 6.26.0, PID52840**, unpaused, with approximately **2.091 kH/s over 60s**, **13729 good / 13731 submitted**, two more accepted shares than the opening capture. Its API listens only at `127.0.0.1:18088` on that host. It is **not** present in the four-ASIC app inventory, and no remote API exposure, SSH forwarding service, XMRig configuration change or mining-service restart was introduced. The observed recorder LaunchAgent's last exit status is1, not an all-services-healthy claim.

The final read-only verifier at **04:06:45 UTC** passed **53/53 scoped monitoring checks**: correct installed identity and flags, one process, correct CLI link, exactly four real addresses, fresh app snapshots, multiple new database samples for each active entry, real firmware/work fields, source immutability, and the independent all-five checks. Actual app cache readings were approximately six seconds old. The current four entries had 670-709 samples each during the preceding six-minute window. These are real production reads, not a Demo result or an app-hosted UI test run.

## Explicit remaining gates

1. **History identity continuity is unresolved.** After production launch, all four current entries have different UUIDs from the immediately migrated list, although addresses/names match. The cause and any external interaction are not established. The decoder itself preserves encoded UUIDs. The original database is unchanged, and its copied legacy rows remain: 1,574,766 for the saved 602, 1,135,337 for 601a, 1,390,135 for original Naja and 902,868 for Duo 2. This does not prove that current per-device history views associate those old rows correctly. No destructive history rewrite, UUID reassignment or hidden acceptance waiver was performed. Investigate and verify this as the next Mac portion before declaring complete data migration or the whole Mac app good.
2. The M1 is verified separately, not integrated into this four-ASIC UI. Any app integration must preserve its loopback-only API safety boundary.
3. Current-source opened menus/status popover, full maximize/minimize/fullscreen transition matrix, additional Mac routes and operator functional acceptance remain separate. Earlier runtime test passes retain their original binary attribution.
4. iPad, phone, widget and other clients are not newly accepted by this installation. Test them sequentially after the chosen Mac portions.

Private receipts include `backup-result.json`, `package.log`, `install.log`, migration logs, `live-baseline/`, `live-closing/` and `monitoring-acceptance.json`. No raw fleet payload, secret or database is committed.
