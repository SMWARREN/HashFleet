# One React entry with real HTTP statuses

## Corrected conclusion

The user's October 25, 2026 suggestion works on the verified host. The earlier
claim that only an administrator include could fix the denied-response headers
was too broad. React cannot change HTTP response headers, but site-level Apache
rules can route an inherited internal error-document request to the React entry,
apply the intended site headers and preserve the original 403 or 404.

The header-only probe at 05:17 UTC missed that later request phase. Its raw
failure and the original strict HTTP audit remain retained, not relabeled as
successful. A broad rewrite probe at about 05:36 UTC contradicted the earlier
inference: its own prediction assertion failed because the site marker actually
appeared on the two affected denials. The narrower 05:41 UTC probe passed all
30 before/during/after observations. Both probes restored the original policy
and verified unchanged protected state. Private receipts are under
`/Users/USER/.jcode/scratch/hashfleet-spa-probe-20261025/`, including
`probe-remote.log`, `probe-remote-v2.log` and `result-v2.json`.

## Routing and safety contract

| Request | Apache result | React presentation / acceptance |
|---|---|---|
| `/`, `/index.html` | 200, original entry | Original homepage and default Mac preview |
| `/demo`, `/demo/mac` | 200, internal entry | Mac preview selected and scrolled into view |
| `/demo/iphone`, `/demo/terminal` | 200, same entry | Corresponding preview selected, original URL retained |
| Unknown public path | 404, local error entry | Generic unavailable page, `noindex`, fixed home link |
| `/.env.local`, `/.git/config`, `/.htaccess` | Real 403 retained | Same generic unavailable view, all five intended headers |
| API, companion, assets, images, source, private and well-known namespaces | Existing files or normal server denial | Excluded from SPA error presentation, never a missing-file soft 200 |
| HEAD / non-GET page request | HEAD keeps status with empty body, POST demo stays 404 | No API forwarding, mutation or external redirect |

`Server/public/.htaccess` and `website/public/.htaccess` have an identical marked
React-routing region. Public demo routing is allowlisted and limited to GET/HEAD
with real files and directories preserved. The separate inherited-error rule
requires `REDIRECT_STATUS` 403 or 404. All substitutions are fixed `/index.html`,
not user-supplied destinations. Existing HTTPS, authorization, private-file,
no-store and security-header rules remain intact. The deployed bundle uses the
Server policy, including its `no-referrer` value. No global Apache, WAF, sibling
site, service activation or private-state change is needed.

`SiteEntry.tsx` selects the view from `location.pathname`. It does not fetch the
path, echo it into markup, persist it, or treat it as a redirect destination.
Native capture tours and CLI output remain unchanged. The unavailable page does
not pretend a blocked request is successful or expose the requested file.

## Requirement-to-check map

- `src/lib/routes.test.ts`: 22 homepage, demo, invalid, private and malformed-path
  cases. The complete frontend suite has 134 tests.
- `Server/tests/react_entry_test.py`: seven tests using actual isolated Apache,
  inherited early denials and synthetic private files. Checks exact entry bytes,
  one value per expected header, 403/404 preservation, namespace exclusions,
  unchanged assets/directories, GET/HEAD/POST behavior, matching policy regions
  and the unchanged production HTTPS rule. The loopback fixture removes only
  that HTTPS redirect so local HTTP is possible. It loads no actual API code,
  private configuration/database or mining endpoint.
- `Tools/run-route-acceptance.mjs`: actual Apache or HTTPS responses, with no
  response interception or injected CSP. Verifies selected previews, all five
  headers, no external redirect, real statuses, generic unavailable UI,
  `noindex`, keyboard home recovery, 320px layout, no API calls/persistence and
  no runtime errors or unexpected failed requests.
- The first route-browser attempt exposed a real 320px overflow inherited from
  the homepage's non-wrapping heading style. Only the unavailable heading's
  wrapping was fixed. The original narrow-screen assertion was retained.
  A rerun encountered the old orphaned fixture and still failed that assertion.
  The fixture now refuses occupied ports and verifies its exact entry bytes.
  The owned stale process was stopped, and the final run used a fresh fixture
  whose lifetime and cleanup were tied to the browser runner.
