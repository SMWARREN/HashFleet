"""Opt-in real-firmware acceptance. Uses existing pinned assets and no physical hosts."""

import argparse
import http.client
import json
import os
from pathlib import Path
import subprocess
import sys
import tempfile
import time

from virtual_miners.backend import _ports


def require(condition: bool, message: str) -> None:
    if not condition:
        raise RuntimeError(message)


def read(port: int, path: str, method: str = "GET") -> tuple[int, dict]:
    client = http.client.HTTPConnection("127.0.0.1", port, timeout=4)
    try:
        client.request(method, path)
        with client.getresponse() as response:
            body = response.read(1_048_577)
            require(len(body) <= 1_048_576, "gateway exceeded its response limit")
            require(response.getheader("X-Virtual-Miner-Fixture") is None, "unexpected API-only fixture")
            return response.status, json.loads(body) if response.status == 200 else {}
    finally:
        client.close()


def wait_for_serial(log: Path, markers: tuple[str, ...]) -> None:
    deadline = time.monotonic() + 25
    while time.monotonic() < deadline:
        text = log.read_text(errors="replace")
        if all(marker in text for marker in markers):
            return
        time.sleep(0.2)
    raise RuntimeError(f"original firmware markers not observed: {markers}; see {log}")


def verify(assets: Path, state: Path, hashfleet: Path) -> None:
    config = state / "test.toml"
    ports = dict(zip(("normal", "missing", "hot", "offline", "no-power"), _ports(5, 0), strict=True))
    scenarios = dict(zip(ports, ("normal", "asic-missing", "overheat", "offline", "no-power"), strict=True))
    config.write_text("\n".join(
        f'[[miner]]\nname = "{name}"\nboard = "gamma-601"\nbackend = "esp-emu"\n'
        f'http_port = {port}\nscenario = "{scenarios[name]}"\n'
        for name, port in ports.items()
    ), encoding="ascii")
    command = [sys.executable, "-B", "-m", "virtual_miners", "--config", str(config),
               "--state-dir", str(state), "--assets-dir", str(assets)]

    def lab(*args: str) -> list[dict]:
        result = subprocess.run(command + list(args), cwd=Path(__file__).parent, check=True,
                                capture_output=True, text=True, timeout=40)
        return [json.loads(line) for line in result.stdout.splitlines()]

    def cli(expected: str, *names: str, exit_code: int = 0) -> None:
        # Explicit addresses bypass HashFleet's device discovery and never read the local fleet.
        targets = [f"127.0.0.1:{ports[name]}" for name in names]
        result = subprocess.run([str(hashfleet), "status", *targets],
                                capture_output=True, text=True, timeout=18)
        require(expected in result.stdout and result.returncode == exit_code,
                f"HashFleet did not report {expected} with exit {exit_code}:\n{result.stdout}{result.stderr}")
        print(f"HashFleet status: {expected} (exit {exit_code})")

    def run_logs(*names: str) -> dict[str, Path]:
        active = lab("start", *names)
        for name in names:
            checked = lab("check", name)[0]
            require(checked["backend"] == "esp-emu" and checked["hostname"] == name,
                    f"wrong firmware identity for {name}")
        return {item["name"]: Path(item["run"]) / "serial.log" for item in active}

    try:
        logs = run_logs("normal", "missing")
        wait_for_serial(logs["normal"], (
            "TPS546: Device ID: 54 49 54 6d 24 41", "EMC2101: Initializing EMC2101",
            "common: Chip 0 detected:", "Changing UART baud to 1000000",
            "ASIC initialized successfully with 1 chip(s)",
        ))
        wait_for_serial(logs["missing"], ("ASIC 0 not found", "ASIC initialization failed"))
        code, info = read(ports["normal"], "/api/system/info")
        require(code == 200 and info.get("fanrpm") == 3000, "original EMC2101 fan telemetry missing")
        stats_code, stats = read(ports["normal"], "/api/system/statistics")
        require(stats_code == 200 and {"labels", "statistics"} <= stats.keys(), "original statistics shape missing")
        for method, route, expected in (
            ("POST", "/api/system/restart", 405), ("PATCH", "/api/system", 405),
            ("GET", "/api/ws", 404), ("GET", "/api/system/statistics?columns=power", 404),
        ):
            require(read(ports["normal"], route, method)[0] == expected, f"unexpected gateway result: {method} {route}")
        cli("2/2 online", "normal", "missing")

        lab("stop", "normal")
        cli("1/2 online", "normal", "missing", exit_code=1)
        new_log = run_logs("normal")["normal"]
        require(new_log != logs["normal"], "restart reused private guest flash")
        wait_for_serial(new_log, ("ASIC initialized successfully with 1 chip(s)",))
        cli("2/2 online", "normal", "missing")
        lab("stop", "normal", "missing")

        faults = run_logs("hot", "offline", "no-power")
        wait_for_serial(faults["no-power"], ("Cannot find TPS546 regulator",))
        wait_for_serial(faults["hot"], (
            "ASIC initialized successfully with 1 chip(s)",
            "Entering safe mode due to overheat condition",
        ))
        wait_for_serial(faults["offline"], ("http_server: Starting HTTP Server",))
        code, hot = read(ports["hot"], "/api/system/info")
        temp = hot.get("temp")
        require(code == 200 and type(temp) in (int, float) and temp >= 95,
                "guest HTTP did not report the injected overheat temperature")
        offline = read(ports["offline"], "/api/system/info")[1]
        require(offline.get("wifiStatus") != "Connected!", "offline station unexpectedly connected")
        print("Native GET-only guard, board faults, and independent restart verified.")
        print(f"The original firmware reported {temp} °C and entered its overheat safe mode.")
    finally:
        lab("stop")


def main() -> None:
    os.umask(0o077)
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--assets-dir", type=Path, default=Path.home() / ".cache/hashfleet-vm/assets")
    parser.add_argument("--hashfleet", type=Path, default=Path(__file__).resolve().parents[2] / ".build/debug/hashfleet")
    arguments = parser.parse_args()
    state = Path(tempfile.mkdtemp(prefix="hf-native-", dir=os.environ.get("JCODE_SCRATCH_DIR")))
    print(f"Private native evidence: {state}", flush=True)
    try:
        verify(arguments.assets_dir.expanduser().resolve(), state, arguments.hashfleet.expanduser().resolve(strict=True))
    except (RuntimeError, OSError, subprocess.SubprocessError) as error:
        if isinstance(error, subprocess.CalledProcessError) and error.stderr:
            print(error.stderr.strip(), file=sys.stderr)
        raise SystemExit(str(error)) from None


if __name__ == "__main__":
    main()
