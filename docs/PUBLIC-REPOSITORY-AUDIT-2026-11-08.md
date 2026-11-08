# Public repository audit, November 8, 2026

## Scope and current status

The operator requested source that other people can build without access to personal credentials or fleet configuration. The existing public workspace is separate from the active repair repository and has no configured remote. Publication is not authorized by this audit.

The dedicated scan below covers repair revision `02097e52ccd29be5ca8e3608f154bf2ce2ab239c`, not every future edit. Subsequent documentation sanitization and a clean candidate must be checked separately. No credential was tested against a live service.

## Dedicated secret scan

At 19:57 UTC, a scratch-only Gitleaks 8.30.1 binary scanned:

- An exact committed source archive: raw exit 0, zero findings, approximately 21.31 MB reported scanned.
- All reachable Git history, including root: raw exit 0, zero findings, 103 commits and approximately 11.30 MB reported scanned.

The scanner used its default rules, recursive decoding depth 5 and archive depth 2. Repository ignore files and per-line suppression comments were bypassed. Default rule allowlists remained in effect. Output redaction was set to 100 percent, and reports were retained outside source control. A separate generated, nonfunctional GitHub-token-shaped canary was detected with the expected raw exit 1; its value was absent from the redacted report and logs.

The downloaded official release archive matched SHA-256 `b40ab0ae55c505963e365f271a8d3846efbc170aa17f2607f13df610a9aeb6a5`. Its extracted executable matched `ba52fb1bfabbcde42f032afad3d6e0b19dff8ed105229a16e7caa338bbc0e84f`. The scanned source archive matched `5a6a3f27a89a59e840b83db3559d6f72cac66ccef2744ea759572416d47fb28a`. Independent read-only review rechecked these bindings, the report/log hashes and the recorded commit count.

Zero findings means no matches under those scanner rules, not proof that all possible secrets, personal information, binary-embedded content or operational details are absent. The Git scan covers reachable commits, not abandoned objects, reflogs, stashes or private files outside the committed export.

## Configuration and privacy checks

- `Signing.xcconfig` has no assigned development team. Its local override is ignored.
- Private environment files, APNs/signing keys and profiles, production server configuration and personal agent state are ignored. Ignore rules do not remove previously tracked material.
- The checked server and website examples contain placeholders, null credentials or empty optional public links.
- Targeted private fleet-subnet checks found no matching tracked inventory. Generic documentation, test and loopback addresses remain.
- Three later diagnostic documents had four personal home-path references. Those references now use `/Users/USER/`. Private original evidence outside the repository was not changed.
- Public application/product identifiers and intentionally public support destinations are not authentication secrets. They were preserved rather than indiscriminately removed.

The prior heuristic review and the dedicated scanner are complementary. Neither replaces visual review of screenshots or a rights review of third-party assets.

## Usability and remaining gates

`PUBLIC-BUILD.md` explains unsigned Mac/simulator builds, explicit demo mode, private local signing configuration, embedded-target requirements and optional integrations. Its commands and descriptions received independent source review against the project manifests and CLI parser. A configured CI command is not evidence that CI has run successfully.

Before publication:

1. Validate the exact sanitized candidate from a clean source export without developer signing credentials.
2. Rescan the final candidate after all edits and verify its file manifest.
3. Review distributable screenshots, PDFs and other assets for personal information and rights/provenance.
4. Preserve the existing public workspace and its history. Do not import the development repository's personal commit metadata merely to copy source changes.
5. Obtain the operator's publication destination and approval before creating a remote or pushing.

No public push, credential rotation, history rewrite, physical-device installation or change to submitted build 23 was performed by this audit.
