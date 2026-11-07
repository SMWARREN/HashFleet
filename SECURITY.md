# Security

- Treat miners as trusted-LAN appliances. Their APIs can change hardware settings without authentication.
- Never expose ESP-Miner ports to the public internet. Use a trusted VPN instead.
- Only import binaries from a source you trust, matched to your hardware. HashFleet does not perform firmware-signature or board-compatibility verification.
- Do not include raw logs or configuration secrets in public issues.
- If you discover a vulnerability, use the private security-reporting channel of the repository that distributed your copy. Until a public HashFleet repository exists, contact that distributor privately rather than posting sensitive details publicly.

The app validates entered device addresses and uses a fixed endpoint catalog. This reduces accidental malformed requests but is not a sandbox against a malicious server. HTTPS certificate errors are not bypassed. User-entered HTTP destinations and plaintext responses remain a local-network trust decision.
