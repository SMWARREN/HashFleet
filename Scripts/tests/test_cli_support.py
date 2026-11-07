#!/usr/bin/env python3
"""Test the actual support command. Never contact PayPal or submit a payment.

Pass --expected-url after activating a reviewed checkout. Without it, the build
must be unconfigured and must fail closed with exit 69.
"""
import argparse
import pathlib
import subprocess
import unittest


class CLISupportTests(unittest.TestCase):
    def run_cli(self, *args):
        return subprocess.run(
            [str(BINARY), *args], capture_output=True, text=True, timeout=5
        )

    def test_support_is_documented(self):
        result = self.run_cli("--help")
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn("hashfleet support", result.stdout)
        self.assertIn("without contacting miners or opening a browser", result.stdout)

    def test_support_has_explicit_configured_or_unavailable_result(self):
        result = self.run_cli("support")
        if EXPECTED_URL:
            self.assertEqual(result.returncode, 0, result.stderr)
            self.assertEqual(result.stderr, "")
            self.assertIn(EXPECTED_URL, result.stdout.splitlines())
            self.assertIn("Optional developer tip", result.stdout)
            self.assertIn("No browser was opened", result.stdout)
        else:
            self.assertEqual(result.returncode, 69, result.stderr)
            self.assertEqual(result.stdout, "")
            self.assertIn("not configured in this build", result.stderr)

    def test_support_rejects_hosts_and_options_before_fleet_dispatch(self):
        for argument in ["127.0.0.1:1", "--open", "--json", "--demo", "support"]:
            with self.subTest(argument=argument):
                result = self.run_cli("support", argument)
                self.assertEqual(result.returncode, 64, result.stderr)
                self.assertIn("takes no options or miner hosts", result.stderr)
                self.assertEqual(result.stdout, "")

    def test_support_help_does_not_require_checkout(self):
        result = self.run_cli("support", "--help")
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn("hashfleet support", result.stdout)


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--binary", type=pathlib.Path, required=True)
    parser.add_argument("--expected-url")
    args = parser.parse_args()
    BINARY = args.binary.resolve(strict=True)
    EXPECTED_URL = args.expected_url
    unittest.main(argv=[__file__], verbosity=2)
