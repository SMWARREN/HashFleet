# Virtual miner network isolation

**Evidence checked:** November 21, 2026, Apple Silicon macOS. Each native `esp-emu` guest has a separate private flash, virtual Wi-Fi/NAT process and TCP listeners. The gateway is a host-side guard, not an implementation of the firmware API. The API-only fixture does not launch a guest.

## Native `esp-emu` isolation

- Use only `user,restrict=yes,dns=127.0.0.1,net=10.0.2.0/24,hostfwd=tcp:127.0.0.1:<private-port>-:80`. The `10.0.2.0/24` virtual STA network does not overlap the firmware's `192.168.4.0/24` setup AP. Each emulator supplies its own isolated link. Guest MAC/IP values can repeat across these links and are not host identifiers; use each instance's distinct localhost port and configured firmware hostname.
- `restrict=yes` is not the only control. Espressif documents explicit DNS forwarding, so the runner also disables emulator updates, sets DNS to `127.0.0.1` inside the backend configuration, and applies an OS boundary. The lab NVS overlay replaces both pool hostnames with `.invalid` and replaces all pool credentials with dummy data.
- On macOS, `sandbox-exec` denies all `network*` operations except bind/inbound for the assigned TCP ports. No UDP binds, outgoing TCP, DNS forwarding, or new sockets connecting out are allowed. Offline tests explicitly attempt outbound TCP and UDP against local sockets and attempt an unassigned listener. The SBPL `localhost` predicate does not independently guarantee the bound address. The pinned emulator is given literal `127.0.0.1` for its HTTP forward, co-sim and UART1 listeners, and the supervisor checks the live process's exact numeric listener addresses with `lsof` before exposing the gateway.
- On Linux, the runner refuses real firmware unless `/sys/class/net` contains only `lo`. A container started with `--network none`, without the Docker socket, host namespaces, extra capabilities, or other host interfaces, is the intended option. Run the client inside the same container. The Linux binary is pinned but the Docker path was not exercised here. Do not publish Docker ports or use host networking.
- This is a developer environment for independently verified input artifacts and trusted host users. Local processes can contact a private guest TCP forward if they intentionally obtain its port and bypass the public gateway. The macOS process profile is network confinement, not a sandbox for arbitrary untrusted host binaries or a defense against other local users. Never target the private forward with controls. Do not expose any lab socket to another machine.

## API boundary

The gateway `make_gateway(port, guest_port)` binds only `127.0.0.1` and always targets its fixed local guest forward. It permits only exact `GET /api/system/info` and `GET /api/system/statistics` with no query. It strips request headers, rejects bodies, never follows redirects, applies timeouts and a 1 MiB response cap, and does not log payloads. Info can contain pool and Wi-Fi fields: do not store raw captures. Statistics excludes configuration and logs, but can include historical telemetry such as RSSI. Mutations, WebSocket routes, scans and log routes are not exposed. Use `stop` then `start` for a virtual power cycle, not the firmware's restart endpoint.

`make_fixture(config)` is a distinct synthetic mode: `X-Virtual-Miner-Fixture: api-only` and `GET /healthz` identify that there is no firmware execution. It has no external traffic or controls. Failure to boot a real guest never starts a fixture.

## QEMU alternative (not a runner backend)

Use QEMU user-mode networking with `restrict=on` and no NIC/backend except the explicitly intended user-mode backend. For the optional HTTP bridge, create one explicit host-forward bound to IPv4 loopback, for example:

```text
-netdev user,id=miner-net,restrict=on,hostfwd=tcp:127.0.0.1:18080-:80
-device <guest-nic>,netdev=miner-net
```

Replace `<guest-nic>` with the NIC model supported by the selected machine. `restrict=on` is documented to prevent the guest from contacting the host and prevent guest IP packets being routed out through the host. QEMU explicitly documents that `restrict` does **not** affect explicitly configured forwarding rules. Binding the host-forward listener to `127.0.0.1` keeps that exception off LAN interfaces. This is a narrow host-to-guest HTTP path, not guest access to the host or Internet. Do not add other `hostfwd` rules unless independently needed and reviewed.

The pinned Espressif QEMU macOS v9.2.2 binary could not run even `--version` on the test host: `dyld` reported missing `libgcrypt.20.dylib`. No host packages were installed. Its OpenETH example targets firmware built for that NIC, not this original Wi-Fi image. Apple App Sandbox client/server entitlements are not per-destination controls or substitutes for an OS egress test.

## mDNS and discovery limits

mDNS is link-local per RFC 6762; a host-only TCP listener does not put firmware and HashFleet on the same multicast link. AxeOS advertises mDNS in the guest, but no mDNS or discovery advertisement reaches the host or LAN in this lab. Use explicit loopback targets. To test discovery itself later, use a dedicated isolated L2 link or a narrow test-only reflector with collision handling. Do not bridge the lab onto a production LAN.

## Source evidence

- Espressif `esp-emulator` **v1.2.0** [`Networking`](https://github.com/espressif/esp-emulator/blob/v1.2.0/docs/guides/NETWORKING.md) and [`Host interfaces`](https://github.com/espressif/esp-emulator/blob/v1.2.0/docs/guides/HOST-INTERFACES.md). `restrict=yes` does not imply that configured DNS forwarding is disabled.
- ESP-Miner AxeOS API, pinned **v2.15.4**, commit `d212a0f948cb3ffd90c7ca9572e9b2cf2d865d80`: [`main/http_server/openapi.yaml`](https://github.com/bitaxeorg/ESP-Miner/blob/d212a0f948cb3ffd90c7ca9572e9b2cf2d865d80/main/http_server/openapi.yaml) and [`http_server.c`](https://github.com/bitaxeorg/ESP-Miner/blob/d212a0f948cb3ffd90c7ca9572e9b2cf2d865d80/main/http_server/http_server.c). The fixture serves only a typed subset of info, with synthetic values.
- QEMU **11.1.3** stable documentation, user-mode networking options: [`Invocation`](https://qemu.readthedocs.io/en/stable-11.1/system/invocation.html). It describes `restrict=on` as isolating the guest from the host and preventing guest packets from being routed outside, and says explicit forwarding rules are unaffected. The user-mode networking overview is [`Network emulation`](https://qemu.readthedocs.io/en/stable-11.1/system/devices/net.html).
- IETF **RFC 6762**, February 2013, especially sections 3 and 14: [Multicast DNS](https://www.rfc-editor.org/rfc/rfc6762). `.local.` names and mDNS multicast have local-link scope.
- Apple Developer Documentation, [App Sandbox network client entitlement](https://developer.apple.com/documentation/BundleResources/Entitlements/com.apple.security.network.client) and [Configuring the macOS App Sandbox](https://developer.apple.com/documentation/xcode/configuring-the-macos-app-sandbox): client/server entitlements control outgoing/incoming connection capability, not per-destination policy.

The real guest path and fixture path are tested separately. No physical miner, LAN scan, outbound multicast, or production pool connection is needed or allowed in either path.
