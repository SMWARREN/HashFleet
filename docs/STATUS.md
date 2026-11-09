# Release status

## Version 0.1.0

Separate Mac app and CLI downloads are available for Apple Silicon on macOS 14 or later. Both are Developer ID signed and Apple-notarized. The Mac app has a stapled notarization ticket.

### Stability

**Fixed, not verified.** The owner reported roughly ten error-free hours on both devices on November 8, 2026. No further stability testing will be performed unless those issues are raised again.

Release builds, signing, notarization, package parsing, and download checks were completed. They do not establish that intermittent issues cannot recur. A full end-user Homebrew installation was not exercised during publication.

### Compatibility

Intel binaries are not included in this release. Firmware compatibility varies, and successful monitoring does not verify the safety of device-changing operations. See [model compatibility](MODEL-CAPABILITY-MATRIX.md) and [API coverage](API-COVERAGE.md).
