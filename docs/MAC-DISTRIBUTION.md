# Hash Fleet Mac distribution

Hash Fleet for Mac is the **native macOS app**, built by the `HashFleetMac`
scheme. The iOS/iPad app is not a Mac installation artifact. The workspace and
menu-bar UI share the native app executable and fleet store.

See [native installation and signing](MAC-NATIVE-INSTALL.md) for the canonical
packaging contract, validation checks, reversible installation, and limitations.

## Local package

```sh
Scripts/package-hashfleet-mac.sh
```

The script builds the native Release app and release CLI, validates the app,
embeds the CLI at `Hash Fleet.app/Contents/MacOS/hashfleet`, and re-signs the
nested executable and enclosing app in staging. It produces:

- `dist/hashfleet-mac/Hash Fleet.app`
- `dist/hashfleet-mac/INSTALL.md`
- `dist/Hash Fleet Mac.zip`
- `dist/Hash Fleet.pkg`

The package does not contain a Designed-for-iPad wrapper or install the separate
legacy menu-bar companion. It does not install a LaunchAgent or start mining.

The default re-signing identity is ad-hoc, suitable for local testing only.
`HASH_FLEET_CODESIGN_IDENTITY` selects an existing code-signing identity.
`HASH_FLEET_INSTALLER_IDENTITY` optionally signs the PKG with an existing installer
identity. Neither option provisions capabilities or performs notarization.
A successful package build is not public-distribution approval.

For a separately verified prebuilt native app, both opt-in variables are required:

```sh
HASH_FLEET_USE_PREBUILT_APP=1 \
HASH_FLEET_APP_SOURCE="/absolute/path/to/Hash Fleet.app" \
Scripts/package-hashfleet-mac.sh
```

Verify its source revision, configuration, signature, entitlements and test
results before selecting it. The path alone does not establish provenance.
The source cannot be inside the output directory. `HASH_FLEET_DIST_DIR` must end
in `hashfleet-mac`. `HASH_FLEET_DERIVED_DATA` selects the Xcode build directory.

## Installation

```sh
Scripts/install-hashfleet-mac.sh
```

The repository installer stages the app into `/Applications/Hash Fleet.app` and
links `~/bin/hashfleet` to the bundled executable. The PKG instead creates the
system link `/usr/local/bin/hashfleet`. Existing app/link entries are retained
as reversible backups. No user data is deleted or migrated, and existing apps
or background services are not stopped or removed. Cleanup is a separate action.

The App Store sandbox cannot install a CLI into `~/bin` or register a LaunchAgent.
Do not treat the direct-distribution installer as a Mac App Store submission.

## Release feature policy

`FleetReleaseFeatures.xmrigEnabled` is false for the current app release. The flag
hides XMRig in the app while preserving saved identities, credentials, core API
support and CLI support. Re-enabling it requires mixed-fleet, freshness/control,
visibility and native UI validation. Hidden devices are not deleted.

The CLI dashboard and `status` commands read telemetry. **The CLI also has a
settings editor**, so the entire CLI must not be described as read-only. Settings
writes target the selected miner and require explicit review and confirmation.
Use `hashfleet watch --demo` for a sample dashboard without network access.
Never include real credentials or raw private telemetry in release artifacts.

## Regression checks

```sh
python3 -B Scripts/tests/test_package_hashfleet_mac.py
bash -n Scripts/package-hashfleet-mac.sh Scripts/install-hashfleet-mac.sh Scripts/validate-native-mac-app.sh
```

These use isolated fixtures and tool doubles. They do not replace signed builds,
installation acceptance, notarization, store review, or physical-device testing.
