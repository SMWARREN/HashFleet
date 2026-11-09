# Building a personal copy

You do not need the original developer's credentials, fleet configuration, App Store Connect account, APNs key or server configuration to build the app or explore its demo. Do not copy private configuration from another checkout.

## Requirements

Use macOS with Xcode and SDKs that support the deployment targets in `project.yml` and `Package.swift`. These currently declare Swift 6, iOS 17, macOS 14 and watchOS 26.5. The embedded Watch targets require a compatible watchOS SDK even when building the parent iOS target. Install XcodeGen only if regenerating the included Xcode project.

The dependency URLs and resolved revisions are public. Package resolution requires network access unless the packages are already cached. A dependency download failure is not a request for the original developer's credentials.

## No-signing builds

From the repository root:

```sh
swift test

xcodebuild -project HashFleet.xcodeproj -scheme HashFleetMac \
  -configuration Debug -destination 'generic/platform=macOS' \
  -derivedDataPath build/public-mac \
  CODE_SIGNING_ALLOWED=NO DEVELOPMENT_TEAM= build

xcodebuild -project HashFleet.xcodeproj -scheme HashFleet \
  -configuration Debug -destination 'generic/platform=iOS Simulator' \
  -derivedDataPath build/public-ios \
  CODE_SIGNING_ALLOWED=NO DEVELOPMENT_TEAM= build
```

These commands build locally. They do not install an app on a physical device, upload an archive, create a TestFlight build, or publish a release. An unsigned build is not a notarized distribution package.

In Xcode's scheme Run settings, add `--demo` before launching a development build to explore the sample fleet without contacting miners. Do not use real miner addresses for tests. The CLI also supports an explicit offline demo:

```sh
swift run hashfleet watch --demo
```

## Your own physical-device signing

To run on your own iPhone or Watch, select your own team and unique identifiers for the app and every embedded extension in Xcode. Match App Groups and companion identifiers as described in `WIDGETS.md` and `WATCHOS.md`. Do not reuse another developer's provisioning profiles or certificates.

For a private local team override, create `Signing.local.xcconfig`:

```xcconfig
DEVELOPMENT_TEAM = YOUR_TEAM_ID
```

That filename is ignored. `Signing.xcconfig` deliberately has no assigned team. Changing only the team does not configure all bundle identifiers or entitlements for you.

## Optional integrations

- **Miner monitoring:** add your own reachable devices. There is no bundled personal fleet inventory. Keep mining hardware on a trusted private network and preserve the app's confirmation and voltage safety checks.
- **Native App Store tips:** StoreKit product identifiers are public identifiers, not credentials. They refer to the original app's catalog and do not create products for your own bundle. A fork's Store distribution requires its own catalog and account configuration. Product-loading failure must not be treated as a reason to embed credentials.
- **Direct-distribution Mac and CLI support:** intentionally public support destinations remain part of the source. They are not private signing or authentication material. Review these destinations before distributing your own fork.
- **Optional server:** `Server/private/config.example.php` is a template. Production configuration, APNs keys and generated tokens must remain outside the public repository. The app's demo and local monitoring do not require deploying that server.
- **Website:** `website/.env.example` lists optional public links. Browser-bundled `VITE_` values are not a secret-storage mechanism.

## Sharing your changes

Read the [security policy](../SECURITY.md) and [release guide](RELEASING.md) before sharing. Check both the current tree and history. Ignoring a filename does not remove previously committed contents. Review screenshots and other binary assets separately from text-based secret scans.

Successful development builds and automated scans do not by themselves certify hardware safety, asset privacy, third-party rights, or public-release readiness.
