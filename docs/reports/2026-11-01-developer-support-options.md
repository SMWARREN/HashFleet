# Optional developer support: donation-style shortlist

Checked: 2026-11-01. Research only. No accounts, payments, deployment or app changes.

## Research integrity

Five workers were launched. Three failed before researching with Antigravity HTTP 400 schema errors, and their same-route retries failed. Three replacements were launched, two of which failed the same way. The remaining three workers returned no reports before two wait deadlines and were stopped. This document is the coordinator's independently checked primary-source research, NOT five completed independent reviews. No model pools or accounts were changed.

## Recommendation

Use one simple **Support Hash Fleet** page with separate choices for conventional tips and direct crypto support. Do not create a storefront, sell access, or advertise charitable tax deductibility. Either host this small page ourselves or evaluate a donation-link aggregator. This is a proposed design, not an implemented payment service.

For the conventional tip option, Ko-fi is a strong fit. Direct crypto addresses can sit alongside it on the shared support page. A visitor chooses a method, rather than being forced to buy crypto with a card first. Wallet/payment destinations must be explicitly supplied and verified by the owner. Never derive them from miner pool settings.

## Shortlist

| Option | Verified fit | Limitations and costs |
| --- | --- | --- |
| donatr.ee | Donation-specific link aggregator. Its FAQ lists BTC, ETH, SOL, LTC, DOGE, XMR, TON, TRX, and USDT on ERC-20/TRC-20/BEP-20, alongside PayPal, Ko-fi and other payment links. | Not an all-in-one processor: crypto addresses are copied and external payment services handle their own checkout. The provider claims no platform fee, but payment-service/network costs remain. Its security, uptime, ownership verification and real checkout have NOT been independently audited. Do not connect a wallet or sign transactions just to evaluate it. |
| Ko-fi | Genuine one-time tip page, with PayPal and Stripe connections. Stripe enables eligible Apple Pay/Google Pay checkout; PayPal may expose Venmo for eligible US one-time USD support. Payments go to the connected account. | No crypto payment roadmap. Free mode charges 0% platform fee on one-time tips, versus 5% in Standard mode; processing fees remain. New creators start with expanded features enabled, so inspect settings rather than assume zero platform fees. |
| GitHub Sponsors | One-time or monthly open-source sponsorships, appropriate for a developer supporting multiple repositories. | Not a crypto tip jar. Published billing options include cards and Patreon, not PayPal. Personal-account sponsorships have no GitHub fee; organization sponsorships have fees up to 6%. Requires recipient onboarding, financial/tax details and acceptance. |
| BTCPay Server | Self-hostable crypto donations and payment buttons, including invoice checkout and crowdfunding. | More operational work than a hosted tip jar. Do not assume every coin is available in a default install. Official altcoin FAQ and deployment docs differ on which chains the core project maintains, so validate the chosen deployment/version and plugins before promising particular assets. Hosting, network and optional third-party services may cost money. |
| Our own support page | Design proposal: a static page with verified Ko-fi or GitHub Sponsors links and explicitly labeled crypto addresses/networks. | Requires hosting, maintenance, QR/address tests and owner confirmation. Does not itself process card payments, detect transfers or generate receipts. Avoid third-party scripts and wallet-connection prompts for the initial release. |

## Exclusions and unresolved candidates

- NOWPayments marketing is not enough to establish eligibility. An official general user agreement explicitly excludes people located in or citizens/residents of the United States. Its separate funds-deposit terms also have restrictions. Do not onboard the assumed US-based owner without resolving the applicable current agreement and eligibility. No attempt to evade geographic restrictions is authorized.
- Whop was not selected. Pure optional developer tips without a product have not been sufficiently verified against its terms.
- CoinGate, Geyser, Tallycoin, Open Collective and Liberapay did not receive completed worker reports. They are not represented as reviewed or rejected here.
- A service advertising card-funded crypto purchases is not necessarily conventional card donation processing. These experiences must be distinguished.

## Platform boundaries

Apple's October 16, 2026 guidelines expressly allow developer tips through in-app purchase. External purchase linking has a US-storefront exception and region-specific arrangements elsewhere. A single donation URL is therefore not automatic worldwide App Store permission. Use a consistent Support entry point, but validate the actual payment presentation by storefront and distribution channel. Direct Mac/CLI support links do not establish App Store eligibility.

No purchases unlock features. No changes to pools, mining settings or hash allocation. No charitable status or deductible-donation claims. No seed phrases, private keys or payment credentials in the app or repository. No release placeholders or unverified addresses.

## Before implementation

1. Owner chooses an aggregator versus our own page and supplies public receiving addresses with exact networks plus the ordinary-payment link.
2. Verify provider eligibility, account ownership, relevant fees and any identity/banking requirements in the actual signup flow. The owner handles sensitive information and acceptance of legal agreements.
3. Confirm the App Store tip tiers and regional presentation separately, without treating a web link as a universal bypass.
4. Test link destinations, exact address copy, QR payload, network/memo labels, accessibility, cancellation, and absence of miner writes. No real donation is required without separate authorization.

## Primary sources

- https://donatr.ee/faq/
- https://www.donatr.ee/terms/ (last updated July 2026)
- https://help.ko-fi.com/hc/en-us/articles/115003980093-How-do-I-get-paid
- https://help.ko-fi.com/hc/en-us/articles/360002506494-Does-Ko-fi-take-a-fee
- https://docs.github.com/en/sponsors/sponsoring-open-source-contributors/about-sponsorships-fees-and-taxes
- https://docs.github.com/en/site-policy/github-terms/github-sponsors-additional-terms
- https://docs.btcpayserver.org/Apps/
- https://docs.btcpayserver.org/FAQ/Altcoin/
- https://docs.btcpayserver.org/Docker/cryptocurrencies/
- https://nowpayments.io/doc/user_agreement-v1_2_3.pdf
- https://nowpayments.io/doc/fd-tos.pdf?v=1.3
- https://developer.apple.com/app-store/review/guidelines/ (last updated October 16, 2026)
