# Operator-authorized clean reset, November 6, 2026

## Scope and reason

At 15:36:08 UTC the operator explicitly requested deleting Hash Fleet and its settings to test a clean build. This authorizes deleting local Hash Fleet app copies and app-owned configuration/data. It does not authorize deleting the repository or diagnostic recordings, changing any miner, or treating an empty-state launch as proof of repair.

Application source remains the one-change candidate at `8529f5e`. No further speculative navigation changes or Git rollback were made. Frequency opened in an operator retry, but Technical details and other menu failures were subsequently reported. Those reports remain unresolved.

## Executed reset

At 15:41 UTC no Hash Fleet app process was found. The scoped reset:

- Verified the canonical/staged native bundle ID `app.hashfleet.mac` and retired Trash bundle ID `app.hashfleet` before attempting deletion.
- Removed the canonical app and prior native staged app, the active sandbox container, shared and application defaults, CLI configuration/credentials, and exact app-specific CLI links/backups. This removes saved miners, local telemetry history, preferences and window restoration state.
- Deleted 101 Hash Fleet defaults domains through `defaults` before filesystem removal, with 39 exact targets removed. Canonical `defaults read` returned exit 1. Canonical app, app container, CLI configuration and CLI link were all confirmed absent.
- Preserved the sandbox's diagnostic-only CrashReporter metadata outside the removed container. Original OS hang reports, continuous samples, source, symbols and test evidence remain intact. System Keychain and macOS privacy/TCC settings were not changed.
- Removed four additional verified generated iOS/watch/test app bundles and two retired ZIP/PKG installers. Unrelated WebDriverAgent and tiny offline installer-test fixtures were not removed.

Exact local receipt: `~/.jcode/scratch/hashfleet-clean-reset-20261106T1541.noindex/reset-receipt.json`. The six additional generated artifacts were exact paths verified immediately before their removal at 15:43 UTC.

## Administrator-only remainder

`~/.Trash/Hash Fleet.app` remains root-owned. Deleting its Contents returned permission denied. It is not the canonical installation or active settings, but prevents claiming all historical app copies were deleted. An administrator must authenticate locally to remove this exact retired copy. No permission bypass was attempted.

Inactive historical reset/diagnostic folders in Trash were not blindly swept. They do not restore the active settings. No source directory was selected for deletion.

## Fresh build and acceptance

A clean Release native build and a separate fresh CLI build were started at 15:41:59 UTC in the previously absent directory `~/.jcode/scratch/hashfleet-clean-build-20261106T1542.noindex`. The native build reuses pinned dependency source checkouts, not previous compiled products. Automatic dependency updates are disabled.

Build/install result: both fresh builds completed successfully at 15:44:29 UTC, 149.8 seconds total. The native app and CLI were signed with the existing development identity and installed at `/Applications/Hash Fleet.app` at 15:44 UTC. The native platform validator and deep/strict signature verification passed. The staged duplicate app was deleted after byte comparison against the canonical executable.

Installed native SHA-256: `3f6cc8e68dcf188bb05b77dc7ce5bd6be3da2c69944e20da4532513c1e55b41b`. Native UUID: `61C3E80F-D522-3045-B8B0-3682FCEAEB26`. CLI SHA-256: `0b87d0f2e29ff81b5dc7babf9f5c17f201dfb377a8f7f8d012830f772dae274a`.

At 15:45:13 UTC, the final read-only verification found no running Hash Fleet process, no active app container/configuration/preferences at the checked paths, and no remaining Hash Fleet defaults domain. The canonical CLI symlink resolves to the new app. The app has not been launched. Detailed receipt: `~/.jcode/scratch/hashfleet-clean-reset-20261106T1541.noindex/fresh-install-receipt.json`.

No test suite or interactive menu workflow was executed during this reset. Source code remains the existing candidate, not a new repair.

No GUI was opened, focused, resized or clicked during the reset. A successful compilation, valid signature and empty local state will establish a clean test installation only. Frequency entry, Technical details, Advanced switching and Easy frequency editing still require matched interactive validation. No hardware Apply action is part of this reset. The three earlier strict sidebar-dismiss warning gates remain failed.
