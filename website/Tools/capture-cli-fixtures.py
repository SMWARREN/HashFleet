#!/usr/bin/env python3
"""Capture sanitized hashfleet CLI examples against synthetic loopback HTTP fixtures only.

Usage: python3 website/Tools/capture-cli-fixtures.py [path/to/hashfleet]
The script never reads the configured fleet store, performs discovery, or contacts non-loopback hosts.
"""
from __future__ import annotations

import json
import fcntl
import hashlib
import os
import pty
import re
import select
import socket
import struct
import subprocess
import sys
import termios
import threading
import uuid
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
BINARY = Path(sys.argv[1]).resolve() if len(sys.argv) > 1 else ROOT / ".build/out/Products/Release/hashfleet"
OUT = ROOT / "website/src/lib/cli-captures.json"
ALIASES = ["gamma-demo.invalid", "office-demo.invalid", "supra-demo.invalid"]
NAMES = ["Workshop Gamma", "Office Gamma", "Little Supra"]
# Safe synthetic equivalents of App/Store/DemoFleet.swift. Pool users, wallet identities,
# credentials, local addresses and all unrelated secrets are intentionally omitted.
INFO = [
    {"hostname":"Workshop Gamma","hashRate":1218.0,"power":19.2,"temp":53.0,"vrTemp":61.0,"fanspeed":65,"fanrpm":4200,"voltage":5200,"frequency":575,"coreVoltage":1150,"sharesAccepted":12486,"sharesRejected":3,"uptimeSeconds":245820,"version":"Demo fixture","ASICModel":"BM1370","asicCount":2,"statsFrequency":30,"autofanspeed":1,"temptarget":55,"bestDiff":"18.4G","bestSessionDiff":"9.2M","stratumURL":"solo.ckpool.org","primaryPoolIndex":0,"secondaryPoolIndex":1,"isUsingFallbackStratum":0,"fallbackStratumURL":"bch.solofury.com","pools":[{"id":0,"stratumURL":"stratum.ckpool.org"},{"id":1,"stratumURL":"bch.solofury.com"}],"wifiRSSI":-48},
    {"hostname":"Office Gamma","hashRate":1164.0,"power":19.2,"temp":56.0,"vrTemp":62.0,"fanspeed":65,"fanrpm":4400,"voltage":5200,"frequency":575,"coreVoltage":1150,"sharesAccepted":13206,"sharesRejected":3,"uptimeSeconds":245820,"version":"Demo fixture","ASICModel":"BM1370","asicCount":2,"statsFrequency":30,"autofanspeed":1,"temptarget":55,"bestDiff":"18.4G","bestSessionDiff":"9.2M","stratumURL":"solo.ckpool.org","primaryPoolIndex":0,"secondaryPoolIndex":1,"isUsingFallbackStratum":0,"fallbackStratumURL":"bch.solofury.com","pools":[{"id":0,"stratumURL":"stratum.ckpool.org"},{"id":1,"stratumURL":"bch.solofury.com"}],"wifiRSSI":-48},
    {"hostname":"Little Supra","hashRate":638.0,"power":12.4,"temp":59.0,"vrTemp":63.0,"fanspeed":65,"fanrpm":4600,"voltage":5200,"frequency":525,"coreVoltage":1150,"sharesAccepted":13926,"sharesRejected":3,"uptimeSeconds":245820,"version":"Demo fixture","ASICModel":"BM1368","asicCount":2,"statsFrequency":30,"autofanspeed":1,"temptarget":55,"bestDiff":"18.4G","bestSessionDiff":"9.2M","stratumURL":"solo.ckpool.org","primaryPoolIndex":0,"secondaryPoolIndex":1,"isUsingFallbackStratum":0,"fallbackStratumURL":"bch.solofury.com","pools":[{"id":0,"stratumURL":"stratum.ckpool.org"},{"id":1,"stratumURL":"bch.solofury.com"}],"wifiRSSI":-48},
]
# Count is 12486 + 2 * 720, matching DemoFleet.sampleRawInfo.

