# HashFleet Virtual Miner Lab

Run original ESP32-S3 miner firmware in a headless, loopback-only developer lab. The first supported profile is **Bitaxe Gamma 601**: the official AxeOS **v2.15.4** application executes under Espressif **esp-emu v1.2.0**. HashFleet talks to the original HTTP server, not a model of the server. The virtual hardware sidecars answer original firmware I2C and UART1 traffic. See [compatibility](COMPATIBILITY.md), [network isolation](NETWORK.md), and [execution evidence](evidence/axeos-gamma601.md).

## Start a real firmware instance on Apple Silicon

Requires macOS on Apple Silicon, Python 3.11+, `/usr/bin/sandbox-exec` and `/usr/sbin/lsof`. No third-party Python dependencies, GUI, simulator boot, USB or physical miner are required.

```sh
cd Tools/virtual-miners
python3 -B -m virtual_miners setup       # fetch and SHA-256 verify the pinned publisher assets
python3 -B -m virtual_miners start gamma
python3 -B -m virtual_miners check gamma # wait for the actual guest API and matching identity
python3 -B -m virtual_miners list
hashfleet status 127.0.0.1:18081         # explicit local target, not LAN discovery
python3 -B -m virtual_miners stop gamma
```

If the CLI is not installed, from the repository root `swift build --product hashfleet` builds it and `.build/debug/hashfleet` is the executable. Use a separate terminal only if needed, or `python3 -B -m virtual_miners run gamma` for a foreground instance. `list` reports process state, not HTTP readiness. `check` prints only a few identity fields rather than the raw response. `stop` followed by `start` simulates a power cycle with a fresh flash copy; it never sends a restart request to a miner. `list` prints the private run directory for debugging (`serial.log`).

`setup` is the only download command. The default state and cache are `~/.cache/hashfleet-vm` and its `assets` subdirectory. To override them, pass `--state-dir PATH` and/or `--assets-dir PATH` **before** the command. Use a short path for the Unix control socket. No installer, login, emulated flash or firmware binary is committed. Cached images are digest-checked again before launching. Only the **first NVS page of a disposable copy** is provisioned: clear the factory self-test flag, set the lab hostname/Wi-Fi, and substitute `.invalid` pool addresses plus dummy credentials. The factory artifact, executable, partition table and bootloader are unchanged. The unprovisioned factory self-test is a [separate experiment](evidence/esp-emulator-gamma601-factory-serial.md).

## Run multiple miners and inject faults

Copy `lab.toml`, add one `[[miner]]` block per instance, and give each a unique `name` and `http_port`. The board profile fixes the known firmware build, ASIC family and ASIC count (Gamma 601, one BM1370). The only configurable public network value is the local TCP port; interface and upstream destinations are not configurable. Set `temperature_c` and `power_w` to drive the board model, not the HTTP response.

```toml
[[miner]]
name = "gamma-with-fault"
board = "gamma-601"
backend = "esp-emu"
http_port = 18082
hardware = "board"
scenario = "asic-missing"
temperature_c = 48
power_w = 14
```

`python3 -B -m virtual_miners --config ./my-lab.toml start` starts all entries. `start`, `list`, and `stop` also accept one or more names. Read both instances with `hashfleet status 127.0.0.1:18081 127.0.0.1:18082`. Each instance has its own storage, emulated network and loopback ports. Leave room on disk for the logs and per-run images; `stop` does not delete receipts.

| Scenario | Injected condition |
|---|---|
| `normal` | Regulator, temperature, fan, OLED I2C acknowledgments, and BM1370 discovery are modeled. |
| `asic-missing` | The UART sidecar does not return a chip identity. The board and HTTP path remain available. |
| `no-power` | The TPS546 stops acknowledging; other I2C devices remain. The original firmware reports its regulator initialization failure. |
| `overheat` | The EMC2101 virtual ASIC temperature is at least 95 °C. Output depends on the unmodified guest's initialization and policy. |
| `offline` | The guest cannot associate to its virtual upstream Wi-Fi. Its setup AP can still answer the local HTTP forward. To test an unreachable HTTP endpoint, `stop` that instance. |

`hardware = "bare"` is a normal-mode comparison without the sidecars. It is not a working ASIC. The model does not perform hash work, return fake shares, accurately simulate voltage transients or clock timing, or render an OLED. The raw UART bridge sees register commands, not physical baud timing. The only public real-guest routes are exact GETs for system info and statistics. No writes, scans, firmware OTA, WebSockets or LAN mDNS are exposed. Prefer separate isolated transport work if those become test requirements.

