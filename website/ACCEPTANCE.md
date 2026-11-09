# HashFleet website acceptance evidence

Checked October 8, 2026. This report separates the functioning local website from public-domain publication. It does not turn local test success into a claim that `hashfleet.app` is live.

## Interpretation audit

The initial request was typo-filled: make a website showing an interactive Mac app, iPhone app, and terminal. The subsequent domain registration and supplied native miner artwork supported the HashFleet product interpretation.

Initial interpretations that were not explicitly confirmed when implementation began:

1. “has fleet” refers to this repository's HashFleet product.
2. “in terminal” means a third interactive terminal experience alongside the Mac and iPhone previews.
3. “interactive apps” means native-looking, functioning web previews, not SwiftUI binaries streamed into a browser or a pixel-exact native screen reproduction.
4. Supplying `hashfleet.app` implies eventual publication. It does not authorize hosting purchases, contract changes, password resets, or unrelated server uploads.

At **October 8, 17:24:10 UTC**, the user explicitly said they liked the website and asked Cow to implement its chart and organization ideas in the native app. This confirms approval of the demonstrated visual direction. It does not establish native binary streaming, exact feature parity, a native release, or public-domain publication.

Early implementation decisions were rechecked against that interpretation. The first website already had the three interactive surfaces, supplied artwork, HashFleet identity, and correct canonical domain. Fictional data and the lack of a native-app stream are disclosed. Native `README.md` confirms the Mac/CLI packaging, iOS product, local-first behavior, compact cards, and source-only release limits. The website's Energy screen is an illustrative browser estimate, not a claim of pixel-exact native feature parity. No public download or repository destination was invented.

Live fleet telemetry, native app distribution, physical iPhone testing, and a public launch are not substituted with browser fixtures and are not claimed complete.

## Real acceptance path

The exact upload ZIP was extracted into an isolated scratch directory and served by installed Apache `2.4.67`, bound only to loopback. Its own `.htaccess` supplied the response headers. The app under test was the actual compiled React website, not imported/copied app source or a substituted API fixture. Sample data is intentional website content.

- Direct HTTP checks: **24 actual requests**, including served bytes, MIME types, five security headers, directory protection, missing source/secrets, missing routes, and a POST to a nonexistent local backend route.
- Browser checks: **91 checkpoints on the Apache-served artifact**, completed at **16:41:24 UTC**. No response interception in this mode. Six unique requests, all to that same website origin. No browser or CSP errors.
- Unit/type checks: **83 tests passed** at **16:41 UTC**. These supplement, not replace, the actual HTTP/browser path.
- Archive: all **12 production files** match the final ZIP byte for byte. The ZIP also contains two directory entries.

Earlier Vite-preview checks used injected CSP. They remain supplemental evidence only. The committed browser tool now distinguishes `server-response` from `injected-preview-test` and rejects unsupported/error-page origins instead of silently falling back to a local passing site.

## Website requirement-to-observation map

All PASS results below refer to the interpreted local website scope, not to public hosting or native binaries.

