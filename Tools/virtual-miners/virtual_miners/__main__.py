"""Run from Tools/virtual-miners: python3 -B -m virtual_miners --help."""

import argparse
import http.client
import json
import os
from pathlib import Path
import subprocess
import sys
import time

from .assets import emulator_asset, firmware_asset, install_asset
from .config import FIRMWARE_TAG, LabError, Miner, load
from .supervisor import control, control_path, instance_settings, private_directory, supervise


PROJECT = Path(__file__).resolve().parents[1]
DEFAULT_STATE = Path.home() / ".cache" / "hashfleet-vm"


def _parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(description="HashFleet Virtual Miner Lab (loopback only)")
    parser.add_argument("--config", type=Path, default=PROJECT / "lab.toml")
    parser.add_argument("--state-dir", type=Path, default=DEFAULT_STATE)
    parser.add_argument("--assets-dir", type=Path, help="pinned asset cache; default is STATE/assets")
    commands = parser.add_subparsers(dest="action", required=True)
    commands.add_parser("setup", help="download and verify pinned assets (the only online command)")
    for name, help_text in (
        ("list", "show configuration and process state"),
        ("start", "start configured miners in the background"),
        ("stop", "stop running miners without signaling arbitrary PIDs"),
    ):
        cmd = commands.add_parser(name, help=help_text)
        cmd.add_argument("names", nargs="*", help="omit to select all configured miners")
    cmd = commands.add_parser("run", help="run one miner in the foreground")
    cmd.add_argument("name")
    cmd = commands.add_parser("check", help="require a response from the selected backend (not just a live process)")
    cmd.add_argument("name")
    cmd.add_argument("--wait", type=int, default=20, choices=range(1, 121), metavar="SECONDS")
    return parser


def _matches(miner: Miner, status: dict) -> bool:
    return all(status.get(key) == value for key, value in instance_settings(miner).items())


def _check(miner: Miner, directory: Path, wait: int) -> dict:
    state = control(directory)
    if state is None or not _matches(miner, state):
        raise LabError(f"{miner.name}: configured instance is not running")
    deadline = time.monotonic() + wait
    code = "no HTTP response"
    while time.monotonic() < deadline:
        client = http.client.HTTPConnection("127.0.0.1", miner.http_port, timeout=2)
        try:
            client.request("GET", "/api/system/info")
            with client.getresponse() as response:
                code = str(response.status)
                if response.status == 200:
                    body = response.read(256 * 1024 + 1)
                    if len(body) > 256 * 1024:
                        raise LabError(f"{miner.name}: response too large")
                    data = json.loads(body)
                    if not isinstance(data, dict):
                        raise LabError(f"{miner.name}: expected a JSON object")
                    is_fixture = response.getheader("X-Virtual-Miner-Fixture") == "api-only"
                    if is_fixture != (miner.backend == "api-fixture"):
                        raise LabError(f"{miner.name}: HTTP backend did not match the selected mode")
                    if miner.backend == "esp-emu" and (
                        data.get("version") != FIRMWARE_TAG
                        or data.get("boardVersion") != miner.profile.revision
                        or data.get("ASICModel") != miner.profile.asic
                        or data.get("hostname") != miner.name
                    ):
                        raise LabError(f"{miner.name}: response does not match the pinned firmware/board identity")
                    return {
                        "name": miner.name, "backend": miner.backend, "status": 200,
                        "hostname": data.get("hostname"), "firmware": data.get("version"),
                        "board": data.get("boardVersion"), "asic": data.get("ASICModel"),
                    }
        except (OSError, http.client.HTTPException, ValueError):
            pass
        finally:
            client.close()
        time.sleep(0.2)
    raise LabError(f"{miner.name}: no ready HTTP API (last status {code}); see the run directory in 'list'")


def _start(miner: Miner, config: Path, state: Path, cache: Path) -> dict:
    directory = private_directory(state / miner.name)
    control_path(directory)
    if (status := control(directory)) is not None:
        if not _matches(miner, status):
            raise LabError(f"{miner.name} is already running with a different configuration; stop it first")
        return status
    command = [
        sys.executable, "-B", "-m", "virtual_miners", "--config", str(config),
        "--state-dir", str(state), "--assets-dir", str(cache), "run", miner.name,
    ]
    log = directory / "supervisor.log"
    with log.open("ab") as stream:
        child = subprocess.Popen(
            command, cwd=PROJECT, stdin=subprocess.DEVNULL,
            stdout=stream, stderr=subprocess.STDOUT, start_new_session=True,
        )
    deadline = time.monotonic() + 12
    while time.monotonic() < deadline:
        if child.poll() is not None:
            raise LabError(f"{miner.name}: start failed; see {log}")
        try:
            status = control(directory)
        except LabError:
            # The private socket can be bound up to eight seconds before the guest is ready.
            pass
        else:
            if status is not None:
                if not _matches(miner, status):
                    raise LabError(f"{miner.name} is already starting with a different configuration")
                return status
        time.sleep(0.05)
    if child.poll() is None:
        child.terminate()
        try:
            child.wait(timeout=7)
        except subprocess.TimeoutExpired:
            raise LabError(f"{miner.name}: supervisor did not exit; see {log}") from None
    raise LabError(f"{miner.name}: startup deadline exceeded; see {log}")


def _stop(name: str, directory: Path) -> dict:
    if control(directory, "stop") is not None:
        deadline = time.monotonic() + 8
        path = control_path(directory)
        while path.exists() and time.monotonic() < deadline:
            time.sleep(0.05)
        if path.exists():
            raise LabError(f"{name}: stop timed out; see the instance log")
    return {"name": name, "running": False}


def _execute(args: argparse.Namespace) -> None:
    config = args.config.resolve()
    state = args.state_dir.expanduser().absolute()
    cache = (args.assets_dir if args.assets_dir is not None else state / "assets").expanduser().absolute()
    miners = load(config)
    if args.action == "setup":
        private_directory(state)
        private_directory(cache)
        if not (profiles := {miner.profile for miner in miners.values() if miner.backend == "esp-emu"}):
            raise LabError("no real firmware selected; API fixtures need no downloads")
        for asset in (emulator_asset(), *sorted(map(firmware_asset, profiles), key=lambda item: item.file)):
            path = install_asset(cache, asset)
            print(f"{asset.sha256}  {path}")
        return
    if args.action in ("run", "start"):
        private_directory(state)
    names = [args.name] if args.action in ("run", "check") else args.names or list(miners)
    if unknown := next((name for name in names if name not in miners), None):
        raise LabError(f"unknown miner: {unknown}")
    for name in dict.fromkeys(names):
        miner = miners[name]
        if args.action == "run":
            supervise(miner, state, cache)
            return
        if args.action == "start":
            result = _start(miner, config, state, cache)
        elif args.action == "stop":
            result = _stop(name, state / name)
        elif args.action == "check":
            result = _check(miner, state / name, args.wait)
        else:
            result = control(state / name) or {
                "name": name, "running": False, "backend": miner.backend,
                "board": miner.board, "http_port": miner.http_port,
            }
        print(json.dumps(result), flush=True)


def main() -> int:
    os.umask(0o077)
    try:
        _execute(_parser().parse_args())
    except (LabError, OSError) as error:
        print(f"virtual-miners: {error}", file=sys.stderr, flush=True)
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main())