class Handler(BaseHTTPRequestHandler):
    def do_GET(self):
        self.server.audit.append((self.command, self.path))
        if self.path != "/api/system/info":
            self.send_error(404)
            return
        payload = json.dumps(INFO[self.server.fixture_index], separators=(",", ":")).encode()
        self.send_response(200)
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(payload)))
        self.end_headers()
        self.wfile.write(payload)

    def log_message(self, *_args):
        pass

    def _reject(self):
        self.server.audit.append((self.command, self.path))
        self.send_error(405)

    def __getattr__(self, name):
        if name.startswith("do_"):
            return self._reject
        raise AttributeError(name)

    do_POST = _reject
    do_PUT = _reject
    do_PATCH = _reject
    do_DELETE = _reject
    do_OPTIONS = _reject


def server_for(index):
    server = ThreadingHTTPServer(("127.0.0.1", 0), Handler)
    server.fixture_index = index
    server.audit = []
    threading.Thread(target=server.serve_forever, daemon=True).start()
    return server


def capture_tty(args):
    master, slave = pty.openpty()
    fcntl.ioctl(slave, termios.TIOCSWINSZ, struct.pack('HHHH', 34, 125, 0, 0))
    env = {**os.environ, 'TERM': 'xterm-256color', 'COLORTERM': 'truecolor', 'LC_ALL': 'en_US.UTF-8'}
    env.pop('NO_COLOR', None)
    process = subprocess.Popen([str(BINARY), *args], cwd=ROOT, stdin=subprocess.DEVNULL,
                               stdout=slave, stderr=slave, env=env)
    output = b''
    try:
        while process.poll() is None or select.select([master], [], [], 0.1)[0]:
            if select.select([master], [], [], 0.1)[0]:
                output += os.read(master, 65536)
        if process.wait(timeout=3) != 0:
            raise RuntimeError('TTY capture failed')
        return output.decode().replace('\r', '').rstrip('\n')
    finally:
        if process.poll() is None:
            process.kill()
            process.wait()
        os.close(master)
        os.close(slave)


def normalize_tty(text, port_map):
    ansi = re.compile(r'\x1b\[[0-9;?]*[A-Za-z]')
    lines = text.splitlines()
    groups, header, current = {}, [], None
    for line in lines[:-1]:
        plain = ansi.sub('', line)
        authority = next((host for host in port_map if plain.startswith(f' {host:<23}') and 'ONLINE' in plain), None)
        if authority:
            current = port_map[authority]
            groups[current] = []
            line = line.replace(f'{authority:<23}', f'{NAMES[ALIASES.index(current)]:<23}')
        for host, alias in port_map.items():
            line = line.replace(host, alias)
        (header if current is None else groups[current]).append(line)
    if len(groups) != 3:
        raise RuntimeError('Expected three colored native miner rows')
    return {'header': '\n'.join(header), 'miners': {host: '\n'.join(rows).rstrip('\n') for host, rows in groups.items()}, 'footer': lines[-1]}


