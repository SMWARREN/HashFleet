#!/usr/bin/env python3
"""Exercise CLI Support in a real PTY using only demo data and loopback fixtures.

Receiving destinations are compared privately and never included in test messages.
No browser, wallet, clipboard or payment operation is performed.
"""
import argparse
import hmac
import http.server
from pathlib import Path
import re
import signal
import subprocess
import threading
import time
import unittest

import test_cli_dashboard as dashboard

ROOT = Path(__file__).resolve().parents[2]


def destinations():
    source = (ROOT / "Sources/HashFleetCore/DeveloperSupportCrypto.swift").read_text()
    values = dict(re.findall(r'case \.(bitcoin|ethereum|solana): "([^"\n]+)"', source))
    return [(symbol, name, values[key]) for symbol, name, key in [
        ("BTC", "Bitcoin", "bitcoin"), ("ETH", "Ethereum", "ethereum"),
        ("SOL", "Solana", "solana"),
    ]]


class SupportFixture(dashboard.Fixture):
    def do_POST(self):
        type(self).requests.append(("POST", self.path))
        self.send_error(405)

    do_PATCH = do_POST
    do_PUT = do_POST
    do_DELETE = do_POST


class InteractiveSupportTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.server = http.server.ThreadingHTTPServer(("127.0.0.1", 0), SupportFixture)
        cls.thread = threading.Thread(target=cls.server.serve_forever, daemon=True)
        cls.thread.start()
        cls.host = f"127.0.0.1:{cls.server.server_port}"

    @classmethod
    def tearDownClass(cls):
        cls.server.shutdown()
        cls.server.server_close()
        cls.thread.join(timeout=3)

    def setUp(self):
        SupportFixture.payload = {"hashRate": 1000, "temp": 50, "power": 20}
        SupportFixture.status = 200
        SupportFixture.delay = 0
        SupportFixture.requests = []

    def terminal(self, *args, **kwargs):
        terminal = dashboard.Terminal(*args, **kwargs)
        self.addCleanup(terminal.close)
        return terminal

    def wait(self, terminal, text, after=0, timeout=4):
        end = time.monotonic() + timeout
        while time.monotonic() < end:
            terminal.drain(0.1)
            # A PTY read can stop between the header and footer of one write.
            # Inspect only the newest frame after its existing terminator arrives.
            complete = dashboard.newest_complete_frame(terminal.output, after=after)
            if complete is not None and text.encode() in complete:
                return
        self.fail(f"Missing public UI label: {text!r}; screen contents withheld")

    def open_support(self, terminal, data=b"S"):
        self.wait(terminal, "q quit")
        offset = terminal.send(data)
        self.wait(terminal, "HASH FLEET / SUPPORT", after=offset)

    def assert_clean_exit(self, terminal):
        dashboard.DashboardTests.assert_clean_exit(self, terminal)

    def assert_frame_fits(self, terminal, columns, rows):
        self.wait(terminal, "q quit")
        lines = terminal.frame().splitlines()
        self.assertLessEqual(len(lines), rows)
        self.assertTrue(all(len(line) < columns for line in lines), "Support rows must fit the viewport")
        self.assertIn("q quit", terminal.frame(), "Quit must stay visible")

    def test_standalone_support_includes_exact_shared_crypto_destinations(self):
        result = subprocess.run([str(BINARY), "support"], capture_output=True, text=True, timeout=5)
        self.assertEqual(result.returncode, 0)
        self.assertEqual(result.stderr, "")
        lines = result.stdout.splitlines()
        for symbol, name, address in destinations():
            self.assertIn(f"{name} ({symbol})", lines, f"Missing {symbol} option")
            self.assertIn(f"Network: {name} mainnet", lines, f"Missing {symbol} network")
            self.assertTrue(any(hmac.compare_digest(address, line) for line in lines),
                            f"{symbol} must exactly reuse the shared destination")
        self.assertIn("No browser was opened", result.stdout)
        self.assertIn("generally irreversible", result.stdout)
        self.assertNotIn("\x1b", result.stdout)
        self.assertEqual(SupportFixture.requests, [])

    def test_help_and_supported_dashboard_sizes_advertise_support(self):
        result = subprocess.run([str(BINARY), "--help"], capture_output=True, text=True, timeout=5)
        self.assertEqual(result.returncode, 0)
        self.assertIn("Shift+S", result.stdout)
        self.assertIn("BTC/ETH/SOL", result.stdout)
        for columns, rows in [(120, 40), (80, 18), (60, 12), (45, 12)]:
            with self.subTest(columns=columns, rows=rows):
                terminal = self.terminal("watch", "--demo", columns=columns, rows=rows)
                self.wait(terminal, "S support")
                self.assert_frame_fits(terminal, columns, rows)
                self.open_support(terminal)
                self.assert_frame_fits(terminal, columns, rows)
                terminal.send(b"q")
                self.assert_clean_exit(terminal)
        self.assertEqual(SupportFixture.requests, [])

    def test_all_destinations_remain_intact_when_wrapped_scrolled_and_resized(self):
        terminal = self.terminal("watch", "--demo", columns=120, rows=40)
        self.open_support(terminal)
        for columns, rows in [(120, 40), (54, 12), (45, 12), (30, 8)]:
            with self.subTest(columns=columns, rows=rows):
                terminal.resize(columns, rows)
                terminal.send(b"g")
                terminal.drain(0.25)
                self.assert_frame_fits(terminal, columns, rows)
                match = re.search(r"Lines \d+-\d+/(\d+)", terminal.frame())
                self.assertIsNotNone(match, "Support must expose its scroll extent")
                seen = []
                for _ in range(int(match.group(1)) + 1):
                    self.assert_frame_fits(terminal, columns, rows)
                    seen.append("".join(line.strip() for line in terminal.frame().splitlines()[3:-3]))
                    terminal.send(b"j")
                    terminal.drain(0.12)
                combined = "".join(seen)
                # Every address can span at most two rows at the supported widths.
                # Assert on public symbols so a failure cannot print private destinations.
                shared_destinations = destinations()
                complete_symbols = {
                    symbol for symbol, _name, address in shared_destinations if address in combined
                }
                for symbol, _name, _address in shared_destinations:
                    self.assertIn(symbol, complete_symbols, f"{symbol} must remain complete, not truncated")
                terminal.send(b"G")
                terminal.drain(0.2)
                self.assert_frame_fits(terminal, columns, rows)
        offset = len(terminal.output)
        terminal.resize(20, 5)
        self.wait(terminal, "Resize to", after=offset)
        self.assert_frame_fits(terminal, 20, 5)
        terminal.send(b"q")
        self.assert_clean_exit(terminal)
        self.assertEqual(SupportFixture.requests, [])

    def test_support_returns_to_the_same_detail_and_logo_views(self):
        terminal = self.terminal("watch", "--demo", columns=100, rows=30)
        self.wait(terminal, "q quit")
        terminal.send(b"jd")
        self.wait(terminal, "DETAILS / Gamma / studio")
        self.open_support(terminal)
        offset = terminal.send(b"\x1b")
        self.wait(terminal, "DETAILS / Gamma / studio", after=offset)
        terminal.send(b"l")
        self.wait(terminal, "HASH FLEET / LOGO")
        for back in (b"b", b"S"):
            self.open_support(terminal)
            offset = terminal.send(back)
            self.wait(terminal, "HASH FLEET / LOGO", after=offset)
        terminal.send(b"q")
        self.assert_clean_exit(terminal)
        self.assertEqual(SupportFixture.requests, [])

    def test_support_transitions_discard_buffered_dashboard_actions(self):
        terminal = self.terminal("watch", "--demo", columns=100, rows=30)
        self.open_support(terminal, b"Sqre")
        self.assertIsNone(terminal.process.poll())
        terminal.send(b"redls \r\n")
        terminal.drain(0.25)
        self.assertIn("HASH FLEET / SUPPORT", terminal.frame())
        self.assertNotIn("SETTINGS", terminal.frame())
        offset = terminal.send(b"bre")
        self.wait(terminal, "S support", after=offset)
        self.assertNotIn("HASH FLEET / SUPPORT", terminal.frame())
        self.assertNotIn("SETTINGS", terminal.frame())
        self.assertIn("sort: name", terminal.frame())
        terminal.send(b"q")
        self.assert_clean_exit(terminal)
        self.assertEqual(SupportFixture.requests, [])

    def test_support_suspends_new_polls_and_ignores_hardware_shortcuts(self):
        terminal = self.terminal("watch", self.host, columns=100, rows=30)
        self.wait(terminal, "next refresh")
        before = list(SupportFixture.requests)
        self.assertEqual(before, [("GET", "/api/system/info")])
        self.open_support(terminal)
        terminal.send(b"redls \r\n")
        terminal.drain(5.4)
        self.assertEqual(SupportFixture.requests, before)
        self.assertIn("HASH FLEET / SUPPORT", terminal.frame())
        offset = terminal.send(b"b")
        self.wait(terminal, "S support", after=offset)
        end = time.monotonic() + 3
        while SupportFixture.requests == before and time.monotonic() < end:
            terminal.drain(0.1)
        self.assertEqual(SupportFixture.requests, before + before)
        terminal.send(b"q")
        self.assert_clean_exit(terminal)

    def test_support_quit_and_control_keys_restore_terminal(self):
        for key in (b"q", b"Q", b"\x03", b"\x04"):
            with self.subTest(key=key):
                terminal = self.terminal("watch", "--demo", columns=80, rows=20)
                self.open_support(terminal)
                terminal.send(key)
                self.assert_clean_exit(terminal)
        terminal = self.terminal("watch", "--demo")
        self.open_support(terminal)
        terminal.process.send_signal(signal.SIGTERM)
        self.assert_clean_exit(terminal)
        self.assertEqual(SupportFixture.requests, [])

    def test_pasted_support_shortcuts_are_not_executed(self):
        terminal = self.terminal("watch", "--demo")
        self.wait(terminal, "S support")
        terminal.send(b"\x1b[200~Sqr\x1b[201~")
        terminal.drain(0.25)
        self.assertNotIn("HASH FLEET / SUPPORT", terminal.frame())
        self.open_support(terminal)
        terminal.send(b"\x1b[200~bqr\x1b[201~")
        terminal.drain(0.25)
        self.assertIn("HASH FLEET / SUPPORT", terminal.frame())
        terminal.send(b"\x03")
        self.assert_clean_exit(terminal)
        self.assertEqual(SupportFixture.requests, [])


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--binary", type=Path, required=True)
    args = parser.parse_args()
    BINARY = args.binary.resolve(strict=True)
    dashboard.BINARY = BINARY
    unittest.main(argv=[__file__], verbosity=2)
