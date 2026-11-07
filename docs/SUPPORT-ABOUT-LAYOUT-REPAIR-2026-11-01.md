# Support and About layout repair, November 1, 2026

## Cause and repair

The crypto addition put the entire payment/address form into About. The support component also placed a semantic settings Section inside a VStack, which prevents the iOS List from treating its children as separate grouped rows. Its section accessibility identifier could overwrite child control identifiers on iOS.

Commit `48f0688` restores transparent Group composition and uses the platform-aware section identifier helper. About retains its informational sections and now has one compact internal Support link. Full receiving addresses remain on Support with the original storefront policy and copy-only actions. Explicit invisible line-break opportunities prevent typographic hyphens from appearing inside long receiving addresses. Clipboard contents and accessibility labels continue using the original immutable address. Both Done buttons have explicit accent foreground contrast.

The injected storefront reader defaults to the actual StoreKit storefront. It enables deterministic mounted-render tests without adding a shipping launch flag or weakening the unknown/non-US storefront gate.

## Validation and limitations

- Core DeveloperSupportTests: 9 tests passed, including parameterized storefront and unsafe-URL cases.
- Native/website destination parity: 2 Python checks passed. No receiving destination changed.
- Final actual mounted render suite: About passed, Support at widths 375/430/768 passed, unavailable storefront passed. Independent empty-achievements and solo-helper renders also passed.
- The complete supplemental suite still exits 65 because the unchanged Backup render does not recognize its Import button within the existing 900-point viewport. That failure was preserved, not removed or rewritten to claim a green suite.
- The first new geometry assertions incorrectly treated Vision word boxes as whole lines and compared pixel coordinates to points. Those test assumptions were corrected using unmodified recognized currency/address word boxes and the PNG scale. Initial failure evidence remains private.
- Two attempted method-name-filtered runs executed zero tests despite xcodebuild success. They are not validation evidence. `layout-confirmed.xcresult` is the final actual suite result, with screenshots and real executed tests.
- Actual final narrow and wide screenshots were visually inspected for grouped rows, full wrapped addresses without visual hyphens, and legible Done buttons. About's compact Support link and privacy content were also inspected.
- Physical iPhone and native Mac pixels were not independently captured. No WebDriverAgent/helper was installed, and no separate native Mac test app was launched. The read-only reviewer did not deliver usable findings before being stopped and is not counted as approval.

## Phone delivery

The existing physical iPhone app `app.hashfleet` was updated from build 13 to build 14 using the existing production ad hoc identity, provisioning profiles and shared app group. No uninstall, data reset, profile/account creation, TestFlight upload or App Store submission occurred.

All three final app/extension signatures, build identities, device provisioning eligibility, shared group and production APNs entitlement were checked before installation. The signed shipping executable contains all three original destinations. The normal install and launch receipts are retained privately.

Fresh before/after comparisons, taken before the new build's first normal launch, verified all four accessible saved files totaling **14,635,654 bytes** byte-identical. All **29 main preference keys and values** remained unchanged. The shared container remained unchanged. iOS rotated the main data-container UUID, so preservation was verified by contents rather than assuming path stability. Keychain and inaccessible root-group files were not independently read.

## Final launch and Mac hygiene

The normal phone launch succeeded, and read-only process inspection showed the build 14 main app and widget extension running. The canonical Mac app remained PID 6438 throughout and was not reinstalled, restarted or used for a separate demo/test launch. This delivery updates the phone only, not the installed Mac binary.

All generated phone and simulator source `.app` bundles were unregistered and reversibly retired to owner Trash paths ending in `.retired`. The signed phone artifact is retained as a ZIP. Final physical scans found no generated Fleet applications outside the canonical installation. Existing-path LaunchServices checks by bundle identifier, Dock recent entries and canonical Mac signature validation all passed, with only `/Applications/Hash Fleet.app` remaining.

Private evidence and ZIP artifacts are under the owner-only nonindexed staging directory `~/.jcode/scratch/hashfleet-layout-20261101.noindex`. No wallet addresses or private backups are included in this report.