- `Tools/run-native-parity.mjs`: original 186 local / 187 public product checks,
  all 18 captured assets, native tour and CLI behavior. These assertions are not
  rewritten to accommodate the routing change.
- Existing five Apache-header tests, ten installer/rollback tests and nine
  retired-endpoint guards remain unchanged and separately run.
- `Tools/public-parity-assets.mjs` remains the original strict 40-response audit.
  Header normalization must not hide its independent Git-path expected-404
  versus actual-403 mismatch. A 403 is still a denial. Do not change the status
  or the historical expectation merely to manufacture a green audit.

## Publication status

Local final acceptance passed at **05:53 UTC on October 25, 2026**: 134 unit
tests and TypeScript/build, seven React-entry Apache tests, the unchanged five
header tests, ten installer tests and nine retired-endpoint guards. All **126
real-Apache route-browser checks** passed in
`website/output/playwright/20261025T055323399Z-react-entry-local/result.json`.
All **186 original local product-browser checks** passed in
`website/output/playwright/native-parity-20261025T055326489Z-native-parity-local/result.json`.
Both browser runs reported no runtime errors or unexpected failed requests.

Published implementation **`b6f3dbd`** at **05:55:18 to 05:55:20 UTC on
October 25, 2026**, using the existing tested installer and exact 39-file
allowlist. The private overwritten-file backup is
`hashfleet-private/backups/20261025-055519-99730b9a`. Archive SHA-256:
`17f9bccebfd11f91af3b288e4a648bb86b423c5461268a8fb65bc0c2dadf249d`.
New artifact names are `index-BL37y5ax.js` and `index-DEpxmuHH.css`.

`/Users/USER/.jcode/scratch/hashfleet-react-entry-publish-20261025T055350Z/deployment-live.log`
verifies that the eight packaged service/retirement files already matched the
host, the old `.htaccess` matched its expected restored hash before promotion,
and protected configuration/database bytes and permissions, service/API code
and crontab digest remained unchanged. No private configuration was created or
replaced. The entry and policy exactly match the validated bundle. The read-only
provider check still reports `provider_ready: false`; activation was not
performed. No administrator include, global configuration or sibling site was
changed.

Actual public acceptance completed at **05:56 UTC**:

- **126 route-browser checks passed** in
  `website/output/playwright/20261025T055554821Z-react-entry-public/result.json`,
  using the real HTTPS responses and headers, without interception or injected
  CSP. The unavailable page was also captured and visually reviewed at 320px
  in that directory's `unavailable-mobile.png`.
- **187 unchanged product-browser checks passed** in
  `website/output/playwright/native-parity-20261025T055554808Z-native-parity-public/result.json`,
  including all 18 native captures. Both public browser runs reported no runtime
  errors or unexpected failed requests. These are Chromium checks, not physical
  Safari, WCAG or APNs certification.
- `public-audit.json`, checked at **05:56:05.261 UTC** in the private publication
  receipt directory, records **40 real responses**, **31 exact build matches**,
  and **all five intended headers on every response**, including both formerly
  affected denials. All nine sensitive/missing/directory paths remain denied.
  The unchanged strict collector still exits **1**, with exactly one finding:
  `/.git/config: HTTP 403, expected 404`. Its eight original header mismatches
  are fixed. The actual protected-path 403 and the historical expected-404
  assertion are both retained, not weakened to manufacture a completely green
  audit. A blocked-path status mismatch is not a private-file disclosure.

The local Apache fixture was stopped after browser acceptance, with no listener
left on 4175. Native app, mining, notification-service and installer sources are
unchanged from this routing task's baseline `d0e0290`.

## Primary references

Apache 2.4 documentation, checked October 25, 2026:

- Custom error responses and the guaranteed `REDIRECT_STATUS` on local redirects:
  https://httpd.apache.org/docs/2.4/custom-error.html
- Internal remapping and front-controller routing:
  https://httpd.apache.org/docs/2.4/rewrite/remapping.html
- Per-directory rewrite processing and the `END` flag:
  https://httpd.apache.org/docs/2.4/rewrite/flags.html

These describe the mechanism. The reversible live probes and final actual
responses establish behavior on this particular host, not on every possible
upstream firewall or hosting setup.
