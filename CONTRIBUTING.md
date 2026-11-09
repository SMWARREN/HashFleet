# Contributing

Contributions are welcome under GPL-3.0. Please keep the app local-first and dependency-light.

## Propose a change

Fork this repository, create a focused branch, and open a pull request against `main`.
Describe the problem, the change, and how you checked it. Include screenshots for UI
changes, using demo data only. Bug reports should include the app version and platform,
but never private telemetry or credentials.

Pull requests run read-only CI checks. A first-time contributor may need a maintainer
to approve the workflow run. PR jobs do not receive release signing credentials.
Passing checks do not merge a change: a maintainer reviews and merges it. Merged
changes are checked again, and versioned releases use the separate signed release
workflow. See [automation and release setup](docs/AUTOMATION.md).

AI-assisted contributions follow the same PR process. Disclose substantial generated
changes, inspect the diff, and provide test evidence. An agent must not approve or
merge its own work. Repository instructions do not activate a paid coding agent or
grant it credentials.

## Development checks

1. Read `docs/CORE-CONTRACT.md` and `docs/API-COVERAGE.md` before changing networking.
2. Add tests for new endpoint paths, methods, payloads, errors, and decoding variations. Audit both the upstream schema and actual HTTP handler registrations.
3. Run `swift test`, regenerate the Xcode project with `xcodegen generate`, and build the simulator app.
4. Check onboarding, explicit demo mode, offline errors, large text, VoiceOver labels, iPhone/iPad layout, and cancellation when leaving screens.
5. Never run mutation tests against physical miners without the owner's explicit approval. Use URLProtocol mocks or a loopback fixture server.
6. Avoid committing private IP inventories, logs, wallet addresses, Wi-Fi secrets, signing credentials, or generated build artifacts.

Keep HTTP/WS behavior centralized in HashFleetCore. Every UI mutation needs an explicit confirmation naming its target, and demo flows must not contact a device. Do not persist secrets from settings editors. Preserve unknown JSON fields when reading firmware responses.

For a public release, choose a unique bundle ID, configure signing, run physical-device compatibility tests, review Apple's distribution rules for the GPL license, provide required store metadata, and publish a privacy-policy URL. The included privacy manifest is not a substitute for that release review.
