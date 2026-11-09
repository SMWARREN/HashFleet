# Install Hash Fleet with Homebrew

The Mac app and terminal CLI are separate downloads. Install either or both.
These packages require Apple Silicon and macOS 14 (Sonoma) or later.
Intel binaries are not provided in this release.

## Add the project tap

```sh
brew tap smwarren/hashfleet
```

Homebrew requires explicit trust for third-party packages by default starting
with version 6. The trust commands below apply only to the selected package in
this project tap. On older versions without `brew trust`, omit those lines.

Official Homebrew catalog packages are trusted automatically. This tap is
project-maintained, so it needs explicit trust even though the release binaries
are Apple-notarized. Signing and tap trust are separate checks. A fully qualified
install also grants trust to that item, but uses the owner/tap prefix. See
[Homebrew's tap trust documentation](https://docs.brew.sh/Tap-Trust).

## Native Mac app only

```sh
brew trust --cask smwarren/hashfleet/hashfleet
brew install --cask hashfleet
```

Installs `Hash Fleet.app`. It does not install the terminal command. If you
already installed Hash Fleet through TestFlight or another channel, Homebrew
may refuse the existing app. Do not use `--force` to overwrite a running app.
Choose one app distribution channel and preserve your existing data.

## Terminal CLI only

```sh
brew trust --formula smwarren/hashfleet/hashfleet-cli
brew install hashfleet-cli
```

Installs the `hashfleet` command and its resource bundle, without installing
or launching the Mac app. To explore fictional data without contacting miners:

```sh
hashfleet watch --demo
```

The real CLI can also send reviewed settings changes. It is not exclusively
read-only. No LaunchAgent, mining process, account or background service is
installed by either Homebrew package.

## Downloads and updates

- Source and release downloads: https://github.com/SMWARREN/hashfleet
- Project-maintained Homebrew tap: https://github.com/SMWARREN/homebrew-hashfleet
- Website: https://hashfleet.app

```sh
brew upgrade --cask hashfleet
brew upgrade hashfleet-cli
```

This is the project-maintained tap, not an assertion of inclusion in the
central Homebrew catalog. Both binaries are Developer ID signed and accepted
by Apple notarization. The Mac app includes a stapled notarization ticket.
The standalone CLI relies on the online notarization ticket. Checksums and
license notices accompany the release.

## Moving into the official Homebrew catalog

The project tap remains the supported installation route until Homebrew accepts
the relevant package. No official-catalog pull request has been submitted as
part of this publication. The app and CLI need separate submissions.

1. **Check eligibility first.** Review the current [shared acceptance policy](https://docs.brew.sh/Package-Acceptance-Policy), including maintenance, release discovery, repository age, and genuine public interest. As checked November 9, 2026, repositories under 30 days old are normally ineligible. Owner self-submissions normally need at least 90 forks, 90 watchers, or 225 stars, with documented exceptions possible. Meeting a threshold does not guarantee acceptance.
2. **Prepare the Mac cask for `homebrew/cask`.** Use the signed, notarized upstream app download, immutable release URL and SHA-256. Declare supported hardware and macOS versions, confirm version discovery, and follow the [cask requirements](https://docs.brew.sh/Acceptable-Casks).
3. **Prepare a source-built CLI formula for `homebrew/core`.** The current tap formula installs a precompiled ARM64 archive. Core normally requires building open-source CLI software from a versioned, verified source release, with reproducible dependencies and a meaningful test. Follow the [formula requirements](https://docs.brew.sh/Acceptable-Formulae).
4. **Validate the packages in an isolated environment.** With separate approval for installation checks, follow Homebrew's current audit, style, install/uninstall and formula-test steps. These are future packaging checks, not permission to reopen app stability investigations or contact miners.
5. **Submit and address review.** Search existing submissions, fork the appropriate official repositories, open one pull request per package, disclose AI assistance as required, and respond to maintainer feedback. See [Adding Software to Homebrew](https://docs.brew.sh/Adding-Software-to-Homebrew).
6. **Switch instructions only after acceptance.** Confirm the official entries are available, then document installs without the project tap or explicit third-party trust. Keep the old tap available long enough to provide a deliberate migration path for existing users. Do not assume both packages will be accepted together.

GitHub Actions can automate release packaging, but it cannot grant official
Homebrew acceptance or remove third-party trust requirements.

## Stability status

Fixed, not verified. The owner reported roughly ten error-free hours on both
devices. No further stability diagnostics or app workload tests were run for
this distribution task. Release compilation, signing, notarization and package
metadata checks do not establish that intermittent issues cannot recur.
