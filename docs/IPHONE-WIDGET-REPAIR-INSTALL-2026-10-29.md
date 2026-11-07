# iPhone widget repair installation, October 29, 2026

## Approved delivery

At **23:16:43 UTC**, the operator approved an in-place, data-preserving installation of the widget-refresh repair. Hash Fleet **0.1.0 build 9** was installed successfully at approximately **23:26:34 UTC** on the previously identified wired, paired iPhone. A subsequent read-only installed-app query independently confirms build 9 and the unchanged application/App Group identities.

The frozen source is **`d15dabbe40034d298ddad71a64902f5c3527993d`**. This includes the prepared-refresh lifetime repair and the preceding reviewed bounded-chart change. No uncommitted working-tree changes were included. Only external build metadata changes the build number to 9. All **1,104** archived source files remain byte-identical to the approved archive.

The same existing distribution certificate and target-specific provisioning profiles were reused. The main app and both existing extensions remain arm64 and have exactly the same signed entitlements, application identities, App Group and APS capabilities as build 8. No account setup, new capability, registration or remote service was introduced.

## Installation and preservation evidence

Private artifact root: `~/.jcode/scratch/hashfleet-phone-widget-install-20261029-2317/`.

| Check | Observed result |
| --- | --- |
| Signed physical-device build | Succeeded using the exact frozen source and existing signing configuration |
| `signed-app-validation.json` | **1,144** artifact, source, signing and repository-preservation checks passed before installation |
| `install-result.json` | One approved `devicectl device install app` command completed successfully, without uninstall/reset/remove flags |
| `phone-after-install.json` | Actual installed application is build **9**, same existing bundle and App Group |
| `installed-preservation-validation.json` | **21/21** installation/preservation checks passed |
| Current accessible user data | All **4 files / 1,372,299 bytes** from Application Support, app Preferences and shared Library read back byte-identical |
| Saved preferences | All **25** main preference keys preserved, including both existing widget-sharing and manual-local-refresh consents; no diagnostic exception needed |
| `postinstall-artifact-validation.json` | All **1,144** artifact/source/repository checks passed again after installation |

The prior app was not removed. Accessible user data was privately backed up before installation. This is not a claim that inaccessible keychain material or every root App Group file was independently copied. In particular, the existing root refresh-state file remains outside the device tool's permitted copy paths, and that restriction was not bypassed. The update did not intentionally clear or alter it.

## Actual widget acceptance remains unverified

A single post-install normal-readiness observation at approximately **23:27:19 UTC** reported that the passcode was required. No app launch, authentication bypass, indefinite unlock polling or synthetic widget-tap success was attempted. No miner request or hardware/settings operation was performed by this installation workflow.

The operator was asked to unlock normally, open Hash Fleet until complete readings load, then return to the Home Screen and tap Refresh. Foreground preparation may be needed if the earlier bug already deleted the saved refresh configuration. Do not toggle consent, reinstall/remove the app, or silently rebind an existing Live Activity as a substitute for observing this check.

This completes the approved preserving installation, **not** verification that a physical Home Screen tap now produces a new reading. The earlier deferred device acceptance can resume after normal user readiness and an observed tap. No repeating watcher remains running.
