# Clean local Mac reinstall, November 1, 2026

The operator authorized removing old Hash Fleet app copies and starting with one current installation at 19:19:48 UTC. This was an app reinstall, not permission to reset mining hardware or erase saved fleet data.

## Delivered

- Built source `bf1b1ee` using `Scripts/package-hashfleet-mac.sh`, Release `HashFleetMac`, then installed with `Scripts/install-hashfleet-mac.sh`.
- Canonical installed app: `/Applications/Hash Fleet.app`, native bundle ID `app.hashfleet.mac`. The bundled CLI link is `~/bin/hashfleet`.
- The previous installed app used `org.axefleet.mac`. The current app domain already contained all four real ASICs. Both domains' preferences and databases were backed up with matching source/copy database SHA-256 checks. No UUID replacement, history merge, keychain deletion or device deletion occurred.
- Ten generated native Mac build/package app bundles and four superseded installed/backup bundles were moved to reversibly named retired copies under Trash. Three older bundles had `.app.backup.*` or `.app.rejected-ui-update-*` suffixes, so they survived a search limited to `*.app` and caused the four visible Applications entries. The final Applications inventory must match `*hash*fleet*`, not just `*.app`. Source, test result bundles, historical records, iOS artifacts and sandbox data were not deleted. Targeted unregister operations addressed only Hash/Axe Fleet build paths. No global LaunchServices reset was performed.
- Closed the old local simulator UI-test app. The only remaining normal Hash Fleet application process runs from the canonical installed path without demo/testing arguments.

## Actual acceptance

- Native validators and complete package/install commands succeeded.
- At 19:32:20 UTC, actual screen OCR showed Overview, `Miners (4)`, all four real ASIC addresses, four miner cards and `4 of 4 online` in the installed app, not a demo.
- Actual installed native application menu contains `Support Hash Fleet…`.
- At 19:36:10 UTC, invoking that menu returned the actual window title `Support Hash Fleet`. No checkout or payment action was invoked for this acceptance.
- All eight read-only ASIC info/log requests completed HTTP 200 in the 19:24:44-19:24:50 UTC preflight. M1 SSH and exact-name XMRig PID 52840 reads succeeded, but its documented loopback API refused connection, so current CPU rate/shares/paused state were not established. The app's visible four-device inventory is ASIC-only. M1 was checked separately and no service was changed.

Owner-private package logs, data backups, sanitized all-five observations and reversible cleanup manifests are under `~/.jcode/scratch/hashfleet-clean-20261101/`. No miner POST/PATCH, firmware/self-test/restart, tuning/fan/pool/wiring/protection change, lockout clear or expanded recovery permission was performed. Current dated hardware observations are recorded in the canonical fleet operations playbook.
