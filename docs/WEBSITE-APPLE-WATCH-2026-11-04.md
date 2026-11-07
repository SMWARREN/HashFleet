# Apple Watch website delivery, November 4, 2026

## Request and delivered scope

The owner requested Apple Watch imagery and interactivity on the Hash Fleet website, reported moving both App Store versions to automatic release, and requested Astra if new media generation was necessary. This delivery changes the website only. No App Store API, release-setting change, build upload, physical device operation, miner request, notification send, email send or payment was performed.

- Published at **2026-11-04 04:54:55 UTC** on `https://hashfleet.app/`.
- Implementation commit: `f607ab7` (`feat: add authentic interactive Apple Watch website tour`), exactly 19 owned website files.
- A fourth product tab, **Apple Watch**, sits between iPhone and Terminal. The hero Watch opens and focuses that tab.
- Five real native captures support step selection, Next, history-aware Back, Reset, captured Back/Add navigation, keyboard operation, readable descriptions and image-failure recovery.
- Light/dark layouts and responsive Watch case/strap styling preserve the site's gold-and-graphite design. CSS decorates the device frame, not the app pixels.
- The Watch entry in the download dialog says it is included with the iOS app. No unverified download URL or new server route was introduced.
- Existing Mac, iPhone, terminal, help/contact, privacy and optional-support behavior remains covered by acceptance checks.

## Native-image provenance and product boundaries

All five PNGs are byte-identical to original 368×448 native Watch UI-test attachments, totaling 191,291 bytes. Their source is the submitted build 20 release revision `a10fec115ba3f74ceed100f023eb235d4a009cd1`. Exact source/public hashes, dimensions and provenance are in `website/src/lib/watch-captures.json`; `website/Tools/prepare-watch-captures.py --source <native-watch-attachments> --verify` independently checks identity. The existing 18-image native manifest was not replaced or regenerated.

The captured screens cover fleet summary, miner readings, lower miner details, discovery with no compatible devices found, and local manual setup. Captured timestamps and fictional readings remain unchanged and are explicitly disclosed. Website controls navigate captured images only. They do not scan a visitor's network, connect to a Watch/miner, edit a native form or change hardware settings. No image model was needed because genuine captures already existed, so Astra was not invoked.

The Watch FAQ was checked against the native setup coordinator, discovery/manual-setup views, import confirmation and lifecycle code. Optional iPhone transfer imports miner names and local addresses with confirmation on the Watch, not miner readings or credentials. The native Watch app obtains readings directly from miners. The website does not promise continuous background monitoring. The documented native minimum is watchOS 26.5.

## Validation and evidence

Final production source passed TypeScript/build checks and **175 unit tests**. Real-browser checks against the production preview and actual public site passed:

| Suite | Local checks | Public checks |
| --- | ---: | ---: |
| Watch captures, tour, keyboard/focus, responsive themes and recovery | 112 | 113 |
| Original native Mac/iPhone captures and CLI | 210 | 211 |
| Public contact and help | 85 | 85 |
| Privacy permalink and dialog | 49 | 49 |
| Optional support | 64 | 64 |

The Watch suite verifies exact hashes of all five served native PNGs, every screen, controls, keyboard tab adjacency/Home/End, readable transcripts, reload/reset boundaries, reduced motion and both themes at 320/390/768/1024/1440px. Normal public checks use real responses, with no response interception. Invalid-image recovery uses a separate, explicitly intercepted failure fixture. Public desktop and phone screenshots were visually reviewed.

Earlier failed runs are retained. Native regression navigation now waits for the selected image to decode before advancing, preserving all original scroll/focus and zero-failed-request assertions. Initial public privacy runs recorded a browser favicon abort caused by the old test's same-document hash navigation followed immediately by its fallback reload. A traced run established that sequence. All **49 original privacy assertions, unchanged**, then passed from the real support document, making the initial privacy navigation cross-document. The assertion-source SHA-256 and request trace are preserved. No privacy assertion, production response or favicon was suppressed or rewritten.

The optional configured read-only audit worker failed its provider request without a report or edits. No successful worker audit is claimed. The coordinator performed the source audit and executed independent deterministic acceptance verifiers.

An independent precommit verifier fetched **all 37 production build files**, confirmed exact local/public bytes, MIME types, existing restrictive security headers and no-store policy, rechecked all ten local/public suite results and checked the original owner worktree diff byte-for-byte. Postcommit verification repeats those checks after this document is committed. These are automated Chromium/HTTP checks, not a claim of physical Safari, VoiceOver or every device combination being tested.

## Narrow publication and preservation

Only nine frontend files were promoted: two new hashed JavaScript bundles, one hashed stylesheet, five Watch PNGs and `index.html`. The files were privately staged, digest-validated and published with assets first and the index last. Previous hashed assets remain available for rollback.

- Publication manifest SHA-256: `3eaa0fde235a865bf9487b599e1eed3dcc70b4b24c2d95c03cfae1f4f28716bb`.
- Exact deployed index SHA-256: `a76d4d6be4eb6531579825eec8a32c634e1b7eb18e1e533d3b95c4be96900bba`.
- Private original-index rollback copy: `/home/USER/hashfleet-private/backups/20261104-045454-watch-website/index.html`.
- Publication and independent readback verify unchanged unrelated public files, support page, server policy, private service/configuration hashes and permissions, and crontab. The publisher does not write the live database. The public contact remains `support@hashfleet.app`, without the removed phone number or old Gmail address.
- User-owned dirty files and untracked work were not staged. No native application or server backend source was edited.

Task evidence is under `/Users/USER/.jcode/scratch/hashfleet-watch-website-20261104T0411.noindex`. The final verifiers are `verify_public_watch_release.py` with `precommit`/`postcommit` phases. The separate privacy driver is `run_privacy_settled.mjs`; its final run starts from the real support document and preserves the unchanged assertion source.

Durable preservation target: `/Users/USER/Library/Application Support/HashFleetBackups/2026-11-04-watch-website.noindex`. `preserve_watch_website_delivery.py` saves tracked website source, exact production files, this document, task receipts/scripts/logs, successful and failed browser artifacts, and a verified committed-history Git bundle. It excludes regenerable caches and does not copy deployment keys or local environment credentials. Completion is recorded only by the independent saved-file/hash/ZIP-entry checks in `backup-verification.json`, with a duplicate receipt in the task evidence folder.
