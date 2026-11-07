# Apple Watch App Store delivery, 2026-11-04 UTC

## Scope

The owner finished the Watch app and requested that it be added to the existing Hash Fleet release. This delivery adds the independently runnable Watch app and its static Smart Stack / supported watch-face launcher to the existing iOS 1.0 draft. It does not create a separate app record, submit for review, release a version, enroll testers, or replace any installed iPhone, Watch or Mac app.

## Frozen release and signing

- Accepted source revision: `a10fec115ba3f74ceed100f023eb235d4a009cd1`.
- An isolated release copy preserves the current two owner scheme files and the pin-identical owner lockfile. No application behavior was edited.
- All five distribution targets use version **1.0**, build **20**: `app.hashfleet`, `.widgets`, `.notification-service`, `.watchkitapp`, and `.watchkitapp.widgets`.
- Existing Apple Distribution identity and three iOS store profiles were reused. Only the two missing Watch bundle records and their two App Store profiles were created. No certificate or private key was rotated or exported.
- The iOS application remains universal for iPhone and iPad. Both nested Watch targets require watchOS **26.5** and contain device architectures `arm64` and `arm64_32`.
- Strict nested signatures, expected identifiers, production entitlements, profile UUIDs, version/build parity, independent-running declaration, Watch companion identifier and widget embedding were checked in the archive and exported IPA.
- The isolated parent Info.plist adds only `ITSAppUsesNonExemptEncryption=false`. Apple independently reports `usesNonExemptEncryption=false` on build 20. This is an export-compliance declaration, not a claim that no platform encryption is used.

## Exact uploaded artifact and Apple readback

- IPA: `HashFleet-iOS-Watch-1.0-20.ipa`, **54,361,883 bytes**.
- IPA SHA-256: `4813e8625bb59eb5286dc9fff6483472784fd11921c1a07434a11ded546b04cb`.
- Existing app record: `6812623943`, bundle `app.hashfleet`.
- Processed build ID: `10cc616e-b9b0-42a2-bd66-9e0e92b82b96`, state **VALID**.
- Existing iOS draft: `6e59d0e4-7087-4f1f-a39a-faeab0ab1778`, version 1.0, now selecting build **20**, still **PREPARE_FOR_SUBMISSION**.
- One exact IPA upload was invoked through Blitz MCP. Its client request timed out after 30 seconds while the in-app operation continued. Fresh Apple reads established the accepted build, so no second upload was attempted.
- Blitz had already selected the exact new build by the subsequent readback. The initial stale build-18 guard failure was retained, then the exact observed build-20 selection was respected without a redundant attachment request.
- Prior iOS build 18 remains present. Existing native Mac build **19** and its draft `605fc5ac-0228-4c30-8263-e8b2666f7768` are unchanged.

## Watch listing and review information

- Blitz MCP saved only the iOS en-US description and promotional text, adding accurate Watch functionality, minimum watchOS, foreground-refresh limits, independent local setup and the static launcher behavior. Other returned localization fields are unchanged. The Mac localization is unchanged.
- Two actual, unmodified native Watch demo screenshots were captured by the existing UI tests on a newly owned 44 mm watchOS 26.5 simulator. Both are RGB PNGs, **368 x 448**, with no alpha or synthetic UI edits.
- Watch screenshot set: `e15338da-0262-425a-af6e-fc79ca669011`, display type `APP_WATCH_SERIES_4`.
- `01-Watch-Demo-Fleet.png`: asset `9c800019-6106-8447-8039-e5a61e97c29e`, 27,157 bytes.
- `02-Watch-Demo-Miner.png`: asset `d4400019-6106-8447-8001-e6bf21b2486d`, 34,864 bytes.
- Both assets were read back **COMPLETE**, with matching names, dimensions, byte sizes, checksums and ordering. The Watch upload used the bundled ASC CLI because the current Blitz screenshot MCP enum exposes only iPhone, iPad and desktop tracks.
- Watch-specific review instructions were appended to the existing iOS notes. They explain Try demo, local Wi-Fi setup, direct read-only access and foreground-only refresh. Original notes, private review contacts and all other returned review fields were preserved.
- The original 18 iPhone/iPad/Mac screenshot assets and both COMPLETE native reviewer demonstration videos were preserved. No Watch-specific video was added or represented as uploaded by this task.

## Verification boundaries

- Fresh Watch core acceptance: **159 passed**, exact frozen release source.
- Fresh unchanged native Watch UI fixtures: **2 passed**, covering sample fleet/miner details and independent empty/manual setup.
- Fixture tests and demo screenshots made no real miner requests. No production network discovery or hardware operation was invoked.
- Simulator checks, archive validation and installed-metadata evidence are not physical Watch acceptance. Physical phone-off Wi-Fi behavior, wrist-down behavior and physical widget/face invocation were not recertified here. The declared circular/inline widget families must not be mistaken for separately exercised face tests.
- The canonical `/Applications/Hash Fleet.app` remains native local build 13, bundle `app.hashfleet.mac`, with unchanged executable and Info.plist hashes. It was not launched, restarted or replaced for this delivery.
- Only the simulator created for these captures is eligible for final shutdown. Existing simulators and physical devices are not reset or overwritten.

## Preservation and completion gate

Private task evidence is under `~/.jcode/scratch/hashfleet-watch-store-20261104T0053.noindex/`. Original diagnostics are retained rather than rewritten as successful commands.

- Complete signed archive ZIP: `HashFleet-iOS-Watch-1.0-20.xcarchive.zip`, SHA-256 `483c9a65cc67fa46951a8701a82503f558637269e0a577f9c7973f297e209f23`. All **75** original archive file/symlink entries, bytes, targets and permissions were independently verified in the ZIP.
- Frozen release source ZIP: `HashFleet-Watch-Release-Source-a10fec1.zip`, SHA-256 `0bab28a5ae697f5ccdae52dd0c3b5cf6bd5e97f18994514baff4d6aa28208a25`. All **1,293** source entries were independently verified, including the copied workspace package-resolution state. The original 1,292-file snapshot and the one metadata-only plist addition are separately recorded.
- Final durable backup destination: `~/Library/Application Support/HashFleetBackups/2026-11-04-watch-store.noindex/`.
- Completion requires a successful postcommit read-only acceptance receipt, a current committed-history Git bundle and the durable folder's independently rechecked manifest and backup receipt. Regenerable build/package caches are excluded. Signing private keys remain in the keychain, not in this backup.

Only this owned delivery document is committed. Pre-existing dirty schemes, lockfile, website stability notes, Blitz metadata, screenshots and marketing files remain uncommitted and untouched by staging. No App Review submission or release is authorized or performed.
