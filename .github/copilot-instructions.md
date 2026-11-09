# HashFleet contribution instructions

- Work on a focused branch and propose changes through a pull request. Never merge,
  approve your own PR, disable checks, or change repository protection settings.
- Read CONTRIBUTING.md and the relevant contracts in docs/ before changing behavior.
- Preserve unknown firmware fields, explicit device-change confirmations, demo-mode
  network isolation, and fail-closed safety checks. Never contact physical miners.
- Use mocks or loopback fixtures. Run targeted checks and report their actual results.
  Do not label an unexecuted check as passed or weaken tests to get a green build.
- Never access or export signing keys, account credentials, or private telemetry.
- Keep app and CLI release artifacts separate. Release signing credentials belong
  only to the protected release environment, never PR jobs.
- Preserve existing release tags and assets. New releases require a reviewed version
  change and the signed release workflow. Do not publish ad-hoc or unsigned binaries.
- Keep internal investigation logs, screenshots containing private data, and generated
  artifacts out of tracked source. Keep user-facing documentation concise.

These instructions guide an agent that a maintainer has explicitly enabled and
assigned. They do not themselves provision an agent, subscription, or API access.
