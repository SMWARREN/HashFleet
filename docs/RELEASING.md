# Source release and distribution

HashFleet can be shared as source without access to the original developer's accounts or miners. The generated Xcode project and local Swift package are included, along with the GPL license, API reference, privacy documentation and tests.

For the maintained repository's PR checks and versioned Mac/CLI releases, see
[automation and signing setup](AUTOMATION.md). Public app and CLI downloads remain
separate. The local combined installer described elsewhere is not the public
Homebrew release pipeline.

## Prepare a source archive

Start from a clean, committed checkout:

```sh
bash Tools/package-source.sh 0.1.0
```

This uses `git archive HEAD`. It includes **only tracked, committed files**, not the Git database or uncommitted local artifacts. This project's simulator preferences, hardware screenshots, inventories and build products are stored outside tracked source. However, `.gitignore` cannot exclude a file that was already committed. Audit the archive before sharing, especially if you have added signing files, screenshots or response exports. An existing archive is never overwritten.

The output is `build/releases/HashFleet-0.1.0-source-<commit>.zip`, with a companion SHA-256 checksum. This is an unsigned source bundle, not an installable IPA or App Store release.

Before sharing, inspect the file list and verify the checksum:

```sh
cd build/releases
unzip -l HashFleet-0.1.0-source-<commit>.zip
shasum -a 256 -c HashFleet-0.1.0-source-<commit>.zip.sha256
```

Extract into a new folder, open `HashFleet.xcodeproj`, and build with your own signing team. The source archive does not need `.git` to build. To regenerate the project, install XcodeGen and run `xcodegen generate`.

## Publish a public source repository

Choose the owner, repository name and issue/security reporting contact before publication. Do not reuse addresses, wallet/worker names, network names, or real-miner screenshots from local testing. Only synthetic screenshots are committed here.

After the repository exists, set the remote explicitly, push the `main` branch, and add the public repository URL to the README and app About screen. Enable the included CI workflow and private security reporting. A repository push is a separate publication action, not performed by the packaging script.

## Signed iPhone distribution

For direct development installation, select a personal development team in Xcode and use a unique bundle identifier. For TestFlight/App Store distribution, the app owner must configure signing and App Store Connect, provide a public privacy-policy URL, review the GPL distribution obligations and Apple's current terms, and complete the physical-device release checks in [release status and validation limits](STATUS.md).

Do not treat passing mocks, a source ZIP, a successful simulator build, or read-only LAN monitoring as approval to flash hardware. Firmware updates still require a board-correct image and a deliberate recovery plan.
