"""Offline runner contract tests. Real firmware acceptance runs separately."""

from contextlib import ExitStack
from pathlib import Path
from types import SimpleNamespace
import http.client
import json
import os
import platform
import socket
import subprocess
import sys
import tempfile
import unittest
from unittest.mock import patch

from virtual_miners import backend
from virtual_miners.assets import emulator_asset
from virtual_miners.config import LabError, load


ROOT = Path(__file__).resolve().parents[1]
INSTANCE = '''[[miner]]
name = "first"
board = "gamma-601"
backend = "api-fixture"
http_port = 18081
'''


def open_ports(count: int) -> list[int]:
    with ExitStack() as sockets:
        result = []
        for _ in range(count):
            listener = sockets.enter_context(socket.socket())
            listener.bind(("127.0.0.1", 0))
            result.append(listener.getsockname()[1])
        return result


def request(port: int, path: str, method: str = "GET") -> tuple[int, bytes, str | None]:
    connection = http.client.HTTPConnection("127.0.0.1", port, timeout=3)
    try:
        connection.request(method, path)
        with connection.getresponse() as reply:
            return reply.status, reply.read(), reply.getheader("X-Virtual-Miner-Fixture")
    finally:
        connection.close()


class RunnerContractTests(unittest.TestCase):
    def setUp(self) -> None:
        self.state = Path(self.enterContext(tempfile.TemporaryDirectory(prefix="hf-", dir=os.environ.get("JCODE_SCRATCH_DIR"))))
        self.config = self.state / "lab.toml"

    def cli(self, *arguments: str, succeeds: bool = True) -> subprocess.CompletedProcess:
        result = subprocess.run(
            [sys.executable, "-B", "-m", "virtual_miners", "--state-dir", str(self.state),
             "--config", str(self.config), *arguments],
            cwd=ROOT, capture_output=True, text=True, timeout=24,
        )
        self.assertEqual(result.returncode == 0, succeeds, result.stderr)
        return result

    def test_configuration_rejects_external_target_and_nonliteral_settings(self) -> None:
        for text in (
            INSTANCE + 'host = "example.invalid"\n',
            INSTANCE.replace('"first"', '"../escape"'),
            INSTANCE.replace('18081', 'true'),
            INSTANCE + 'power_w = nan\n',
            INSTANCE + 'scenario = "overheat"\n',
            INSTANCE + INSTANCE.replace('"first"', '"second"'),
            INSTANCE + INSTANCE.replace('18081', '18082'),
        ):
            with self.subTest(text=text):
                self.config.write_text(text)
                with self.assertRaises(LabError):
                    load(self.config)

    def test_multiple_fixtures_lifecycle_denies_writes_does_not_download(self) -> None:
        first, second = open_ports(2)
        self.config.write_text(
            INSTANCE.replace("18081", str(first))
            + INSTANCE.replace('"first"', '"second"').replace("18081", str(second))
            + 'scenario = "degraded"\n'
        )
        self.addCleanup(self.cli, "stop")
        self.cli("setup", succeeds=False)
        self.cli("start")
        self.cli("start", "first")  # idempotent; sibling stays alive
        for port, name, health in [(first, "first", "ok"), (second, "second", "degraded")]:
            status, raw, marker = request(port, "/api/system/info")
            self.assertEqual((status, marker, json.loads(raw)["hostname"]), (200, "api-only", name))
            self.assertEqual(json.loads(request(port, "/healthz")[1])["status"], health)
            self.assertEqual(request(port, "/api/system/restart", "POST")[0], 405)
        self.assertEqual(json.loads(self.cli("check", "second").stdout)["backend"], "api-fixture")
        self.cli("stop", "first")
        self.assertFalse(json.loads(self.cli("list", "first").stdout)["running"])
        self.assertEqual(request(second, "/api/system/info")[0], 200)
        self.cli("start", "first")
        self.assertEqual(request(first, "/api/system/info")[0], 200)

        self.config.write_text(self.config.read_text().replace('scenario = "degraded"', 'scenario = "normal"'))
        self.assertIn("different configuration", self.cli("start", "second", succeeds=False).stderr)
        self.cli("check", "second", succeeds=False)
        self.assertEqual(json.loads(request(second, "/healthz")[1])["status"], "degraded")

    def test_missing_or_corrupt_asset_cannot_become_api_fixture(self) -> None:
        port = open_ports(1)[0]
        self.config.write_text(INSTANCE.replace("18081", str(port)).replace('"api-fixture"', '"esp-emu"'))
        try:
            asset = emulator_asset()
        except LabError as error:
            self.skipTest(str(error))
        self.addCleanup(self.cli, "stop")
        self.cli("start", succeeds=False)
        cache = self.state / "assets"
        cache.mkdir(mode=0o700)
        (cache / asset.file).write_bytes(b"corrupt")
        self.cli("start", succeeds=False)
        self.assertFalse(json.loads(self.cli("list", "first").stdout)["running"])
        self.assertIn("digest mismatch", (self.state / "first" / "supervisor.log").read_text())
        with self.assertRaises(OSError):
            request(port, "/api/system/info")

    def test_linux_runner_refuses_a_non_loopback_interface(self) -> None:
        with patch.object(backend.platform, "system", return_value="Linux"), \
             patch.object(Path, "iterdir", return_value=iter([Path("lo"), Path("eth0")])):
            with self.assertRaisesRegex(LabError, "--network none"):
                backend.isolated_command(["esp-emu"])

    def test_native_listener_verifier_refuses_non_loopback_or_extra_port(self) -> None:
        child = SimpleNamespace(pid=123)
        with patch.object(backend.platform, "system", return_value="Darwin"), \
             patch.object(subprocess, "run") as run:
            run.return_value = SimpleNamespace(returncode=0, stdout="p123\nn127.0.0.1:18081\n")
            backend._verify_native_listeners(child, (18081,))
            for names in ("n*:18081\n", "n127.0.0.1:18081\nn127.0.0.1:18082\n", ""):
                run.return_value.stdout = "p123\n" + names
                with self.assertRaisesRegex(LabError, "loopback"):
                    backend._verify_native_listeners(child, (18081,))

    @unittest.skipUnless(platform.system() == "Darwin", "native macOS sandbox example")
    def test_macos_sandbox_allows_assigned_tcp_port_but_not_egress_or_extra_listeners(self) -> None:
        allowed, forbidden = open_ports(2)
        code = '''import errno, socket, sys
allowed, forbidden = map(int, sys.argv[1:])
with socket.socket() as local:
    local.bind(("127.0.0.1", allowed))
    local.listen()
    with socket.socket() as tcp:
        assert tcp.connect_ex(local.getsockname()) in (errno.EPERM, errno.EACCES)
    with socket.socket(socket.AF_INET, socket.SOCK_DGRAM) as udp:
        try:
            udp.sendto(b"isolated", local.getsockname())
        except PermissionError:
            pass
        else:
            raise AssertionError("guest can originate UDP")
    for address, port, socktype in [("127.0.0.1", forbidden, socket.SOCK_STREAM),
                                    ("0.0.0.0", forbidden, socket.SOCK_STREAM),
                                    ("127.0.0.1", allowed, socket.SOCK_DGRAM)]:
        with socket.socket(socket.AF_INET, socktype) as extra:
            try:
                extra.bind((address, port))
            except PermissionError:
                pass
            else:
                raise AssertionError("guest bound to an unassigned listener")
'''
        command = backend.isolated_command(
            [sys.executable, "-B", "-c", code, str(allowed), str(forbidden)], listener_ports=(allowed,),
        )
        completed = subprocess.run(command, capture_output=True, text=True, timeout=10)
        self.assertEqual(completed.returncode, 0, completed.stderr)