| ID | Requirement / changed public output | Concrete end-user or HTTP check | Observed result |
| --- | --- | --- | --- |
| W1 | HashFleet identity, supplied artwork, and domain metadata | Open actual homepage, inspect title/heading, GET icons/artwork/social card/sitemap | PASS. Title is `Hash Fleet \| Your hash. Your hardware.`, one main heading, all image responses are PNG and byte-match the build, domain metadata uses `hashfleet.app`. |
| W2 | Interactive Mac workspace | Click Overview, chart `24h`, My miners, search `Naja`, unmatched search, clear search | PASS. Five miners initially, two Najas after filtering, explanatory empty state, five after clearing, and an accessible `Illustrative 24h` chart replaces the previous range. |
| W3 | Mac details and useful Energy interaction | Open MacBook Pro details and return. Operate full Energy slider with End/Home while hero Energy is also open | PASS. CPU displays kH/s and two `Not reported` values. Details start with focused Back. Full estimate becomes `$3.26`, then `$0.07`; hero slider remains `0.12`. Both slider IDs and label targets are distinct. |
| W4 | Interactive iPhone experience | Scroll to CPU, open detail, return, open Network, change Compact miner cards in Settings, revisit Fleet | PASS. Five cards, honest missing CPU sensors, focused Back/return control, scroll restoration, trusted-VPN guidance, and a measured decrease in card height. Preference survives platform switching. |
| W5 | Interactive terminal | Type `hashfleet status --json`, use history keys, click fictional host filter, help, and Clear | PASS. JSON has five miners, CPU normalized rate `0.0000021` GH/s, omitted unavailable power/temp, working history/draft restoration, `2/2 online` filter, and usable status after Clear. |
| W6 | Terminal safety and native limitations | Type explicit XMRig host and shell syntax | PASS. XMRig limitation is explained. `hashfleet status; echo unsafe` reports `Nothing was executed`. No shell or hardware operation occurs. Browser utility commands are distinguished from native CLI commands. |
| W7 | Responsive Mac/iPhone/terminal layouts | Exercise all three selected panels at 320, 375, 768, 1024, and 1440px | PASS. Document scroll width equals the viewport at every checked combination. Mobile navigation opens and closes after selection. Phone content remains internally scrollable. This is Chromium viewport testing, not a physical iPhone/Safari claim. |
| W8 | Keyboard, labels, and modal focus | ArrowRight/End/Home on tabs, three modal-close paths, privacy close, detail navigation | PASS. Selected tab receives focus, every `aria-controls` target exists, only one panel is visible, all rendered IDs are unique, and Escape/button/backdrop restore the correct invoker. |
| W9 | Clear sample data, privacy, and release availability | Read preview/FAQ/privacy disclosures, click Get Hash Fleet, monitor browser requests and cookies | PASS. Fictional readings and browser previews are disclosed, two native releases say `Coming soon`, cookie list is empty, and only same-origin website assets are requested. No public native release is promised. |
| W10 | Polished presentation and secondary interactions | Toggle light/dark, open all six FAQs, examine generated desktop/375px screenshots | PASS. Theme state changes in the document, each native disclosure opens, and desktop/phone captures show the supplied gold/graphite identity. The user explicitly approved the website's visual direction at 17:24:10 UTC and requested its chart/organization ideas for the native app. This is design approval, not native or public-domain acceptance. |
| W11 | Deployable static output, not a development-only demo | GET `/`, assets, icons, `robots.txt`, sitemap, and social image from actual Apache | PASS. Homepage GET/HEAD 200, HTML/CSS/JS/PNG/XML MIME types correct, served build-file bodies byte-match `dist/`. No Node backend is needed to serve this artifact. |
| W12 | Real hosting safety boundaries | Request `/assets/`, `/images/`, `/.htaccess`, source/secret paths, missing page/API, and nonexistent local POST route | PASS locally. Directories and `.htaccess` return 403. `.env`, `.env.local`, `.git/config`, `src/App.tsx`, `package.json`, and missing routes return 404. All 24 responses carry the five intended security headers. Hidden-file denial also depends on the supplied Apache test-host config, not only the site's `.htaccess`. |

## Observed improvement, not just inspection

Two distinct real deployment artifacts were served through the same Apache boundary and exercised with the same browser actions at **16:37 UTC**. No app-source imports or response interception were used.

- Previous intermediate ZIP: `hashfleet-site-2026-10-08.zip`, module `index-DTWFnXqT.js`.
- Current final ZIP: `hashfleet-site-2026-10-08-final.zip`, module `index-DwHthC12.js`.

| End-user behavior | Previous actual artifact | Current actual artifact |
| --- | --- | --- |
| Hero CTA transfers focus to Mac tab | false | true |
| Mac detail starts with focused Back | false | true |
| iPhone detail starts with focused Back | false | true |
| iPhone return focuses the selected miner | false | true |
| iPhone detail starts at its top | scrollTop 160px | scrollTop 0px |
| iPhone Fleet preserves prior inner scroll after Back | scrollTop 0px, position lost | scrollTop 233px, position restored |

The current artifact also passes the full keyboard/modal/navigation suite. Earlier review-discovered duplicate Energy IDs and dangling tab relationships are now directly checked in the rendered DOM. This is mechanical usability evidence, not a claim of user design approval or full accessibility certification.

## Public-domain acceptance map

The live public boundary was exercised, not replaced with a local result.

At **16:15:22 UTC**, DNS resolved and HTTPS failed in curl with exit **35**, TLS internal alert, before an HTTP response. Actual Chromium navigation showed **“This site can’t provide a secure connection”** and **`ERR_SSL_PROTOCOL_ERROR`**. Certificate validation was not bypassed.

At **16:27:37 UTC**, plain HTTP returned 200, but its **605,912-byte HTML did not match** the prepared **1,327-byte** index. This response is not evidence that the HashFleet build is published. Account-tab inspection found no open IONOS account/login tab, and the browser bridge was unresponsive. That does not establish cookie authentication, contract availability, or absence of hosting.

