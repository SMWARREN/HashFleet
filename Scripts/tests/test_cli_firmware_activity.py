#!/usr/bin/env python3
"""Executable CLI acceptance using only a loopback miner fixture, never a real fleet."""
import argparse
import copy
import http.server
import json
import pathlib
import subprocess
import threading
import unittest


class FixtureHandler(http.server.BaseHTTPRequestHandler):
    payload = {}
    status = 200
    methods = []

    def do_GET(self):
        type(self).methods.append(("GET", self.path))
        body = json.dumps(type(self).payload).encode()
        self.send_response(type(self).status)
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)

    def do_POST(self):
        type(self).methods.append(("POST", self.path))
        self.send_error(405)

    def log_message(self, *_args):
        # Silence per-request stderr logging from the fixture HTTP server.
        pass


class CLIActivityTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.server = http.server.ThreadingHTTPServer(("127.0.0.1", 0), FixtureHandler)
        cls.thread = threading.Thread(target=cls.server.serve_forever, daemon=True)
        cls.thread.start()
        cls.host = f"127.0.0.1:{cls.server.server_port}"

    @classmethod
    def tearDownClass(cls):
        cls.server.shutdown()
        cls.server.server_close()
        cls.thread.join(timeout=3)

    def setUp(self):
        FixtureHandler.payload = {
            "hashRate": 1000, "temp": 50, "power": 20, "bestDiff": "8M", "bestSessionDiff": "2M",
            "expectedHashrate": 1000,
            "hashrateMonitor": {"asics": [{"domains": [240, 250, 260, 250]}]},
            "isUsingFallbackStratum": 0, "primaryPoolIndex": 5, "secondaryPoolIndex": 2,
            "pools": [{"id": 2, "stratumTLS": 0, "stratumProtocol": "SV1"},
                      {"id": 5, "stratumTLS": 2, "stratumProtocol": "SV1"}],
            "stratumUser": "fixture-secret-wallet",
            "primaryPoolError": "Denied fixture-secret-wallet\n\u001b[31m",
            "poolBanner": "Welcome to the fixture pool",
        }
        FixtureHandler.status = 200
        FixtureHandler.methods = []

    def run_cli(self, *args, expected=0):
        result = subprocess.run([str(BINARY), *args], text=True, capture_output=True, timeout=20)
        self.assertEqual(result.returncode, expected, result.stderr)
        return result.stdout

    def test_help_documents_new_read_only_output(self):
        text = self.run_cli("--help")
        self.assertIn("--details", text)
        self.assertIn("session-best", text)
        self.assertEqual(FixtureHandler.methods, [])

    def test_text_and_details_include_distinct_records_and_safe_diagnostics(self):
        text = self.run_cli("status", "--details", self.host)
        self.assertIn("BEST (ALL)", text)
        self.assertIn("BEST (SESSION)", text)
        self.assertRegex(text, r"8(?:[.,]0+)?M\s+2(?:[.,]0+)?M\s+ONLINE")
        self.assertNotIn("Transport:", text)
        self.assertNotIn("Primary pool error:", text)
        self.assertIn("Pool notice: Denied [redacted]", text)
        self.assertIn("ASIC 1 domain 4", text)
        self.assertIn("nominal 250", text)
        self.assertNotIn("fixture-secret-wallet", text)
        self.assertNotIn("\u001b", text)
        self.assertEqual(FixtureHandler.methods, [("GET", "/api/system/info")])

    def test_old_firmware_never_substitutes_all_time_for_missing_session(self):
        del FixtureHandler.payload["bestSessionDiff"]
        del FixtureHandler.payload["hashrateMonitor"]
        text = self.run_cli("status", "--details", self.host)
        self.assertRegex(text, r"8(?:[.,]0+)?M\s+--\s+ONLINE")
        self.assertNotIn("ASIC 1 domain", text)

    def test_numeric_zero_and_boolean_are_not_confused(self):
        FixtureHandler.payload["bestSessionDiff"] = 0
        text = self.run_cli("status", self.host)
        self.assertRegex(text, r"8(?:[.,]0+)?M\s+0(?:[.,]0+)?\s+ONLINE")
        FixtureHandler.payload["bestSessionDiff"] = True
        text = self.run_cli("status", self.host)
        self.assertRegex(text, r"8(?:[.,]0+)?M\s+--\s+ONLINE")

    def test_json_preserves_existing_raw_schema_and_unknown_fields(self):
        FixtureHandler.payload["newFirmwareField"] = {"nested": [1, 2]}
        payload = copy.deepcopy(FixtureHandler.payload)
        result = json.loads(self.run_cli("status", "--json", self.host))
        self.assertEqual(result["miners"][0]["info"], payload)
        self.assertNotIn("hashrateDomains", result["miners"][0])
        self.assertNotIn("transportLabel", result["miners"][0])

    def test_invalid_options_are_usage_errors_without_requests(self):
        for args in [("--details", "--details"), ("--json", "--details"), ("--unknown",)]:
            self.run_cli("status", *args, self.host, expected=64)
        self.assertEqual(FixtureHandler.methods, [])

    def test_offline_exit_status_remains_failure(self):
        FixtureHandler.status = 503
        FixtureHandler.payload = {"error": "Fixture unavailable"}
        text = self.run_cli("status", "--details", self.host, expected=1)
        self.assertIn("OFFLINE", text)
        self.assertNotIn("ASIC 1 domain", text)

    def test_useful_metrics_preserve_zero_and_missing_values(self):
        FixtureHandler.payload.update({"power": 0, "sharesAccepted": 100, "sharesRejected": 0,
                                       "frequency": 575, "voltage": 5120, "wifiRSSI": -57})
        text = self.run_cli("status", "--details", self.host)
        self.assertRegex(text, r"Efficiency\s+0(?:[.,]0)? J/TH")
        self.assertRegex(text, r"Rejected share rate\s+0(?:[.,]0+)? %")
        self.assertRegex(text, r"Input voltage\s+5[.,]12 V")
        self.assertRegex(text, r"Measured clock\s+Not reported")
        self.assertRegex(text, r"Wi-Fi signal\s+-57 dBm")
        FixtureHandler.payload["sharesRejected"] = True
        text = self.run_cli("status", "--details", self.host)
        self.assertRegex(text, r"Rejected share rate\s+Not reported")

    def test_healthy_pool_has_no_empty_error_or_transport_fields(self):
        del FixtureHandler.payload["primaryPoolError"]
        FixtureHandler.payload["poolBanner"] = ""
        text = self.run_cli("status", "--details", self.host)
        self.assertNotIn("Pool notice", text)
        self.assertNotIn("Primary pool error", text)
        self.assertNotIn("Transport", text)

    def test_active_pool_uses_reported_slot_id_and_never_guesses(self):
        FixtureHandler.payload["pools"] = [
            {"id": 2, "url": "bch.solofury.com"}, {"id": 5, "url": "solo.ckpool.org"}]
        FixtureHandler.payload["activePoolIndex"] = 2
        text = self.run_cli("status", "--details", self.host)
        pool = text.split("POOL STATUS", 1)[1].split("CONFIGURED POOLS", 1)[0]
        self.assertIn("bch.solofury.com", pool)
        self.assertIn("BCH", pool)
        self.assertNotIn("solo.ckpool.org", pool)
        self.assertIn("Using the backup pool", pool)
        for invalid in [9, True, "2"]:
            FixtureHandler.payload["activePoolIndex"] = invalid
            text = self.run_cli("status", "--details", self.host)
            pool = text.split("POOL STATUS", 1)[1].split("CONFIGURED POOLS", 1)[0]
            self.assertIn("has not identified its active pool", pool)
            self.assertNotIn("Active pool reported", pool)

    def test_reported_health_is_clear_without_leaking_fault_text(self):
        FixtureHandler.payload.update({"miningPaused": True, "overheat_mode": True,
                                       "hardware_fault": "fixture-secret-wallet"})
        text = self.run_cli("status", "--details", self.host)
        self.assertIn("Overheat protection active", text)
        self.assertIn("reports a hardware fault", text)
        self.assertNotIn("fixture-secret-wallet", text)


if __name__ == "__main__":
    parser = argparse.ArgumentParser()
    parser.add_argument("--binary", type=pathlib.Path, default=pathlib.Path(".build/debug/hashfleet"))
    args = parser.parse_args()
    BINARY = args.binary.resolve()
    if not BINARY.is_file():
        parser.error(f"Build hashfleet first, missing executable: {BINARY}")
    unittest.main(argv=[__file__], verbosity=2)
