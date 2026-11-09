#!/usr/bin/env python3
"""Source-contract checks, not native-window hang acceptance.

The runtime CLI probe separately executes production bulk-add and completion logic.
--source-ref checks the same invariants against a preserved Git version without
editing it. No app, defaults, network, screen input or hardware is used.
"""
import argparse
from pathlib import Path
import subprocess
import unittest

ROOT = Path(__file__).resolve().parents[2]
SOURCE_REF = None


def source(path):
    if SOURCE_REF:
        return subprocess.check_output(
            ["git", "show", f"{SOURCE_REF}:{path}"], cwd=ROOT, text=True
        )
    return (ROOT / path).read_text()


def bulk_body():
    text = source("App/Features/Dashboard/AddMinerView.swift")
    return text.split("    func addAllDiscovered() {", 1)[1].split("    func startDiscovery()", 1)[0]


def for_platform(text, native_mac):
    # This bounded method contains only os(macOS) conditionals. Refuse unknown
    # conditions rather than silently treating a different branch as inactive.
    active = True
    stack = []
    selected = []
    for line in text.splitlines():
        directive = line.strip()
        if directive.startswith("#if "):
            if directive != "#if os(macOS)":
                raise AssertionError(f"Unsupported source conditional: {directive}")
            stack.append((active, native_mac))
            active = active and native_mac
        elif directive == "#else":
            parent, condition = stack[-1]
            active = parent and not condition
        elif directive == "#endif":
            parent, _ = stack.pop()
            active = parent
        elif active:
            selected.append(line)
    if stack:
        raise AssertionError("Unbalanced conditional in completion method")
    return "\n".join(selected)


class NativeAddMinerCompletionContract(unittest.TestCase):
    def test_native_success_does_not_broadcast_external_window_open(self):
        native = for_platform(bulk_body(), native_mac=True)
        self.assertNotIn("FleetSystemNavigation.request()", native)
        self.assertEqual(native.count("AddMinerMultiSelection.completeInWorkspace("), 1)

    def test_both_native_presenters_supply_the_completion_owner(self):
        dashboard = source("App/Features/Dashboard/DashboardView.swift")
        split = source("App/Features/Dashboard/FleetSplitView.swift")
        self.assertIn("AddMinerView(store: store, onBulkAddSuccess: { showingAddMiner = false })", dashboard)
        self.assertIn("AddMinerView(store: store, onBulkAddSuccess: completeBulkAdd)", split)

    def test_ios_completion_keeps_its_existing_dismiss_then_request(self):
        ios = for_platform(bulk_body(), native_mac=False)
        self.assertEqual(ios.count("dismiss()"), 1)
        self.assertEqual(ios.count("FleetSystemNavigation.request()"), 1)
        self.assertLess(ios.index("dismiss()"), ios.index("FleetSystemNavigation.request()"))
        self.assertNotIn("completeInWorkspace", ios)

    def test_partial_failures_still_keep_the_page_and_error(self):
        text = bulk_body()
        self.assertIn("if result.failures.isEmpty {", text)
        self.assertIn("addedAddresses = result.addedAddresses", text)
        error_branch = text.split("        } else {", 1)[1]
        self.assertIn("discoveryAddError = result.failures.joined", error_branch)
        self.assertNotIn("completeInWorkspace", error_branch)
        self.assertNotIn("FleetSystemNavigation.request()", error_branch)
        self.assertNotIn("dismiss()", error_branch)


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--source-ref", help="Read production files from this existing Git ref")
    args = parser.parse_args()
    SOURCE_REF = args.source_ref
    tests = unittest.defaultTestLoader.loadTestsFromTestCase(NativeAddMinerCompletionContract)
    result = unittest.TextTestRunner(verbosity=2).run(tests)
    raise SystemExit(0 if result.wasSuccessful() else 1)