def main():
    if not BINARY.is_file():
        raise SystemExit(f"CLI binary not found: {BINARY}")
    servers = [server_for(i) for i in range(3)]
    try:
        authorities = [f"127.0.0.1:{server.server_address[1]}" for server in servers]
        # Assert resolution stays loopback before handing any host to the native CLI.
        for authority in authorities:
            host, _port = authority.rsplit(":", 1)
            if socket.gethostbyname(host) != "127.0.0.1":
                raise RuntimeError("fixture host did not resolve to loopback")
        addresses = authorities
        commands = {
            "help": ["--help"],
            "table": ["status", *addresses],
            "details": ["status", "--details", *addresses],
            "json": ["status", "--json", *addresses],
        }
        captures = {}
        for name, args in commands.items():
            result = subprocess.run([str(BINARY), *args], cwd=ROOT, text=True, capture_output=True, timeout=30)
            if result.returncode not in (0,):
                raise RuntimeError(f"{name} exited {result.returncode}: {result.stderr}")
            captures[name] = result.stdout.rstrip("\n")
        port_map = {authority: ALIASES[i] for i, authority in enumerate(authorities)}
        tty = {name: normalize_tty(capture_tty(commands[name]), port_map) for name in ('table', 'details')}
        logo = capture_tty(['logo'])
        for server in servers:
            if any(method != "GET" or path != "/api/system/info" for method, path in server.audit):
                raise RuntimeError(f"unsafe or unexpected fixture request(s): {server.audit!r}")
        observed = [item for server in servers for item in server.audit]
        if len(observed) != 15:
            raise RuntimeError(f"expected 15 GET info requests across five status runs, got {len(observed)}")
        # Deterministic fixture contract: all dynamic IDs, timestamps, and ephemeral loopback
        # authorities are normalized. Table rows are reformatted to the documented 20/28
        # character Swift String.padding(toLength:) columns after substituting fictional hosts.
        port_map = {authority: ALIASES[i] for i, authority in enumerate(authorities)}
        captures["table"] = normalize_table(captures["table"], port_map)
        captures["details"] = normalize_table(captures["details"], port_map)
        captures["json"] = normalize_json(captures["json"], port_map)
        document = {
            "source": "Sources/hashfleet/main.swift + Sources/HashFleetCore/FleetStatusService.swift; synthetic fixture based on App/Store/DemoFleet.swift",
            "binarySHA256": hashlib.sha256(BINARY.read_bytes()).hexdigest(),
            "normalization": "Capture-only: ephemeral 127.0.0.1 ports map by fixture index to *.invalid sample hosts; explicit-host row names map back to the corresponding DemoFleet configured names while preserving the host column, with native 20/28 character columns re-padded; JSON device names map to the same source names; UUIDs map by stable miner order; ISO-8601 timestamps map to 2026-01-01T12:00:00Z. Raw fixture excludes payout users/secrets. All status fields/formatting otherwise come from the binary.",
            "commands": captures,
            "tty": tty,
            "logo": logo,
            "requestAudit": observed,
        }
        OUT.write_text(json.dumps(document, indent=2, ensure_ascii=False) + "\n")
        print(f"Wrote {OUT.relative_to(ROOT)}")
        print(json.dumps({"binary":str(BINARY),"requests":observed,"commands":list(captures)}, indent=2))
    finally:
        for server in servers:
            server.shutdown()
            server.server_close()


def normalize_table(text, port_map):
    lines = text.splitlines()
    prefix = lines[:3]
    groups = []
    current = None
    for line in lines[3:]:
        if line.startswith("127.0.0.1:"):
            match = re.match(r"^(.{20}) (.{28}) (.{14}) (.{10}) (.{10}) (.{14}) (.{16}) (.*)$", line)
            if not match:
                raise RuntimeError(f"unexpected native table row: {line!r}")
            fields = list(match.groups())
            source = fields[0].strip()
            alias = port_map.get(source)
            if alias is None:
                raise RuntimeError(f"unknown fixture authority in row: {line!r}")
            fields[0] = f"{NAMES[ALIASES.index(alias)]:<20}"
            fields[1] = f"{alias:<28}"
            current = [" ".join(fields)]
            groups.append(current)
        else:
            if current is not None:
                current.append(line)
    groups.sort(key=lambda group: group[0][:20].strip().casefold())
    return "\n".join(prefix + [line for group in groups for line in group])


def normalize_json(text, port_map):
    data = json.loads(text)
    fixed_time = "2026-01-01T12:00:00Z"
    for index, miner in enumerate(data.get("miners", [])):
        original_address = miner["device"]["address"]
        alias = port_map.get(original_address)
        if alias is None:
            raise RuntimeError(f"unknown fixture authority in JSON: {original_address!r}")
        miner["device"]["address"] = alias
        stable_index = ALIASES.index(alias)
        miner["device"]["name"] = NAMES[stable_index]
        miner["device"]["id"] = str(uuid.UUID(f"00000000-0000-4000-8000-{stable_index+1:012d}"))
        miner["observedAt"] = fixed_time
    data["observedAt"] = fixed_time
    data["miners"].sort(key=lambda miner: miner["device"]["name"].casefold())
    return json.dumps(data, indent=2, sort_keys=True, ensure_ascii=False)

if __name__ == "__main__":
    main()
