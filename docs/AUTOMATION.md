# Automation

HashFleet has two workflows. Neither approves or merges pull requests, and neither
updates `main` directly. The release workflow can create a separate Homebrew update
branch and pull request.

## CI (`.github/workflows/ci.yml`, workflow `HashFleet CI`)

Runs on pull requests and on pushes to `main`, with a read-only token and no secrets. It never uses `pull_request_target`. Branch protection should require exactly one check: **`CI required`**. Contributors do not need any secret to get a result.

It runs repository syntax and contract checks, website tests and build, Swift package tests, the CLI build, and unsigned macOS and iOS simulator builds on the standard arm64 `xcode-27` preview runner with Xcode 27.2. This matches the project SDK, including SwiftUI toolbar APIs. Preview runner availability is not guaranteed. Heavy simulator UI tests are manual: run the workflow with mode `simulator-ui-tests`. `runner-check` only confirms runner access.

### SwiftLint

SwiftLint 0.65.1 is a separate required CI job using the existing `.swiftlint.yml`.
The upstream portable archive is SHA-256 pinned and version-checked before use.
It runs `swiftlint lint --strict --no-cache`, without automatic corrections or a
suppression baseline. Reproduce locally with that same version and command.
Strict mode fails on warnings as well as errors. The configured `unused_import`
analyzer rule requires a compiler log and is **not** executed by this lint job.
Adding CI does not imply existing lint violations have been repaired.


## Release (`.github/workflows/release.yml`, workflow `HashFleet Release`)

Starts only after a successful `HashFleet CI` run. It is never triggered by a pull request.

1. **Trust gate.** The `workflow_run` must be a completed, successful push to `main` of this repository from `.github/workflows/ci.yml`, and the release workflow itself must run from `main`. A manual run needs a CI run ID and must also be started on `main`. `Scripts/release/release.py plan` re-checks the run through the API and decides whether the version in `version.txt` still needs a release.
2. **Protected environment.** The release job uses the `release` environment, restricted to `main`. Store signing and notarization secrets there, not in repository secrets. The workflow fails by name if any is missing. An optional required reviewer adds a separate approval before signing, beyond the reviewed version PR.
3. **Exact commit.** The job checks out the planned SHA and confirms it is reachable from `main`. `prepare.sh` compiles unsigned packages in a step without signing secrets. Only afterwards does `build.sh` import the temporary signing key and sign/notarize the separate packages into `$RUNNER_TEMP/hashfleet-release`.
4. **Publish.** `release.py publish` uploads only checksum-verified packages and opens a Homebrew pull request. Signing secrets are given only to the missing-secret preflight and signing step, never to compilation. These steps share a runner, so reviewed `main` code remains the trust boundary. The default token is given to the publish step only.

Releases run one at a time (`release-global`) and are never cancelled midway. A pending run may be replaced by a newer one, which is safe because planning is recomputed from `main`.

### Manual steps and limits

- To release a new version, change `version.txt` in a reviewed pull request and merge it. Nothing is tagged or published for an unchanged version.
- A human reviews and merges the Homebrew pull request. GitHub may require **Approve workflows to run** for PRs created by the default token. The repository setting "Allow GitHub Actions to create and approve pull requests" permits creation, but these workflows never submit approving reviews or merge.
- Published releases must be treated as immutable. Do not replace the assets of an old version. Fix forward with a new version.
- Never put signing material in a pull request, an issue, or a log.

### One-time signing setup

An authorized maintainer must add these secrets to the `release` environment:

| Secret | Value |
| --- | --- |
| `MACOS_CERTIFICATE_P12` | Base64-encoded Developer ID Application certificate and private key |
| `MACOS_CERTIFICATE_PASSWORD` | Password protecting that exported P12 |
| `APPLE_SIGNING_IDENTITY` | Developer ID Application identity name or certificate SHA-1 |
| `APPLE_TEAM_ID` | Team ID expected in both signatures |
| `APPLE_API_KEY_P8` | App Store Connect notarization API private key text |
| `APPLE_API_KEY_ID` | Notarization key ID |
| `APPLE_API_ISSUER_ID` | Notarization issuer ID |

