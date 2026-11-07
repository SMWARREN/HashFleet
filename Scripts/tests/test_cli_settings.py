#!/usr/bin/env python3
"""Exercise settings writes only against loopback firmware fixtures in real PTYs."""
import argparse
import copy
import http.server
import json
import pathlib
import secrets
import subprocess
import threading
import time
import unittest

import test_cli_dashboard as dashboard

# Random per-run fixture secrets prove redaction without embedding credentials.
FIXTURE_POOL_SECRET = "fixture-" + secrets.token_hex(8)


class SettingsFixture(http.server.BaseHTTPRequestHandler):
    payload = {}
    requests = []
    writes = []
    reads = 0
    preflight_change = {}
    fail_read = 0
    persist = True
    redirect = False
    patch_delay = 0
    corrupt_slot_readback = {}
    after_write_change = {}

    def reply(self, status, body):
        data = json.dumps(body).encode()
        self.send_response(status)
        if type(self).redirect and self.command == "PATCH":
            self.send_header("Location", f"http://127.0.0.1:{self.server.server_port}/unexpected-write")
        self.send_header("Content-Length", str(len(data)))
        self.end_headers()
        try:
            self.wfile.write(data)
        except (BrokenPipeError, ConnectionResetError):
            pass

    def do_GET(self):
        cls = type(self)
        cls.reads += 1
        cls.requests.append(("GET", self.path))
        if cls.reads == 2:
            cls.payload.update(cls.preflight_change)
        if cls.fail_read and cls.reads >= cls.fail_read:
            self.reply(503, {"error": "private-token-from-firmware"})
        else:
            reported = copy.deepcopy(cls.payload)
            for slot in reported.get("pools", []) if isinstance(reported.get("pools"), list) else []:
                if isinstance(slot, dict) and "stratumPassword" in slot:
                    slot["stratumPassword"] = "*****"
            self.reply(200, reported)

    def do_PATCH(self):
        cls = type(self)
        payload = json.loads(self.rfile.read(int(self.headers["Content-Length"])))
        cls.requests.append(("PATCH", self.path))
        cls.writes.append((self.server.server_port, payload))
        time.sleep(cls.patch_delay)
        if cls.persist and not cls.redirect:
            # Firmware replaces supplied slots by persistent ID; omitted slots are untouched.
            cls.payload.update({key: value for key, value in payload.items() if key != "pools"})
            if "pools" in payload:
                slots = {slot["id"]: slot for slot in cls.payload.get("pools", [])}
                for entry in payload["pools"]:
                    slot = copy.deepcopy(entry)
                    if slot.get("stratumPassword") == "*****":
                        slot["stratumPassword"] = slots.get(slot["id"], {}).get("stratumPassword", "x")
                    slot.update(cls.corrupt_slot_readback)
                    slots[slot["id"]] = slot
                cls.payload["pools"] = list(slots.values())
            cls.payload.update(cls.after_write_change)
        self.reply(302 if cls.redirect else 200, {"ok": True, "error": "private-token-from-firmware"})

    def log_message(self, *_args):
        # Silence per-request stderr logging from the fixture HTTP server.
        pass


class SettingsTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.servers = [http.server.ThreadingHTTPServer(("127.0.0.1", 0), SettingsFixture) for _ in range(2)]
        cls.threads = [threading.Thread(target=server.serve_forever, daemon=True) for server in cls.servers]
        for thread in cls.threads:
            thread.start()
        cls.host = f"127.0.0.1:{cls.servers[0].server_port}"

    @classmethod
    def tearDownClass(cls):
        for server in cls.servers:
            server.shutdown()
            server.server_close()
        for thread in cls.threads:
            thread.join(timeout=3)

    def setUp(self):
        SettingsFixture.payload = {
            "hostname": "gamma", "hashRate": 1000, "frequency": 500, "coreVoltage": 1100,
            "autofanspeed": 1, "manualFanSpeed": 50, "minFanSpeed": 25, "temptarget": 60,
            "statsFrequency": 5, "rotation": 0, "invertscreen": 0, "displayTimeout": -1,
            "stratumURL": "pool.example", "stratumPort": 3333, "stratumUser": "wallet.worker",
            "stratumPassword": FIXTURE_POOL_SECRET, "boardVersion": "600",
        }
        SettingsFixture.requests = []
        SettingsFixture.writes = []
        SettingsFixture.reads = 0
        SettingsFixture.preflight_change = {}
        SettingsFixture.fail_read = 0
        SettingsFixture.persist = True
        SettingsFixture.redirect = False
        SettingsFixture.patch_delay = 0
        SettingsFixture.corrupt_slot_readback = {}
        SettingsFixture.after_write_change = {}

    def configure_slots(self, ids=(5, 2)):
        slots = [{
            "id": slot, "stratumURL": f"pool-{slot}.example", "stratumPort": 3333 + slot,
            "stratumUser": f"wallet.worker{slot}", "stratumPassword": f"{FIXTURE_POOL_SECRET}-{slot}",
            "stratumProtocol": "SV1", "stratumSuggestedDifficulty": 1234.5,
            "stratumExtranonceSubscribe": True, "stratumTLS": 2,
            "stratumCert": "-----BEGIN CERTIFICATE-----\nexisting-public-certificate\n-----END CERTIFICATE-----",
            "stratumDecodeCoinbase": False, "stratumV2ChannelType": "extended",
            "stratumV2AuthorityPubkey": "existing-authority", "stratumV2RequireAuth": True,
        } for slot in ids]
        SettingsFixture.payload.update(pools=slots, primaryPoolIndex=min(ids), secondaryPoolIndex=max(ids))
        return slots

    def terminal(self, *args, **kwargs):
        terminal = dashboard.Terminal(*(args or ("settings", self.host)), **kwargs)
        def close():
            try:
                if terminal.process.poll() is None:
                    terminal.send(b"\x03")
                    deadline = time.monotonic() + 3
                    # A full dashboard frame can exceed the PTY buffer on return from settings.
                    # Continue consuming output so the child can read Ctrl+C and restore the TTY.
                    while terminal.process.poll() is None and time.monotonic() < deadline:
                        terminal.drain()
                    terminal.process.wait(timeout=0.1)
            finally:
                terminal.close()
        self.addCleanup(close)
        terminal.wait_for("HASH FLEET / SETTINGS" if not args or args[0] == "settings" else "HASH FLEET")
        return terminal

    def edit(self, terminal, value, category=1, index=0):
        terminal.send(str(category).encode() + b"j" * index)
        offset = terminal.send(b"\r")
        terminal.wait_for("Ctrl+U clear", after=offset)
        terminal.send(b"\x15" + value.encode())
        terminal.drain(0.1)
        return terminal.send(b"\r")

    def stage(self, terminal, value, category=1, index=0, count=1):
        offset = self.edit(terminal, value, category, index)
        terminal.wait_for(f"{count} pending changes", after=offset)

    def review(self, terminal):
        offset = terminal.send(b"r")
        terminal.wait_for("REVIEW", after=offset)
        self.assertEqual(SettingsFixture.writes, [])

    def apply(self, terminal, expected="SAVED & VERIFIED"):
        offset = terminal.send(b"APPLY\r")
        terminal.wait_for(expected, after=offset)
        terminal.drain(0.1)

    def test_hostname_is_staged_then_written_once_and_verified(self):
        terminal = self.terminal(colors=True)
        self.stage(terminal, "gamma-desk")
        self.assertEqual(SettingsFixture.requests, [("GET", "/api/system/info")])
        self.review(terminal)
        self.assertIn("gamma → gamma-desk", terminal.frame())
        terminal.send(b"APPLY")
        terminal.drain()
        self.assertEqual(SettingsFixture.writes, [])
        offset = terminal.send(b"\r")
        terminal.wait_for("SAVED & VERIFIED", after=offset)
        self.assertEqual(SettingsFixture.writes, [(self.servers[0].server_port, {"hostname": "gamma-desk"})])
        self.assertEqual(SettingsFixture.requests, [("GET", "/api/system/info"), ("GET", "/api/system/info"),
                                                    ("PATCH", "/api/system"), ("GET", "/api/system/info")])
        self.assertNotIn(FIXTURE_POOL_SECRET.encode(), terminal.output)

    def test_cancel_undo_and_paste_never_apply(self):
        terminal = self.terminal()
        self.stage(terminal, "gamma-desk")
        terminal.send(b"\x1b[200~rAPPLY\r\x1b[201~")
        terminal.drain()
        self.assertEqual(SettingsFixture.writes, [])
        terminal.send(b"u")
        terminal.wait_for("0 pending changes")
        self.stage(terminal, "gamma-other")
        self.review(terminal)
        terminal.send(b"\x1b[200~APPLY\x1b[201~\r")
        terminal.drain()
        self.assertEqual(SettingsFixture.writes, [])
        terminal.send(b"\x1b")
        terminal.wait_for("pending changes")
        terminal.drain(0.25)
        offset = terminal.send(b"\x1b")
        terminal.wait_for("Discard", after=offset)
        terminal.send(b"y")
        terminal.wait_for("e settings")
        self.assertEqual(SettingsFixture.writes, [])

    def test_multi_field_cooling_sends_explicit_values_only(self):
        terminal = self.terminal()
        self.stage(terminal, "off", category=2)
        self.stage(terminal, "65", category=2, index=1, count=2)
        self.review(terminal)
        self.apply(terminal)
        self.assertEqual(SettingsFixture.writes[0][1], {"autofanspeed": 0, "manualFanSpeed": 65})
        self.assertEqual(SettingsFixture.payload["temptarget"], 60)

    def test_invalid_values_and_board_ceiling_block_requests(self):
        SettingsFixture.payload["boardVersion"] = "601a"
        terminal = self.terminal()
        offset = self.edit(terminal, "1e3", category=3)
        terminal.wait_for("finite decimal", after=offset)
        offset = terminal.send(b"\x1b")
        terminal.wait_for("0 pending changes", after=offset)
        self.stage(terminal, "1151", category=3, index=1)
        offset = terminal.send(b"r")
        terminal.wait_for("1150 mV", after=offset)
        self.assertEqual(SettingsFixture.writes, [])
        self.assertEqual(len(SettingsFixture.requests), 1)

    def test_preflight_hardware_policy_and_changed_fields_block_writes(self):
        for preflight, value, category, index, expected in [
            ({"boardVersion": "601a"}, "1200", 3, 1, "1150 mV"),
            ({"hostname": "another-client"}, "gamma-desk", 1, 0, "changed since"),
        ]:
            with self.subTest(preflight=preflight):
                self.setUp()
                SettingsFixture.preflight_change = preflight
                terminal = self.terminal()
                self.stage(terminal, value, category, index)
                self.review(terminal)
                self.apply(terminal, expected="CHECK RESULT")
                self.assertIn(expected, terminal.frame())
                self.assertEqual(SettingsFixture.writes, [])
                terminal.send(b"\x03")
                terminal.process.wait(timeout=3)

    def test_preflight_failure_and_post_write_failure_are_distinct(self):
        for failure_at, writes, expected in [(2, 0, "Nothing was sent"), (3, 1, "Request accepted")]:
            with self.subTest(failure_at=failure_at):
                self.setUp()
                SettingsFixture.fail_read = failure_at
                terminal = self.terminal()
                self.stage(terminal, "gamma-desk")
                self.review(terminal)
                self.apply(terminal, expected="CHECK RESULT")
                self.assertIn(expected, terminal.frame())
                self.assertEqual(len(SettingsFixture.writes), writes)
                self.assertNotIn("private-token", terminal.frame())
                terminal.send(b"\x03")
                terminal.process.wait(timeout=3)

    def test_ignored_settings_are_not_reported_as_verified_or_retried(self):
        SettingsFixture.persist = False
        terminal = self.terminal()
        self.stage(terminal, "gamma-desk")
        self.review(terminal)
        self.apply(terminal, expected="CHECK RESULT")
        self.assertIn("do not match", terminal.frame())
        terminal.drain(0.4)
        self.assertEqual(len(SettingsFixture.writes), 1)
        self.assertNotIn("SAVED & VERIFIED", terminal.frame())

    def test_redirected_write_is_not_followed(self):
        SettingsFixture.redirect = True
        terminal = self.terminal()
        self.stage(terminal, "gamma-desk")
        self.review(terminal)
        self.apply(terminal, expected="CHECK RESULT")
        self.assertEqual(len(SettingsFixture.writes), 1)
        self.assertTrue(all(path != "/unexpected-write" for _, path in SettingsFixture.requests))
        self.assertNotIn("private-token", terminal.frame())

    def test_legacy_pool_preserves_password_and_empty_slots_do_not_guess(self):
        terminal = self.terminal()
        self.stage(terminal, "newpool.example", category=5)
        self.review(terminal)
        self.apply(terminal)
        self.assertEqual(SettingsFixture.writes[0][1], {"stratumURL": "newpool.example"})
        self.assertNotIn(FIXTURE_POOL_SECRET, terminal.frame())
        terminal.send(b"\x03")
        terminal.process.wait(timeout=3)
        self.setUp()
        SettingsFixture.payload["pools"] = []
        terminal = self.terminal()
        terminal.send(b"5")
        terminal.wait_for("No configured pool slots")
        terminal.send(b"\rAPPLY\r")
        terminal.drain()
        self.assertEqual(SettingsFixture.writes, [])

    def test_modern_pool_retains_full_slot_and_sends_only_edited_id(self):
        slots = copy.deepcopy(self.configure_slots())
        terminal = self.terminal(colors=True)
        self.stage(terminal, "newpool.example", category=5)
        self.stage(terminal, "525.5", category=3, count=2)
        self.review(terminal)
        self.assertIn("Slot 2", terminal.frame())
        self.apply(terminal)
        request = SettingsFixture.writes[0][1]
        self.assertEqual(set(request), {"pools", "frequency"})
        self.assertEqual(request["frequency"], 525.5)
        expected = next(slot for slot in slots if slot["id"] == 2)
        expected.update(stratumURL="newpool.example", stratumPassword="*****")
        self.assertEqual(request["pools"], [expected])
        self.assertEqual(next(slot for slot in SettingsFixture.payload["pools"] if slot["id"] == 5), slots[0])
        self.assertNotIn(FIXTURE_POOL_SECRET.encode(), terminal.output)
        self.assertNotIn(b"existing-public-certificate", terminal.output)

    def test_slot_selection_and_roles_use_ids_not_array_positions(self):
        self.configure_slots()
        terminal = self.terminal()
        terminal.send(b"5]")
        terminal.wait_for("Slot 5")
        self.stage(terminal, "backup-new.example", category=5)
        self.stage(terminal, "5", category=5, index=5, count=2)
        self.stage(terminal, "2", category=5, index=6, count=3)
        self.review(terminal)
        self.apply(terminal)
        request = SettingsFixture.writes[0][1]
        self.assertEqual(request["pools"][0]["id"], 5)
        self.assertEqual(request["primaryPoolIndex"], 5)
        self.assertEqual(request["secondaryPoolIndex"], 2)

    def test_role_only_readback_checks_the_selected_pool_identity(self):
        slots = copy.deepcopy(self.configure_slots())
        next(slot for slot in slots if slot["id"] == 5)["stratumURL"] = "changed-after-apply.example"
        SettingsFixture.after_write_change = {"pools": slots}
        terminal = self.terminal()
        self.stage(terminal, "5", category=5, index=5)
        self.review(terminal)
        self.apply(terminal, expected="CHECK RESULT")
        self.assertEqual(SettingsFixture.writes[0][1], {"primaryPoolIndex": 5})
        self.assertIn("do not match", terminal.frame())

    def test_incomplete_unknown_and_invalid_pool_configuration_blocks_before_write(self):
        for mutate in (
            lambda slot: slot.pop("stratumCert"),
            lambda slot: slot.update(futureTLSOption=True),
            lambda slot: slot.update(stratumTLS="2"),
        ):
            with self.subTest(mutate=mutate):
                self.setUp()
                slots = self.configure_slots()
                mutate(next(slot for slot in slots if slot["id"] == 2))
                terminal = self.terminal()
                self.stage(terminal, "newpool.example", category=5)
                offset = terminal.send(b"r")
                terminal.drain(0.3)
                self.assertNotIn("REVIEW", terminal.output[offset:].decode())
                self.assertIn("Slot 2", terminal.frame())
                self.assertEqual(SettingsFixture.requests, [("GET", "/api/system/info")])
                self.assertEqual(SettingsFixture.writes, [])
                terminal.send(b"\x03")
                terminal.process.wait(timeout=3)

    def test_slot_baseline_conflict_and_preserved_field_readback_are_checked(self):
        for conflict in (True, False):
            with self.subTest(conflict=conflict):
                self.setUp()
                slots = copy.deepcopy(self.configure_slots())
                if conflict:
                    next(slot for slot in slots if slot["id"] == 2)["stratumCert"] = "changed elsewhere"
                    SettingsFixture.preflight_change = {"pools": slots}
                else:
                    SettingsFixture.corrupt_slot_readback = {"stratumTLS": 0}
                terminal = self.terminal()
                self.stage(terminal, "newpool.example", category=5)
                self.review(terminal)
                self.apply(terminal, expected="CHECK RESULT")
                self.assertIn("changed since" if conflict else "do not match", terminal.frame())
                self.assertEqual(len(SettingsFixture.writes), 0 if conflict else 1)
                terminal.send(b"\x03")
                terminal.process.wait(timeout=3)

    def test_password_replace_and_clear_are_masked_and_not_claimed_verified(self):
        for modern, password in ((True, "replacement-secret"), (False, "")):
            with self.subTest(modern=modern):
                self.setUp()
                if modern:
                    self.configure_slots()
                terminal = self.terminal()
                self.stage(terminal, password, category=5, index=3 if modern else 6)
                self.review(terminal)
                self.assertIn("(replace)" if password else "Clear password", terminal.frame())
                self.apply(terminal, expected="CHECK RESULT")
                self.assertIn("hides passwords", terminal.frame())
                request = SettingsFixture.writes[0][1]
                written = request["pools"][0]["stratumPassword"] if modern else request["stratumPassword"]
                self.assertEqual(written, password)
                self.assertNotIn(b"replacement-secret", terminal.output)
                self.assertNotIn(FIXTURE_POOL_SECRET.encode(), terminal.output)
                terminal.send(b"\x03")
                terminal.process.wait(timeout=3)

    def test_invalid_slot_ids_and_unconfigured_roles_never_write(self):
        for invalid in (True, "2", 2.5, 5):
            with self.subTest(invalid=invalid):
                self.setUp()
                slots = self.configure_slots()
                slots[1]["id"] = invalid
                terminal = self.terminal()
                terminal.send(b"5")
                terminal.wait_for("invalid or duplicated")
                terminal.send(b"\rAPPLY\r")
                terminal.drain()
                self.assertEqual(SettingsFixture.writes, [])
                terminal.send(b"\x03")
                terminal.process.wait(timeout=3)
        self.setUp()
        self.configure_slots()
        terminal = self.terminal()
        self.stage(terminal, "7", category=5, index=5)
        offset = terminal.send(b"r")
        terminal.wait_for("must refer to a configured slot", after=offset)
        self.assertEqual(SettingsFixture.writes, [])

    def test_large_preserved_certificates_are_not_truncated_or_split(self):
        slots = self.configure_slots(ids=(0, 2, 4, 6))
        for slot in slots:
            slot["stratumCert"] = "c" * 3000
        terminal = self.terminal()
        for index in range(4):
            self.stage(terminal, f"new-{index}.example", category=5, count=index + 1)
            terminal.send(b"]")
        offset = terminal.send(b"r")
        terminal.wait_for("10 KiB", after=offset)
        self.assertEqual(SettingsFixture.requests, [("GET", "/api/system/info")])
        self.assertEqual(SettingsFixture.writes, [])

    def test_pool_fields_and_review_fit_narrow_panes(self):
        self.configure_slots()
        terminal = self.terminal(columns=54, rows=12)
        self.stage(terminal, "newpool.example", category=5)
        self.assertIn("Slot 2", terminal.frame())
        self.assertIn("Esc back", terminal.frame())
        self.review(terminal)
        terminal.send(b"j" * 30)
        terminal.drain()
        self.assertTrue(all(len(line) <= 53 for line in terminal.frame().splitlines()))
        self.assertLessEqual(len(terminal.frame().splitlines()), 12)
        self.assertEqual(SettingsFixture.writes, [])

    def test_demo_offline_and_noninteractive_settings_cannot_write(self):
        terminal = self.terminal("settings", "--demo")
        terminal.wait_for("DEMO")
        terminal.send(b"\rtest\rrAPPLY\r")
        terminal.drain()
        self.assertEqual(SettingsFixture.requests, [])
        terminal.send(b"\x03")
        terminal.process.wait(timeout=3)
        SettingsFixture.fail_read = 1
        terminal = self.terminal()
        terminal.wait_for("Miner offline")
        terminal.send(b"\rtest\rrAPPLY\r")
        terminal.drain()
        self.assertEqual(SettingsFixture.writes, [])
        for args in [("settings", self.host), ("settings", self.host, self.host), ("settings", "--json", self.host)]:
            result = subprocess.run([str(dashboard.BINARY), *args], capture_output=True, timeout=3)
            self.assertEqual(result.returncode, 64)

    def test_only_selected_miner_is_written(self):
        hosts = sorted(f"127.0.0.1:{server.server_port}" for server in self.servers)
        terminal = self.terminal("watch", *hosts)
        terminal.wait_for("2/2")
        terminal.send(b"je")
        terminal.wait_for("HASH FLEET / SETTINGS")
        self.assertIn(hosts[1], terminal.frame())
        self.stage(terminal, "gamma-selected")
        self.review(terminal)
        self.apply(terminal)
        self.assertEqual(SettingsFixture.writes[0][0], int(hosts[1].split(":")[1]))

    def test_narrow_editor_and_split_arrows_restore_terminal(self):
        terminal = self.terminal(columns=54, rows=12)
        terminal.send(b"\x1b[")
        terminal.drain(0.1)
        terminal.send(b"B")
        terminal.drain()
        offset = self.edit(terminal, "30", category=1, index=1)
        terminal.wait_for("1 pending changes", after=offset)
        self.assertTrue(all(len(line) <= 53 for line in terminal.frame().splitlines()))
        self.assertLessEqual(len(terminal.frame().splitlines()), 12)
        self.assertIn("Esc back", terminal.frame())
        terminal.send(b"\x03")
        self.assertEqual(terminal.process.wait(timeout=3), 0)
        terminal.drain()
        self.assertIn(b"\x1b[?2004l", terminal.output)
        self.assertIn(b"\x1b[?25h\x1b[?1049l", terminal.output)
        self.assertEqual(SettingsFixture.writes, [])


if __name__ == "__main__":
    parser = argparse.ArgumentParser()
    parser.add_argument("--binary", type=pathlib.Path, required=True)
    args = parser.parse_args()
    dashboard.BINARY = args.binary.resolve()
    unittest.main(argv=[__file__], verbosity=2)
