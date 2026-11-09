# Privacy

HashFleet does not include analytics, advertising, crash-reporting SDKs, tracking, or a hosted backend. It does not require an account.

Miner display names and addresses are stored in local app preferences. iOS may include app data in a device backup according to the user's backup settings. Monitoring responses and recent chart observations are held in memory. Wi-Fi/pool settings are sent only to the miner selected by the user and are not intentionally persisted by the app.

Logs and raw API responses may contain network addresses, wallet/worker names, or other sensitive information. Sharing or exporting these values is an explicit user action and places the exported data under the receiving app's control. Review it before sharing.

The app connects directly to addresses the user adds. ESP-Miner HTTP traffic is ordinarily unencrypted on the LAN. A VPN is recommended for remote access. The app requests local-network access for this purpose.

Demo mode generates sample data in memory and performs no miner requests. External documentation links open in the user's browser and follow that site's privacy policy.

## Optional developer support

Builds with a configured checkout may offer an optional developer tip in About.
Selecting it opens PayPal in the system browser. HashFleet does not embed a payment
SDK, collect payment credentials, send miner information to PayPal, or receive a
payment-completion callback. PayPal processes the transaction under its own privacy
policy and may collect contact, payment, device and fraud-prevention information.
The recipient may see the transaction details PayPal provides to merchants.
HashFleet does not promise anonymous payments or that verification is never required.
Payment does not unlock app features. The CLI only prints the public checkout link.
App Store builds use StoreKit's current storefront solely to decide whether the
external support option is available. This value is not saved or used for tracking.

## Widgets and Live Activities

Widget sharing is off until explicitly enabled in app Settings. When enabled, a local App Group stores only an aggregate snapshot: update time, online/total miner counts, hashrate, reported power and a demo flag. No miner addresses, names, identifiers, pool credentials or network names enter this shared payload. Turning sharing off clears the cache and requests a widget reload. iOS controls when already-rendered widgets disappear or refresh.

Live Activities start only on request and display the same aggregate fields on system surfaces. There is no push token registration or remote Activity server. Readings can be visible to someone viewing your Lock Screen. End the Activity in HashFleet or dismiss it through iOS. Both surfaces show stale readings after the freshness window rather than claiming continuous background monitoring.