### Add the credentials, step by step

These credentials sign the separate **Developer ID Mac app and CLI downloads**,
not an iOS App Store submission. Keep private material outside the repository.

1. Open **HashFleet → Settings → Environments → release** on GitHub. Under
   **Environment secrets**, use **Add environment secret** for each name above.
   Keep the deployment branch rule restricted to `main`.
2. On your Mac, open **Keychain Access → My Certificates**. Find the valid
   **Developer ID Application** identity used for your existing downloads and
   expand it to confirm its private key is present. Export the certificate and
   private-key pair as a password-protected **.p12**, outside this checkout.
   A .cer alone is insufficient. Do not select Apple Development or Apple
   Distribution. If the private key is missing, use its original Mac/keychain
   rather than creating a replacement blindly.
3. Convert that P12 to Base64 locally and paste into **MACOS_CERTIFICATE_P12**:

   ```sh
   base64 -i "$HOME/private-signing/HashFleet-DeveloperID.p12" | pbcopy
   ```

   Adjust the private path. Set **MACOS_CERTIFICATE_PASSWORD** to the export
   password. Base64 is not encryption. Clear your clipboard after pasting and
   keep the P12 protected. Never paste these values into chat, issues, or source.
4. Set **APPLE_SIGNING_IDENTITY** to the matching full certificate identity name
   (for example, `Developer ID Application: Your Name (TEAMID)`) or certificate
   SHA-1. Set **APPLE_TEAM_ID** to its Apple Developer Team ID.
   `security find-identity -v -p codesigning` lists names and fingerprints without
   exporting private keys. Do not post its output publicly unnecessarily.
5. In **App Store Connect → Users and Access → Integrations → App Store Connect API**,
   use an authorized **team API key** supporting notarization. This workflow
   expects a team key and issuer ID, not an individual key. Reuse a suitable key
   whose private file is securely retained. A new key requires appropriate account
   permissions and secure retention of its private-key download.
6. Add the complete **.p8 text**, including BEGIN/END lines and newlines, as
   **APPLE_API_KEY_P8** (raw text, not Base64). Add its key ID as
   **APPLE_API_KEY_ID** and issuer UUID as **APPLE_API_ISSUER_ID**.
7. Confirm all **seven names** are listed in the release environment. GitHub does
   not reveal stored values later. You do not need to share them with an agent.
   Merge the reviewed automation PR when its checks pass. A later reviewed
   `version.txt` bump triggers the first real signing/notarization run. That run,
   not merely adding secrets, verifies the pipeline. Never overwrite old releases.

Primary references: GitHub's **Installing an Apple certificate on macOS runners for
Xcode development**, Apple's **Creating API Keys for App Store Connect API**, and
**TN3147: Migrating to the latest notarization tool**. This guide does not export
or upload credentials.

No credentials are shipped with the repository. Do not export or upload an owner's
keys without their approval. The new signed pipeline is not end-to-end verified until
a real version passes signing, notarization and publication with these credentials.
Missing credentials never cause an unsigned fallback.

If publication stops after creating a tag or draft, inspect the retained draft and
Actions logs. The workflow deliberately refuses to overwrite it. If publication
succeeded but only the Homebrew PR failed, an authorized maintainer can retry just
`python3 Scripts/release/release.py homebrew --version X.Y.Z` from a trusted checkout
with `gh` authenticated. Existing matching PRs are reused, not automatically merged.

The website is tested and built by CI, not automatically deployed to the private host.
Its deployed versioned download links need updating when a new release is published.
Code-fix agents may follow `.github/copilot-instructions.md` and open PRs when explicitly
enabled and assigned by a maintainer. These files do not activate a paid agent service.
