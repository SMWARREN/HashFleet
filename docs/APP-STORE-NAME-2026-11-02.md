# Verified App Store draft name: November 2, 2026

The owner requested the exact public name **Hash Fleet**, including its space and capitalization, at 09:57:41 UTC. The lowercase `hashfleet` label seen in Blitz was the local project name, not a verified App Store listing name. The installed native iPhone app already displayed `Hash Fleet`.

## Verified existing store record

Read-only lookup through Blitz's bundled `asc` CLI identified the existing Fleet record:

- App ID: `6812623943`.
- Historical bundle ID: `org.axefleet.app`.
- SKU: `axefleet-app`.
- Primary locale: `en-US`.
- App-information ID: `853521f1-b25d-4208-a472-6ff7b83ac288`.
- Localization ID: `70e349ed-1f7a-4bea-8a3a-b63938147985`.
- Initial localized name: `Axe Fleet`.
- App-information state: `PREPARE_FOR_SUBMISSION`.

Blitz MCP's current local project was not connected to this store record, so its empty form was not treated as evidence of a saved name. The documented fallback was Blitz's bundled CLI, not a direct credential-bearing API script.

## Authorized change and independent reread

At 10:11:35 UTC the existing en-US app-information localization was updated with **only** `--name "Hash Fleet"`. The explicit existing app-information ID was selected. At 10:12:50 UTC independent localization, app-list and app-information reads confirmed:

- Localized name and app record name: `Hash Fleet`.
- Same app ID, historical bundle ID, SKU and localization ID.
- State still `PREPARE_FOR_SUBMISSION`.

No duplicate app was created. No bundle identifier, pricing, other metadata, build assignment, submission, review or release state was changed. No binary was uploaded. This verifies the App Store Connect draft name, not a newly published public listing.

## Separate identity boundary

The current physical development install uses `app.hashfleet`, version 0.1.0 build 16. No store record for that bundle ID was found in the same authenticated lookup. This name-only operation did not change the local project bundle ID or silently associate an incompatible binary with the historical store record. A future App Store submission must separately resolve that identity boundary before any upload or submission.

The existing canonical Mac installation, saved inventories/history, physical phone app data, mining hardware and original owner-modified information-page document were not changed by the store-name correction.
