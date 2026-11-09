# Website denial-response headers

## Correction on October 25, 2026 UTC

The earlier administrator-only conclusion below was too broad. At 05:36 UTC,
a site-level rewrite served the React entry for both affected denials, applied
all five intended headers and preserved the real **403** status. A narrower
follow-up at 05:41 UTC reproduced that result, kept unknown pages **404**, and
restored the original policy and protected state. The successful rule handles
the inherited **internal error-document request**, which the earlier header
and error-message-only probe did not handle.

The implementation and current publication receipts are recorded in
`WEBSITE-REACT-ENTRY.md`. No hosting-administrator include is required for this
verified site-level solution. React chooses the view, while Apache supplies
the actual response headers and status. The original strict audit remains
unchanged, including its separate expectation of 404 instead of the retained
403 for `/.git/config`.

The site-only solution was published at **05:55 UTC** and verified against real
HTTPS responses at **05:56 UTC**. All eight missing/conflicting-header findings
are fixed. The strict audit retains only the separate Git-path status mismatch.
All 126 public route checks and 187 original product checks passed. See the
React-entry document for the exact receipts and protected-state verification.

## Historical outcome at 05:24 UTC, superseded

The production website already sends the intended five security headers on its
homepage, build assets and ordinary 403/404 responses. Two host-generated 403
responses, `/.env.local` and `/.git/config`, ignore the site policy. Neither
requested private file is served. This is a response-policy mismatch, not
evidence of a compromise.

React cannot repair the original HTTP response after it reaches the browser.
The existing `Server/public/.htaccess` already uses `Header always set`. Apache
supports these headers and local `ErrorDocument` overrides in `.htaccess`, but
they apply only when that directory configuration participates in the request.

### Reversible live proof

Private receipts are under
`/Users/USER/.jcode/scratch/hashfleet-denial-headers-20261025/`.

- `baseline-public.json`, checked at **05:13:37 UTC**: both affected paths return
  403, `X-Frame-Options: SAMEORIGIN`, `nosniff`, and no site CSP, Referrer-Policy
  or Permissions-Policy. The baseline includes status, all response headers,
  body length and SHA-256, with bodies retained only for denied/missing pages.
- `probe-local.json`: an isolated loopback Apache accepts the candidate and
  applies its diagnostic header and local HTML error message on all five test
  routes. Production access controls and HTTPS rules are unchanged in the
  candidate. The loopback fixture deliberately does not load mod_rewrite.
- `probe-remote-v2.log`, **05:17:26 to 05:17:28 UTC**: a brief, backed-up
  site-only override adds `X-HashFleet-Policy-Probe` and custom 403/404 messages.
  The homepage, `/.htaccess`, missing page and `/assets/` receive the marker.
  Both affected paths receive neither the marker nor custom error message,
  retain 403, and keep the identical baseline error-body hash.
- The remote probe has an exit trap that restores the original policy on
  failure as well as success. Its final receipt verifies original policy
  SHA-256 `11f688698b8253cdb2ab37e4032913b7ab655d920ee49759c49c4c7a6ae6a883`
  and unchanged config/database bytes and permissions, service/API code and
  crontab digest. A subsequent read-only check found zero diagnostic headers
  on the restored homepage.

The observations demonstrate that the two responses bypass the site override.
They are consistent with a denial before directory configuration is applied,
but do not identify a specific WAF, Apache module or server rule. The account
has no readable Apache configuration/error log or writable cPanel per-domain
include at the checked locations. No administrator access was attempted.

Two diagnostic wrappers failed before the final receipt: the first isolated
Apache shutdown terminated its runner's process group before remote work; a
second stopped at a malformed diagnostic awk expression after one homepage
request and restored the policy through its exit trap. The final runner uses
an isolated Apache process group and the corrected filter. Those failed
background receipts remain failed, not counted as complete live probes.

## Historical administrator alternative, not deployed or required

`Server/apache/hashfleet-security-headers.conf` is a proposed **domain-only**
virtual-host include. It copies the exact five site policies and clears the
other Apache header table to avoid conflicting duplicates. It changes no
authorization, rewrite, WAF, cache, HSTS, API or private-file policy. It is
intentionally outside the website installer's allowlist.

On a cPanel/EasyApache 4 host, the documented single-domain locations are:

```text
/etc/apache2/conf.d/userdata/ssl/2_4/ACCOUNT/hashfleet.app/hashfleet-security-headers.conf
/etc/apache2/conf.d/userdata/std/2_4/ACCOUNT/hashfleet.app/hashfleet-security-headers.conf
```

Only the hosting administrator should review and apply it in the actual Hash
Fleet virtual host. Do not install it at global, account-wide or sibling-site
scope. cPanel requires a configuration rebuild and Apache restart to activate
userdata includes. No such action, support-ticket send, security exception or
administrator configuration change has been performed or authorized here.
If the real denying layer sits outside that virtual host, the administrator
must apply the policy at that layer instead and verify it there.

### Local verification

```sh
python3.12 -B Server/tests/apache_headers_test.py
```

All **five tests passed** at 05:20 UTC using actual macOS Apache on loopback.
They compare the include with the site policy, demonstrate an early
`mod_alias` 403 that bypasses `.htaccess`, and verify the include covers that
denial plus ordinary 200/403/404 responses. GET/HEAD checks require exactly
one value per header and never serve the synthetic private-file markers.
The fixture models the boundary, not the identity of the production blocker.
Missing local Apache/modules produce an explicit skip, not validation.

### Historical proposed-include acceptance, not performed

After authorized administrator application, rerun the existing strict audit
and browser acceptance. Do not weaken the audit to label the include accepted:

```sh
cd website
node Tools/public-parity-assets.mjs
node Tools/run-native-parity.mjs https://hashfleet.app
```

The proposed include changes headers only. The strict audit's separate
expectation of 404 for `/.git/config` will still fail if the host retains 403.
Both are denials, but this proposed patch does not claim to alter that status
or make the entire audit green. Preserve all denials and record the actual
post-application response. No React, website build, production `.htaccess`,
backend or private-state change is retained from this investigation.

Final post-edit receipts at 05:22 UTC:

- `final-local-regressions.log`: all five Apache tests, ten installer tests,
  nine retired-endpoint guards, TypeScript and 112 frontend tests passed.
- `final-public-audit.json`: the unchanged strict collector **still exits 1**.
  All 31 build responses match bytes and policy, all nine protected/missing
  routes remain denied, and the same nine mismatches remain on the two paths.
- `final-public-browser.log` and
  `website/output/playwright/native-parity-20261025T052210426Z-native-parity-public/result.json`:
  all 187 public Chromium checks passed, including 18 native captures and the
  real CSP, with no browser errors or unexpected failed requests.

These regressions verify the restored website and the local handoff. They do
not prove the proposed host include fixes production before it is applied.

## Primary references

Checked October 25, 2026:

- Apache `mod_headers`: https://httpd.apache.org/docs/2.4/mod/mod_headers.html
- Apache `ErrorDocument`: https://httpd.apache.org/docs/2.4/mod/core.html#errordocument
- Apache request phases: https://httpd.apache.org/docs/2.4/rewrite/tech.html
- cPanel domain-specific includes: https://docs.cpanel.net/ea4/apache/modify-apache-virtual-hosts-with-include-files/
