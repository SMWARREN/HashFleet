#!/usr/bin/env python3
"""Exercise the real dashboard in a PTY against loopback fixtures, never real miners."""
import argparse
import errno
import fcntl
import http.server
import json
import os
import pathlib
import pty
import re
import select
import signal
import struct
import subprocess
import termios
import threading
import time
import unittest


class Fixture(http.server.BaseHTTPRequestHandler):
    payload = {}
    status = 200
    delay = 0
    requests = []

    def do_GET(self):
        type(self).requests.append(("GET", self.path))
        time.sleep(type(self).delay)
        body = json.dumps(type(self).payload).encode()
        try:
            self.send_response(type(self).status)
            self.send_header("Content-Length", str(len(body)))
            self.end_headers()
            self.wfile.write(body)
        except (BrokenPipeError, ConnectionResetError):
            pass

    def log_message(self, *_args):
        # Silence per-request stderr logging from the fixture HTTP server.
        pass


def newest_complete_frame(output, after=0):
    """Return only the newest ANSI-home frame, once its own terminator arrives."""
    start = output.rfind(b"\x1b[H", after)
    if start < 0:
        return None
    start += len(b"\x1b[H")
    end = output.find(b"\x1b[J", start)
    return None if end < 0 else output[start:end]


class Terminal:
    def __init__(self, *args, columns=120, rows=28, colors=False, redirect_input=False):
        self.master, self.slave = pty.openpty()
        self.original = termios.tcgetattr(self.slave)
        self.resize(columns, rows)
        self.output = b""
        environment = {**os.environ, "TERM": "xterm-256color", "COLORTERM": "truecolor"}
        if colors:
            environment.pop("NO_COLOR", None)
        else:
            environment["NO_COLOR"] = "1"
        self.process = subprocess.Popen(
            [str(BINARY), *args], stdin=subprocess.DEVNULL if redirect_input else self.slave,
            stdout=self.slave, stderr=self.slave,
            env=environment,
        )

    def resize(self, columns, rows):
        fcntl.ioctl(self.slave, termios.TIOCSWINSZ, struct.pack("HHHH", rows, columns, 0, 0))

    def drain(self, seconds=0.15):
        end = time.monotonic() + seconds
        while time.monotonic() < end:
            if select.select([self.master], [], [], min(0.05, end - time.monotonic()))[0]:
                try:
                    chunk = os.read(self.master, 65536)
                    if not chunk:
                        break
                    self.output += chunk
                except OSError as error:
                    if error.errno != errno.EIO:
                        raise
                    break

    def wait_for(self, text, after=0, timeout=5):
        end = time.monotonic() + timeout
        while time.monotonic() < end:
            self.drain(0.1)
            if text.encode() in self.output[after:]:
                return
        raise AssertionError(f"Missing {text!r}: {self.output[after:].decode(errors='replace')}")

    def send(self, data):
        offset = len(self.output)
        os.write(self.master, data)
        return offset

    def frame(self, timeout=5):
        raw = self.output
        if b"\x1b[H" in raw:
            end = time.monotonic() + timeout
            while (raw := newest_complete_frame(self.output)) is None:
                remaining = end - time.monotonic()
                if remaining <= 0:
                    raise AssertionError("Newest CLI frame is incomplete; screen contents withheld")
                self.drain(min(0.1, remaining))
        raw = raw.decode(errors="replace")
        return re.sub(r"\x1b\[[0-9;?]*[a-zA-Z]", "", raw).replace("\r", "")

    def close(self):
        if self.process.poll() is None:
            self.send(b"q")
            try:
                self.process.wait(timeout=3)
            except subprocess.TimeoutExpired:
                self.process.kill()
                self.process.wait(timeout=3)
        self.drain()
        os.close(self.master)
        os.close(self.slave)


class DashboardTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.server = http.server.ThreadingHTTPServer(("127.0.0.1", 0), Fixture)
        cls.thread = threading.Thread(target=cls.server.serve_forever, daemon=True)
        cls.thread.start()
        cls.host = f"127.0.0.1:{cls.server.server_port}"

    @classmethod
    def tearDownClass(cls):
        cls.server.shutdown()
        cls.server.server_close()
        cls.thread.join(timeout=3)

    def setUp(self):
        Fixture.payload = {"hashRate": 1000, "temp": 50, "power": 20, "bestDiff": "8M", "bestSessionDiff": "2M"}
        Fixture.status = 200
        Fixture.delay = 0
        Fixture.requests = []

    def terminal(self, *args, **kwargs):
        terminal = Terminal(*args, **kwargs)
        self.addCleanup(terminal.close)
        return terminal

    def assert_clean_exit(self, terminal):
        self.assertEqual(terminal.process.wait(timeout=3), 0)
        terminal.drain()
        restored = termios.tcgetattr(terminal.slave)
        original = terminal.original.copy()
        # macOS sets this kernel-managed flag when canonical input is re-enabled.
        restored[3] &= ~termios.PENDIN
        original[3] &= ~termios.PENDIN
        self.assertEqual(restored, original)
        self.assertIn(b"\x1b[?25h\x1b[?1049l", terminal.output)

    def assert_snapshot_exit(self, terminal, code=0):
        end = time.monotonic() + 5
        while terminal.process.poll() is None and time.monotonic() < end:
            terminal.drain()
        self.assertEqual(terminal.process.poll(), code)
        terminal.drain()
        self.assertEqual(termios.tcgetattr(terminal.slave), terminal.original)
        # A snapshot belongs in scrollback and must not switch screen or cursor modes.
        self.assertNotIn(b"\x1b[?", terminal.output)
        self.assertNotIn(b"\x1b[H", terminal.output)
        self.assertNotIn(b"\x1b[K", terminal.output)

    def test_status_has_real_logo_and_colors_with_redirected_stdin(self):
        terminal = self.terminal("status", self.host, colors=True, redirect_input=True, columns=150, rows=12)
        self.assert_snapshot_exit(terminal)
        self.assertIn("▀", terminal.frame())
        self.assertIn("HASH FLEET", terminal.frame())
        self.assertIn("STATUS", terminal.frame())
        self.assertIn("1/1 online", terminal.frame())
        self.assertIn("BEST (SESSION)", terminal.frame())
        self.assertIn(b"\x1b[38;2;87;190;133mONLINE", terminal.output)
        self.assertIn(b"\x1b[38;2;122;182;236m", terminal.output)
        self.assertNotIn("view logo", terminal.frame())
        self.assertTrue(all(len(line) <= 124 for line in terminal.frame().splitlines()))
        self.assertEqual(Fixture.requests, [("GET", "/api/system/info")])

    def test_status_fits_narrow_panes_and_no_color_has_no_escapes(self):
        for columns in (80, 54, 32):
            with self.subTest(columns=columns):
                terminal = self.terminal("status", self.host, columns=columns, rows=12)
                self.assert_snapshot_exit(terminal)
                self.assertNotIn(b"\x1b", terminal.output)
                self.assertIn("HASH FLEET", terminal.frame())
                self.assertIn("ONLINE", terminal.frame())
                self.assertIn("Best ever", terminal.frame())
                self.assertIn("Best this session", terminal.frame())
                self.assertRegex(terminal.frame(), r"8[.,]00M")
                self.assertRegex(terminal.frame(), r"2[.,]00M")
                self.assertRegex(terminal.frame(), r"[+*#%@]{2,}")
                self.assertTrue(all(len(line) < columns for line in terminal.frame().splitlines()))

    def test_status_uses_reported_health_colors_and_preserves_offline_exit(self):
        for field, label, color in [("miningPaused", "PAUSED", b"242;193;102"),
                                    ("overheat_mode", "OVERHEAT", b"242;119;119")]:
            with self.subTest(field=field):
                Fixture.payload[field] = True
                terminal = self.terminal("status", self.host, colors=True)
                self.assert_snapshot_exit(terminal)
                self.assertIn(b"\x1b[38;2;" + color + b"m" + label.encode(), terminal.output)
                del Fixture.payload[field]
        Fixture.status = 503
        terminal = self.terminal("status", self.host, colors=True)
        self.assert_snapshot_exit(terminal, code=1)
        self.assertIn(b"\x1b[38;2;242;119;119mOFFLINE", terminal.output)
        self.assertIn("0/1 online", terminal.frame())

    def test_status_json_in_terminal_has_no_branding_or_escapes(self):
        terminal = self.terminal("status", "--json", self.host, colors=True)
        self.assert_snapshot_exit(terminal)
        self.assertNotIn(b"\x1b", terminal.output)
        self.assertNotIn(b"HASH FLEET", terminal.output)
        self.assertEqual(json.loads(terminal.output)["miners"][0]["info"]["bestSessionDiff"], "2M")

    def test_logo_command_uses_image_colors_without_miner_requests(self):
        result = subprocess.run([str(BINARY), "logo"], capture_output=True, text=True, timeout=3)
        self.assertEqual(result.returncode, 0)
        self.assertNotIn("\x1b", result.stdout)
        self.assertEqual(len(result.stdout.splitlines()), 21)
        self.assertRegex(result.stdout, r"[+*#%@]{2,}")
        terminal = self.terminal("logo", colors=True, columns=120, rows=12)
        self.assert_snapshot_exit(terminal)
        self.assertEqual(terminal.frame().splitlines()[0], "HASH FLEET")
        self.assertEqual(len(terminal.frame().splitlines()), 21)
        artwork = terminal.frame().splitlines()[1:]
        self.assertTrue(all(len(line) == 33 for line in artwork))
        self.assertTrue(all(set(line) <= set(" ▀▄") for line in artwork))
        # Transparent margins and partial edge cells must use the terminal's own background.
        self.assertLess(sum(line.count("▀") for line in artwork), 32 * 20)
        self.assertRegex(terminal.output, rb"\x1b\[38;2;\d+;\d+;\d+;49m")
        self.assertIn(b"\x1b[38;2;245;172;38m", terminal.output)
        bad = subprocess.run([str(BINARY), "logo", self.host], capture_output=True, timeout=3)
        self.assertEqual(bad.returncode, 64)
        self.assertEqual(Fixture.requests, [])

    def test_logo_preview_uses_image_colors_and_resizes_with_controls_visible(self):
        terminal = self.terminal("watch", "--demo", columns=120, rows=70, colors=True)
        terminal.wait_for("q quit")
        offset = terminal.send(b"l")
        terminal.wait_for("l return to fleet", after=offset)
        self.assertIn("▀", terminal.frame())
        self.assertLessEqual(len(terminal.frame().splitlines()), 70)
        offset = len(terminal.output)
        terminal.resize(54, 16)
        terminal.wait_for("l return to fleet", after=offset)
        self.assertLessEqual(len(terminal.frame().splitlines()), 16)
        self.assertTrue(all(len(line) <= 53 for line in terminal.frame().splitlines()))
        self.assertIn("▀", terminal.frame())
        terminal.send(b"q")
        self.assert_clean_exit(terminal)
        self.assertEqual(Fixture.requests, [])

    def test_interactive_default_and_quit_restore_terminal(self):
        terminal = self.terminal(self.host)
        terminal.wait_for("1/1")
        self.assertIn("HASH FLEET", terminal.frame())
        self.assertIn("q quit", terminal.frame())
        self.assertIn("BEST (SESSION)", terminal.frame())
        self.assertEqual(Fixture.requests, [("GET", "/api/system/info")])
        terminal.send(b"q")
        self.assert_clean_exit(terminal)

    def test_demo_navigation_details_sort_and_no_requests(self):
        terminal = self.terminal("watch", "--demo")
        terminal.wait_for("DEMO · SAMPLE DATA")
        terminal.wait_for("Naja Duo / spare")
        terminal.send(b"jd")
        terminal.wait_for("DETAILS / Gamma / studio")
        terminal.send(b"s")
        terminal.drain()
        self.assertIn("DETAILS / Gamma / studio", terminal.frame())
        terminal.send(b"\x1b[")  # Arrow key split across reads.
        terminal.drain()
        terminal.send(b"D")
        terminal.wait_for("DETAILS / Gamma / desk")
        terminal.send(b"l")
        terminal.wait_for("HASH FLEET / LOGO")
        offset = terminal.send(b"l")
        terminal.wait_for("DETAILS / Gamma / desk", after=offset)
        self.assertEqual(Fixture.requests, [])

    def test_polling_pause_and_manual_refresh(self):
        terminal = self.terminal("watch", self.host)
        terminal.wait_for("1/1")
        offset = len(terminal.output)
        terminal.wait_for("Refreshing miner readings", after=offset, timeout=7)
        terminal.wait_for("next refresh", after=offset)
        self.assertGreaterEqual(len(Fixture.requests), 2)
        offset = terminal.send(b" ")
        terminal.wait_for("PAUSED", after=offset)
        requests = len(Fixture.requests)
        terminal.drain(5.3)
        self.assertEqual(len(Fixture.requests), requests)
        terminal.send(b"r")
        end = time.monotonic() + 3
        while len(Fixture.requests) == requests and time.monotonic() < end:
            terminal.drain()
        self.assertEqual(len(Fixture.requests), requests + 1)
        self.assertTrue(all(request == ("GET", "/api/system/info") for request in Fixture.requests))

    def test_offline_recovers_and_missing_metrics_are_not_zero_totals(self):
        Fixture.status = 503
        terminal = self.terminal("watch", self.host)
        terminal.wait_for("0/1")
        self.assertIn("OFFLINE", terminal.frame())
        self.assertRegex(terminal.frame(), r"HASHRATE\s+--")
        Fixture.status = 200
        Fixture.payload = {"temp": 0}
        offset = terminal.send(b"r")
        terminal.wait_for("1/1", after=offset)
        self.assertIn("Subtotals", terminal.frame())
        self.assertRegex(terminal.frame(), r"POWER\s+--")
        self.assertRegex(terminal.frame(), r"0(?:[.,]0)? °C")

    def test_resize_small_panes_keep_controls_and_paginate(self):
        terminal = self.terminal("watch", "--demo", columns=80, rows=12)
        terminal.wait_for("1–1 of 4")
        self.assertIn("q quit", terminal.frame())
        terminal.send(b"jjj")
        terminal.wait_for("4–4 of 4")
        offset = len(terminal.output)
        terminal.resize(54, 12)
        terminal.wait_for("Naja Duo / spare", after=offset)
        frame = terminal.frame()
        self.assertLessEqual(len(frame.splitlines()), 12)
        self.assertIn("q quit", frame)
        self.assertTrue(all(len(line) <= 53 for line in frame.splitlines()))
        offset = len(terminal.output)
        terminal.resize(30, 8)
        terminal.wait_for("Resize to", after=offset)
        self.assertIn("q quit", terminal.frame())

    def test_signals_restore_terminal_even_during_request(self):
        for exit_signal in (signal.SIGINT, signal.SIGTERM, signal.SIGHUP):
            with self.subTest(exit_signal=exit_signal):
                Fixture.delay = 2
                terminal = self.terminal("watch", self.host)
                terminal.wait_for("Refreshing miner readings")
                terminal.process.send_signal(exit_signal)
                self.assert_clean_exit(terminal)

    def test_control_c_quits_without_waiting_for_network(self):
        Fixture.delay = 3
        terminal = self.terminal("watch", self.host)
        terminal.wait_for("Refreshing miner readings")
        start = time.monotonic()
        terminal.send(b"\x03")
        self.assert_clean_exit(terminal)
        self.assertLess(time.monotonic() - start, 1.5)

    def test_control_c_interrupts_incomplete_escape_and_paste_sequences(self):
        for prefix in (b"\x1b[", b"\x1b[200~unfinished paste"):
            with self.subTest(prefix=prefix):
                terminal = self.terminal("watch", "--demo", columns=80, rows=12)
                terminal.wait_for("q quit")
                terminal.send(prefix)
                terminal.drain()
                terminal.send(b"\x03")
                self.assert_clean_exit(terminal)

    def test_firmware_text_cannot_inject_terminal_commands(self):
        Fixture.payload["ASICModel"] = "chip\x1b[2J\nINJECT\u009b31m\u202ereverse"
        terminal = self.terminal("watch", "--details", self.host, rows=32)
        terminal.send(b"3")
        terminal.wait_for("INJECT")
        self.assertNotIn(b"chip\x1b", terminal.output)
        self.assertNotIn("\u009b", terminal.output.decode(errors="replace"))
        self.assertNotIn("\u202e", terminal.output.decode(errors="replace"))
        self.assertIn("q quit", terminal.frame())

    def test_details_have_color_sections_scrolling_and_a_way_back(self):
        terminal = self.terminal("watch", "--demo", "--details", colors=True, columns=90, rows=22)
        terminal.wait_for("SHARES & RECORDS")
        self.assertIn(b"\x1b[38;2;122;182;236m", terminal.output)
        self.assertIn(b"\x1b[38;2;87;190;133m", terminal.output)
        self.assertNotIn("Transport:", terminal.frame())
        self.assertNotIn("Primary pool error", terminal.frame())
        offset = terminal.send(b"2")
        terminal.wait_for("1 minute", after=offset)
        offset = terminal.send(b"3")
        terminal.wait_for("COOLING & POWER", after=offset)
        offset = terminal.send(b"jjjjjjjjjjjjjjjj")
        terminal.wait_for("Wi-Fi signal", after=offset)
        self.assertIn("q quit", terminal.frame())
        offset = terminal.send(b"4")
        terminal.wait_for("solo.ckpool.org", after=offset)
        offset = terminal.send(b"\x1b")
        terminal.wait_for("MINER", after=offset)
        self.assertNotIn("DETAILS /", terminal.frame())

    def test_short_details_keep_navigation_and_scroll_to_hidden_values(self):
        terminal = self.terminal("watch", "--demo", "--details", columns=54, rows=12)
        terminal.wait_for("AT A GLANCE")
        self.assertIn("q quit", terminal.frame())
        offset = terminal.send(b"3")
        terminal.wait_for("COOLING & POWER", after=offset)
        offset = terminal.send(b"j" * 40)
        terminal.wait_for("Wi-Fi signal", after=offset)
        self.assertLessEqual(len(terminal.frame().splitlines()), 12)
        self.assertTrue(all(len(line) <= 53 for line in terminal.frame().splitlines()))
        offset = terminal.send(b"d")
        terminal.wait_for("sort: name", after=offset)

    def test_redirected_defaults_and_invalid_options_make_no_dashboard_requests(self):
        for args in [("watch", self.host), ("watch", "--json", self.host),
                     ("watch", "--interval", "nan", self.host), ("watch", "--interval", "4", self.host),
                     ("status", "--interval", "5", self.host), ("watch", "--demo", self.host)]:
            result = subprocess.run([str(BINARY), *args], capture_output=True, timeout=3)
            self.assertEqual(result.returncode, 64, result.stderr)
        self.assertEqual(Fixture.requests, [])
        result = subprocess.run([str(BINARY), self.host], capture_output=True, timeout=5)
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertNotIn(b"\x1b", result.stdout)
        self.assertIn(b"HashFleet status", result.stdout)


if __name__ == "__main__":
    parser = argparse.ArgumentParser()
    parser.add_argument("--binary", type=pathlib.Path, required=True)
    args = parser.parse_args()
    BINARY = args.binary.resolve()
    if not BINARY.is_file():
        parser.error(f"Build hashfleet first, missing executable: {BINARY}")
    unittest.main(argv=[__file__], verbosity=2)