| ID | Public acceptance requirement | Real check / observation | Status and remaining dependency |
| --- | --- | --- | --- |
| P1 | Registered domain resolves | Live NS/A/AAAA queries returned records | OBSERVED. Resolution is not proof of the correct webspace target or an available hosting contract. |
| P2 | Valid HTTPS for `hashfleet.app` | Real curl and Chromium navigation failed TLS | FAILED acceptance. Certificate/transport provisioning must be repaired through authorized hosting. Exact certificate validity could not be evaluated. |
| P3 | Public homepage is this build, not another response | Actual HTTP body compared with production index | NOT MET over HTTP. Bytes differ. HTTPS homepage identity is BLOCKED by P2. |
| P4 | Correct domain-to-dedicated-directory routing | Hosting account/webspace target inspection | BLOCKED. No accessible authenticated hosting session. No existing site root was overwritten. |
| P5 | Public CSS, JS, images, icons, metadata files all load | HTTPS GETs and MIME/byte checks required on the domain | BLOCKED before HTTP by P2. Local W11 is only package-readiness evidence. |
| P6 | Public security headers, protected files, error routes | Domain GET/HEAD, 403/404, and header checks required | BLOCKED by P2/P4. Local W12 does not establish IONOS header modules or override permissions. |
| P7 | Public Mac/iPhone/terminal end-user workflows | Run the same browser tool on the verified HTTPS origin | BLOCKED by P2/P4. The tool now refuses an SSL-error-page origin without falling back to localhost. That refusal was observed. |
| P8 | HTTPS redirection after TLS is valid | Live HTTP HEAD returned 200, not an HTTPS redirect | NOT MET. Do not enable or claim successful HTTPS redirection before P2 is fixed. |
| P9 | Native app/repository links point to real releases | Native source README and website download dialog | HONESTLY UNAVAILABLE. `Coming soon` remains correct. Publishing this website does not create signed Mac or App Store/TestFlight releases. |
| P10 | Safe authorized deployment preserves other sites/mail | Account ownership, selected contract/directory, and proposed changes must be verified | BLOCKED on hosting access. No purchases, credential guesses, password resets, DNS mutations, unrelated-server uploads, or mining-hardware changes were performed. |

**Public publication is not complete.** The available local work and actual public failure observations are complete. Further publication requires authorized hosting access, correct routing, valid HTTPS, and the blocked acceptance checks above.

## Post-approval and handoff recheck: October 8, 17:33 to 17:37 UTC

The public website payload did not change during the handoff. The final ZIP again byte-matched all 12 files in `dist/`; its SHA-256 remains `6d32f0ee85ce78d7e99735516d5e1801a20b1cfd9687bf5debc033122bfd6359`. The new approval and handoff documents are not in that upload archive.

- **W1-W12 replay:** the exact extracted final artifact again passed 91 named end-user browser checkpoints and 24 actual HTTP observations through isolated Apache. The actual server supplied CSP with no response interception. The browser requested six same-origin resources and recorded no browser/CSP errors. The website-only type check and all 83 unit tests also passed after the documentation edit.
- **Measured improvement replay:** the two different archived production builds again showed all four checked focus behaviors changing from false to true, iPhone detail scroll changing from 160px to 0px, and return-to-Fleet scroll changing from a lost 0px position to a restored 233px position. This is actual deployed-artifact interaction, not a copied-source fixture.
- **Design acceptance:** the user's 17:24:10 UTC approval closes the previously unavailable visual-preference observation. It does not claim full accessibility certification, physical Safari testing, or native binary execution in the browser.
- **P1-P3/P8 public replay:** actual DNS still resolved at 17:34:40 UTC. HTTPS again failed with curl exit 35 before any HTTP response. Plain HTTP returned 200 and 605,912 bytes, not the 1,327-byte prepared homepage, and did not redirect. No certificate validation was bypassed or redirect followed.
- **P7 end-user boundary:** actual Chromium navigation at 17:36 UTC failed with `ERR_SSL_PROTOCOL_ERROR`. Its error page was observed again at 17:37 UTC. Running the acceptance tool there rejected the unsupported null origin and exited 1 instead of falling back to a local passing target. These failures are retained, not counted as a public acceptance pass.
- **P4-P6/P10 remain externally blocked:** accessible authorized hosting, correct directory routing, and valid HTTPS are still required. Public assets, security headers, protected routes, and public interactive workflows cannot be accepted before that transport/routing boundary works. Local W11/W12 remain package-readiness evidence only. No hosting purchase, account/password action, DNS mutation, upload, native-app operation, or hardware operation was performed by this audit.
- **P9 unchanged:** native downloads and source destinations remain honestly unavailable. The website does not manufacture native distribution.
- **Cow acknowledgement:** the actual coordinator replied at 17:30:40 UTC that it received the committed brief and will finalize its current demo-only coverage acceptance before planning native charts and hierarchy improvements. Shared native sources, app builds, and simulator operations were left untouched. Receipt is verified; native implementation is still follow-up, not completed work.

