# Native macOS installation

Hash Fleet for Mac is a **native macOS app** built with the `HashFleetMac` scheme. Its workspace and menu bar share one executable and in-memory fleet store. The iOS/iPad app is not a Mac installation artifact. Run that build only inside the iOS simulator when developing on a Mac, never as a Designed-for-iPad Mac installation. Normal iPhone/iPad device targets remain available. The native app is expected at `Release/Hash Fleet.app`, with bundle ID `app.hashfleet.mac` and executable `Hash Fleet`. The release package embeds the `hashfleet` CLI at `Contents/MacOS/hashfleet`.

## Build a local package

On a Mac with the project’s configured Xcode and Swift toolchains:

```sh
Scripts/package-hashfleet-mac.sh
```

The script invokes `xcodebuild` for `HashFleetMac`, Release, native macOS arm64, then validates the app’s bundle metadata, Mach-O platform, layout, and signature before using or replacing the distribution output. It rejects iOS, simulator, Catalyst, wrapper, and non-Mach-O artifacts. It then signs the CLI without app entitlements and re-seals the host while preserving the host’s identifiers, entitlements, flags, and runtime metadata. The signing is done inside out without applying one target’s entitlements to nested code. The default identity is ad-hoc (`-`), suitable for local testing only. To sign with an already-installed code-signing identity, set `HASH_FLEET_CODESIGN_IDENTITY` to that identity. This does not provision capabilities, create signing identities, notarize, or submit anything.

The package appears under `dist/hashfleet-mac/Hash Fleet.app`, with `Hash Fleet Mac.zip` and `Hash Fleet.pkg` beside the directory. All are built in staging before replacing the previous distribution. The PKG installs the native app into `/Applications` and links `/usr/local/bin/hashfleet` to its bundled CLI, with no helper app or LaunchAgent. Set `HASH_FLEET_INSTALLER_IDENTITY` only to an existing approved installer identity if a signed PKG is desired. The default local PKG is unsigned, and neither artifact is notarized by this script. Replaced distribution directories temporarily receive a `.previous.*` name during packaging. After the replacement has passed structural validation and required runtime checks, the coordinator must identity-check and remove superseded distribution bundles and archives rather than retaining previous launchable builds. The re-sign step requests preservation of existing identifiers, entitlements, flags, and runtime metadata, but inspect the resulting signature and entitlements for the actual build before distribution.

To validate a candidate bundle directly:

```sh
Scripts/validate-native-mac-app.sh '/path/to/Hash Fleet.app'
```

The validator checks `CFBundlePackageType`, bundle ID/name/executable, `CFBundleSupportedPlatforms`, prohibited iOS metadata, nested apps/extensions and wrapper layouts, the native executable path and Mach-O format/platform (`LC_BUILD_VERSION` platform 1), and strict code-signature validity. The check is structural, not a substitute for review of the target’s source, entitlements, privacy behavior, or release signing policy.

## Install for the current Mac

The installer stages and validates the packaged app and CLI before moving the installed app. A temporary previous-app backup lives in the hidden, nonindexed `.hashfleet-backups.noindex` directory during replacement. It verifies the new app and CLI link before committing the replacement. A pre-commit failure attempts to restore the previous entries. After structural, signature and CLI-link validation, the installer commits and deletes only its exact identity-verified superseded app backup, following the owner's November 6, 2026 requirement not to accumulate previous builds. A pre-existing CLI entry remains a separate reversible backup. Cleanup failure must not roll back a successfully committed app using a partially removed old bundle.

**Local update completion requirement, clarified November 6, 2026 at 11:27 UTC:** `/Applications/Hash Fleet.app` must be the only current Fleet Mac app. Delete superseded Mac app bundles, including generated, retired and rollback copies, after the replacement is validated. Do not keep earlier builds available to launch or reopen an unchanged old binary as though it were a fix. Preserve source code, owner preferences/history, crash logs and symbolication evidence. Keep only current distribution archives, not superseded app builds. Unregister old bundle paths and check physical outputs, existing-path LaunchServices entries, running processes and Dock recents. Never restart or reinstall the app merely to clean generated copies.

```sh
Scripts/install-hashfleet-mac.sh
```

The default app destination is `/Applications/Hash Fleet.app`; the CLI link is `~/bin/hashfleet`. For isolated/manual installs, set `HASH_FLEET_APP_DEST`, `HASH_FLEET_PACKAGE_DIR`, and/or `HASH_FLEET_CLI_DIR`. The app is copied as a complete `.app` bundle. User data outside the bundle is not migrated, erased, or rewritten by these scripts.

Installer validation does not establish UI responsiveness or resolution of an intermittent hang. These scripts do not stop a running app or alter a LaunchAgent. They do not sweep legacy wrappers, standalone menu-bar apps, historical generated builds, or LaunchServices registrations. That cleanup remains a separate identity-checked coordinator operation under the owner's explicit scope. Preserve configuration, user data, crash reports and symbolication evidence. Keep an app rollback only during the replacement transaction, then delete superseded Mac bundles after validation.

## Offline regression tests

The script tests use isolated temporary directories and tool doubles. They do not build with Xcode, invoke real code signing, install into `/Applications`, or access devices/network services:

```sh
python3 -B Scripts/tests/test_package_hashfleet_mac.py
bash -n Scripts/package-hashfleet-mac.sh Scripts/install-hashfleet-mac.sh Scripts/validate-native-mac-app.sh
```
