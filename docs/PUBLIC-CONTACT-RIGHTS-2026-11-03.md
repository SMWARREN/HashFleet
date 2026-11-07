# Public contact update and content rights, November 3, 2026

## Requested changes

The owner confirmed content ownership/permission at 08:25:31 UTC, requested one phone test notification and native demo videos, then requested removal of the public support phone number and use of `support@hashfleet.app`. These requests do not authorize a review submission, recurring notification schedules, miner changes, or changes to private Apple review contacts.

## Verified delivered scope

- The existing shared Apple app resource `6812623943` now has `contentRightsDeclaration=USES_THIRD_PARTY_CONTENT`. Hash Fleet reads third-party chain/pool data and incorporates open-source components, so the declaration does not incorrectly assert that no third-party content is accessed. The declaration was saved through Blitz MCP and independently read from both the app resource and content-rights endpoint. The cached Blitz app-information getter still showed an empty value and was not treated as authoritative evidence of the app-level attribute.
- The public support page has no phone row, phone number or telephone link. Its only contact fields are Name and Email. Both support and privacy pages display `support@hashfleet.app` with the matching `mailto:` target.
- Publication at 08:38:45 UTC wrote only the homepage, support page and two new hashed frontend JavaScript assets. The unchanged CSS was verified, not rewritten. Prior public files were privately backed up. The allowlisted five frontend hashes and unrelated protected files were checked by the publisher. No backend configuration, scheduling, private key or other website was changed.
- Independent Apple review-detail reads at 08:43:58 UTC confirmed that the original private contact fields remain unchanged on both existing iOS and macOS drafts. Neither draft was submitted.
- The hosting account contains an exact `support` account entry and its existing `mail/hashfleet.app/support` storage directory. DNS points mail to `mail.hashfleet.app`. This is account/routing configuration evidence, not an end-to-end email delivery test. No verification email was sent and no mail account was created or modified.

## Requirement-to-check evidence

| Requirement | Observed check |
| --- | --- |
| Public phone removal | Full HTML contains no original phone digits and no `tel:` anchors. All responsive contact assertions passed. |
| Correct public email | Exact text and `mailto:` targets tested on actual public support and privacy pages. |
| Responsive contact layout and keyboard navigation | Existing contact acceptance retains the viewport/theme, contrast, focus and request-isolation checks. The former phone-presence check was correctly changed to phone absence and Name/Email-only checks, not removed to hide a failure. |
| No regression in the frontend build | `npm run build` succeeded and all 163 unit tests in six files passed. |
| Actual public behavior | 85 contact assertions and 49 privacy-permalink assertions passed against real HTTPS without response interception. No external/service requests, page errors or failed requests were observed by those suites. |
| Shared content rights saved | Independent Apple reads, rather than the stale local MCP getter. |
| Private review contacts preserved | Exact original values asserted separately for both review-detail IDs, without publishing them in this document. |

Evidence is retained privately under `/Users/USER/.jcode/scratch/hashfleet-rights-push-demos-20261103T0825.noindex`. Public browser artifacts are in `website/output/playwright/20261103T083935175Z-contact-public` and `website/output/playwright/20261103T083946844Z-privacy-public`.

## Remaining work and diagnostic boundaries

At the 08:49:33 UTC read-only physical-phone preference copy, remote summaries were disabled and registration was not confirmed. No push has been sent by this work. Provider health alone is not proof of APNs acceptance or phone presentation, and recurring alerts must not be enabled solely to manufacture a successful test.

Native demo recordings are not yet claimed complete. The original shipped demo snapshot metrics are static. A truthful recording must demonstrate the real native app with explicitly identified simulated input, or a genuinely accepted native change, rather than fabricated live telemetry or a browser UI presented as the app.

The first cPanel UAPI read failed because its required host executable was unavailable. A separate Maildir-layout assumption also failed because this host uses `mailboxes`/`storage` directories. Neither failure proves that the support account is absent. The exact account-name check subsequently succeeded without exposing password fields or messages. Both diagnostic boundaries are retained.

This change owns only four website source/acceptance files and this document. Concurrent watchOS work, Blitz project changes and other documentation are not included or accepted by this contact update. Original uploaded iOS build 18 and macOS build 19 remain bound to accepted code revision `320510d645a7e5849d13deff73d312b25ef42781`.