New evidence is retained separately, without replacing earlier receipts: `output/static-host-approval-acceptance-result.json`, `output/playwright/approval-final-result.log`, `output/playwright/approval-comparison-result.log`, `output/approval-evidence-verifier.json`, `output/public-domain-approval-*`, `output/playwright/approval-public-*`, and `output/public-browser-approval-observation.json`.

The owned temporary Apache host reached its configured duration limit after the successful acceptance replay. No listeners remained on its test ports 4175/4176 at 17:37 UTC; the existing user's preview on 4174 still returned HTTP 200. The public-domain and test-tool failure receipts are preserved, and no native acceptance result is credited to this website audit.

## Evidence files

Generated evidence is ignored under `output/`, not included in public upload contents:

- `playwright/apache-final-result.log`: named end-user checkpoints and actual origin/CSP source.
- `static-host-acceptance-result.json`: all 24 actual HTTP observations.
- `playwright/navigation-comparison-result.log`: measured before/after artifact behavior.
- `public-artifact-privacy-check.json`: 11 public text files, five positive detector controls, no findings.
- `deployment-payload-check.log`: exact archive/build comparison and preserved ENOBUFS harness limitation/remediation.
- `public-domain-acceptance.json`, `public-domain-http-identity.json`: public transport and identity observations.
- `playwright/public-domain-open.log`, `public-domain-snapshot.log`, `public-target-guard.log`: real browser SSL failure and no-fallback guard.
- `playwright/desktop-final.png`, `mobile-375.png`, `iphone-375.png`, `terminal-375.png`: actual served UI captures.

The privacy rescan uses fail-fast Node assertions because `rg` was not available in the shell. Its detectors were checked with positive controls before scanning. It is bounded text-pattern evidence, not exhaustive secret detection or binary metadata scanning.

## Reproduce actual static-host acceptance on this Mac

Do not use `sudo`, alter system Apache config, or replace a public website. Ports 4175 and 4176 must be unused. This macOS-only fixture was tested with the installed Apache modules, not the eventual IONOS host.

```sh
cd website
: "${JCODE_SCRATCH_DIR:?Set JCODE_SCRATCH_DIR to an existing owned scratch directory}"
export HASHFLEET_ACCEPTANCE_ROOT="$(mktemp -d "$JCODE_SCRATCH_DIR/hashfleet-apache-XXXXXX")"
export HASHFLEET_ACCEPTANCE_USER="$(id -un)"
export HASHFLEET_ACCEPTANCE_GROUP="$(id -gn)"
mkdir -p "$HASHFLEET_ACCEPTANCE_ROOT/site" "$HASHFLEET_ACCEPTANCE_ROOT/previous"
unzip -q output/hashfleet-site-2026-10-08-final.zip -d "$HASHFLEET_ACCEPTANCE_ROOT/site"
# Optional archived intermediate artifact for the before/after comparison:
if [ -f output/hashfleet-site-2026-10-08.zip ]
then
  unzip -q output/hashfleet-site-2026-10-08.zip -d "$HASHFLEET_ACCEPTANCE_ROOT/previous"
fi
/usr/sbin/httpd -t -f "$PWD/Tools/apache-acceptance.conf"
/usr/sbin/httpd -f "$PWD/Tools/apache-acceptance.conf" -DFOREGROUND
```

With that isolated server running, execute in another terminal from `website/`:

```sh
node Tools/static-host-acceptance.mjs
PWCLI="$HOME/.jcode/skills/playwright/scripts/playwright_cli.sh"
"$PWCLI" -s=hashfleet-static-check open http://127.0.0.1:4175/
"$PWCLI" -s=hashfleet-static-check snapshot
"$PWCLI" -s=hashfleet-static-check run-code "$(cat Tools/browser-acceptance.js)"
"$PWCLI" -s=hashfleet-static-check eval '() => window.__hashfleetAcceptance'
if [ -f output/hashfleet-site-2026-10-08.zip ]
then
  "$PWCLI" -s=hashfleet-comparison-check open http://127.0.0.1:4176/
  "$PWCLI" -s=hashfleet-comparison-check snapshot
  "$PWCLI" -s=hashfleet-comparison-check run-code "$(cat Tools/navigation-regression.js)"
  "$PWCLI" -s=hashfleet-comparison-check eval '() => window.__hashfleetNavigationComparison'
fi
```

Stop only the owned scratch Apache process afterwards. Keep the separate user's preview on port 4174 untouched.
