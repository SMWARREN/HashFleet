# Native parity references

Checked 2026-10-12 for the website/native comparison. These references are safe, deterministic native demo captures already committed under `docs/screenshots/`. They are not live-fleet telemetry and are not copied into the public website bundle.

| Reference | Source | Dimensions | SHA-256 | Safety boundary |
|---|---|---:|---|---|
| Native fleet overview demo | [`../docs/screenshots/fleet-demo.png`](../docs/screenshots/fleet-demo.png) | 1206 × 2622 | `a70291e189121e9e69bcdc004d369aa077fc92cae1f92b3de87806150dd4fd8d` | Native `--demo` fixture. Shows simulated readings and no hardware connection. |
| Native write-lock demo | [`../docs/screenshots/demo-write-lock.png`](../docs/screenshots/demo-write-lock.png) | 1206 × 2622 | `3c8ec240164e7e7b6484ebcf6c82438a1d9a287cd89d395cebda8ceb67b96d96` | Native demo confirmation page. Target is a reserved `.invalid` hostname and writes are explicitly locked. |

## How the references are used

- The screenshots are visual references for hierarchy, status labeling, spacing, settings safety, and native navigation. They are not embedded in the website or presented as browser output.
- Website fixtures remain fictional browser data in `website/src/lib/demo.ts`, with `.invalid` hostnames matching the native DemoFleet fixture, explicit sample labels, and no device requests.
- The website uses the same three fictional ASIC samples as the native `DemoFleet` fixture. The browser terminal and Mac/iPhone previews share those values so the screenshots, totals, and labels do not drift.
- No wallet addresses, credentials, private keys, pool passwords, or real fleet network addresses are used by the website changes.

Re-check the hashes with:

```sh
shasum -a 256 docs/screenshots/fleet-demo.png docs/screenshots/demo-write-lock.png
```