## API-only fallback (explicit, not a firmware test)

```sh
python3 -B -m virtual_miners --config fixture.toml start
python3 -B -m virtual_miners --config fixture.toml list
python3 -B -m virtual_miners --config fixture.toml stop
```

This mode requires no assets. Responses are synthetic and marked `X-Virtual-Miner-Fixture: api-only`; `/healthz` declares `firmware_execution: false`. It supports `normal` and `degraded` fixtures. It is never started automatically if firmware cannot boot.

## Verify changes

```sh
# From Tools/virtual-miners: offline tests, also wired into repository CI
python3 -B -m unittest discover -s tests -v

# Opt-in native acceptance, after setup and building the HashFleet CLI
python3 -B verify_native.py
```

Native acceptance does not download assets. `--assets-dir` and `--hashfleet` override defaults. It retains private evidence and stops its own instances on completion. Linux is only intended inside a dedicated `--network none` container with offline assets copied in before launch. Run clients inside that same namespace. macOS is the tested platform; QEMU and Docker limits are in [NETWORK.md](NETWORK.md).

## Hammer ThorOS (original firmware and API fixture)

**Original firmware.** `thoros-native.toml` boots Hammer's **unmodified** `thorx1-1.0.6-20260916` and `thorp2-1.1.0-20261113` OTA app images (downloaded from `HammerMiner/X1` and `HammerMiner/P2` releases, SHA-256 pinned in `config.py`) under esp-emu with `hardware = "bare"`. Hammer publishes only app images, so `virtual_miners/thoros_flash.py` composes a private flash around the vendor bytes, which are copied unchanged into `factory`:

- the ESP-IDF v5.5.3 second-stage bootloader from the pinned public Bitfortun `BS-1-rev1.3.bin` (v1.0.36), with only its partition-table offset changed from `0x8000` to `0xD000` (ThorOS maps its table at `0xD000`) and its checksum and SHA-256 recomputed;
- a partition table with the labels the app opens (`nvs`, `otadata`, `factory_info`, `logs`, `storage`, `coredump`);
- one NVS page with `thor_cfg/selftest_done = 1`, which skips the factory hardware self-test (as the Bitaxe profile clears its self-test flag). Without it the app waits forever for real I2C/fan/ASIC parts.

```bash
python3 -B -m virtual_miners --config thoros-native.toml setup
python3 -B -m virtual_miners --config thoros-native.toml start
python3 -B -m virtual_miners --config thoros-native.toml check thor-x1 --wait 120
hashfleet status 127.0.0.1:18293 127.0.0.1:18294
```

Verified 2026-11-26 on Apple Silicon: both originals served `GET /v2/device/info`, `/v2/device/status`, `/v2/miner/status` and `/v2/miner/config` from the firmware's own HTTP server (THOR X1 `1.0.6 20260916`, THOR P2 `1.1.0 20261113`, `BM1373`), and HashFleet reported both online. The firmware's default config names real public pools, but the emulator runs with `restrict=yes`, no Wi-Fi credentials and a deny-network sandbox, so no outbound connection is possible. The gateway forwards only those four GET routes. Reboot, logs, Wi-Fi scan and every write return 404/405. There is no Thor board sidecar yet: no regulator, fan, temperature sensor or ASIC chain is modelled, so hashrate, power and temperature read 0 and `detected_chips_count` is 0. This proves identity, API shape and HashFleet integration, not mining.

**API fixture.** The `thor-x1` and `thor-p2` entries in `fixture.toml` (`backend = "api-fixture"`) serve synthetic ThorOS `GET /v2/device/info`, `/v2/device/status` and `/v2/miner/status` (wrapped `{"ok":true,"data":{...}}`) with nonzero telemetry, plus the vendor's HTML console for any other path including `/api/system/info`. Field names follow the official THOR API Reference V1.0.0.

## Harlo OS

The original Harlo OS **0.2.101** Gamma 601 factory image booted on this native emulator and served all six investigated GET routes from its setup AP with ASIC rails off. See the [redacted capture and isolation procedure](evidence/harlo-gamma601.md). This is research evidence, not a second selectable miner backend or a full Harlo mining simulation. The opt-in Swift `HarloReadClient` does not change existing discovery or polling. Its `HarloInfoProfile.gamma601V02101` profile recognizes that exact build and enables only the explicitly advertised fleet GET. No child hosts are contacted and no log or credential values are surfaced. BS-1, NerdOS, AxeForge, Gamma 602 and other profiles are source-researched, not runnable here.
