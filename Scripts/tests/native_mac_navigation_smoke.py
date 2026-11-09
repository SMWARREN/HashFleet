#!/usr/bin/env python3
"""Native macOS route acceptance, run explicitly with Accessibility permission.

Compiles an external AX probe, launches only an isolated --ui-testing --demo app,
checks tuning entrances and optional sidebar routes, then terminates only that
owned PID. No controls are applied. Every external call has a hard timeout.
"""
import argparse
import json
import os
from pathlib import Path
import signal
import subprocess
import time


OVERVIEW = "sidebar.destination.overview"
MINER_PREFIX = "sidebar.destination.miner-"
QUICK_TUNING = "detail.quick.tuning"
VOLTAGE_INPUT = "tuningSession.voltage.customInput"
BACK = "chevron.backward"
ADD_MINER = "addMiner.address"
MONITORING = "monitoring.notifications"
PREFERENCES = "preferences.sortOption"


class NativeMacProbe:
    """PID-scoped, bounded AX calls shared by the explicit smoke entry points."""

    def __init__(self, probe, pid, work, *, owned, snapshot_prefix="ax", wait_seconds=12):
        self.probe = probe
        self.pid = pid
        self.work = work
        self.owned = owned
        self.snapshot_prefix = snapshot_prefix
        self.wait_seconds = wait_seconds
        self.sequence = 0

    @classmethod
    def connect(cls, *, app=None, pid=None, work, probe_name="navigation-probe",
                snapshot_prefix="ax", wait_seconds=12, private=False):
        if (app is None) == (pid is None):
            raise ValueError("Choose exactly one app or running PID")
        owned = app is not None
        if owned:
            app = app.resolve(strict=True)
        else:
            assert pid > 1, "Refusing an invalid or system PID"
        work = work.resolve()
        work.mkdir(parents=True, exist_ok=True)
        if private:
            os.chmod(work, 0o700)
        probe = work / probe_name
        subprocess.run([
            "xcrun", "swiftc", str(Path(__file__).with_name("NativeMacNavigationProbe.swift")),
            "-o", str(probe)
        ], check=True, timeout=120)
        if owned:
            pid = int(subprocess.check_output(
                [str(probe), "launch", str(app)], text=True, timeout=30
            ).strip())
        assert pid > 1, "Refusing an invalid or system PID"
        return cls(probe, pid, work, owned=owned, snapshot_prefix=snapshot_prefix,
                   wait_seconds=wait_seconds)

    def call(self, *arguments):
        return subprocess.check_output(
            [str(self.probe), str(self.pid), *arguments], text=True, timeout=8
        )

    def snapshot(self):
        nodes = json.loads(self.call("list"))
        self.sequence += 1
        path = self.work / f"{self.snapshot_prefix}-{self.sequence:03d}.json"
        path.write_text(json.dumps(nodes, indent=2) + "\n")
        return nodes

    def wait_for(self, predicate, message="Expected popup state not reached"):
        deadline = time.monotonic() + self.wait_seconds
        while time.monotonic() < deadline:
            nodes = self.snapshot()
            if predicate(nodes):
                return nodes
            time.sleep(0.2)
        raise AssertionError(message)

    def wait_for_id(self, identifier):
        return self.wait_for(lambda nodes: any(node["id"] == identifier for node in nodes),
                             f"Missing or unresponsive control: {identifier}")

    def press(self, identifier):
        for attempt in range(3):
            self.wait_for_id(identifier)
            try:
                print(self.call("press", identifier).strip(), flush=True)
                return
            except subprocess.CalledProcessError as error:
                # Only code 2 proves that lookup failed before an action occurred.
                # Never retry an AXPress failure or timeout, which could act twice.
                if error.returncode != 2 or attempt == 2:
                    raise
                time.sleep(0.2)

    def close_owned(self):
        if not self.owned:
            return
        self.owned = False
        try:
            os.kill(self.pid, signal.SIGTERM)
        except ProcessLookupError:
            pass


class NavigationChecks:
    def __init__(self, probe):
        self.probe = probe

    def verify_tuning(self):
        nodes = self.probe.wait_for_id(VOLTAGE_INPUT)
        by_id = {node["id"]: node for node in nodes}
        for identifier, value in (("master", "525"), ("voltage", "1150")):
            field = by_id[f"tuningSession.{identifier}.customInput"]
            assert field["role"] == "AXTextField" and field["value"] == value, field
            assert field["enabled"], field
        assert not by_id["tuningSession.apply"]["enabled"], "Demo must not apply hardware changes"
        assert "Demo" in by_id["tuningSession.writeRestriction"]["value"]
        self.probe.press(BACK)
        self.probe.wait_for_id(QUICK_TUNING)

    def workspace_miner(self):
        try:
            self.probe.wait_for_id(OVERVIEW)
        except AssertionError:
            print(self.probe.call("menu", "Show Hash Fleet").strip(), flush=True)
            self.probe.wait_for_id(OVERVIEW)
        self.probe.press(OVERVIEW)
        nodes = self.probe.snapshot()
        return next(node["id"].removeprefix(MINER_PREFIX) for node in nodes
                    if node["id"].startswith(MINER_PREFIX) and "Little Supra" in node["description"])

    def tuning_round_trips(self, miner):
        for entry in (f"dashboard.miner.{miner}", MINER_PREFIX + miner):
            self.probe.press(entry)
            for route in ("detail.tuning.settings", QUICK_TUNING, QUICK_TUNING):
                self.probe.press(route)
                self.verify_tuning()
                print(f"PASS {entry.split('.')[0]} -> {route} -> inputs -> Back", flush=True)
            self.probe.press(OVERVIEW)
            self.probe.wait_for_id(f"dashboard.miner.{miner}")
        print("PASS: six tuning round trips, both entrances and parent routes, demo safety intact", flush=True)

    def assert_root(self, identifier):
        identifiers = {node["id"] for node in self.probe.wait_for_id(identifier)}
        assert VOLTAGE_INPUT not in identifiers, "Tuning must close"
        assert ADD_MINER not in identifiers, "Add miner must close"
        assert BACK not in identifiers, "Root must not retain a child Back action"

    def same_miner_reselection(self, miner):
        root = MINER_PREFIX + miner
        self.probe.press(root)
        for _ in range(2):
            self.probe.press(QUICK_TUNING)
            self.probe.wait_for_id(VOLTAGE_INPUT)
            self.probe.press(root)
            self.assert_root(QUICK_TUNING)
        print("PASS same-miner reselection closes tuning twice", flush=True)

    def sidebar_destinations(self, miner):
        roots = {
            "overview": f"dashboard.miner.{miner}",
            "network": "insights.poolNetworks",
            "energy": "energy.rateField",
            "achievements": "achievements.filter",
            "reports": "fleetReport.capture",
            "backup": "fleetBackup.export",
            "monitoring": MONITORING,
            "about": "about.hero",
        }
        for destination, marker in roots.items():
            self.probe.press(MINER_PREFIX + miner)
            self.probe.press(QUICK_TUNING)
            self.probe.wait_for_id(VOLTAGE_INPUT)
            self.probe.press(f"sidebar.destination.{destination}")
            self.assert_root(marker)
            print(f"PASS tuning -> sidebar {destination} root", flush=True)

    def settings_reselection(self):
        self.probe.press("sidebar.destination.monitoring")
        self.probe.press("monitoring.fleet")
        self.probe.wait_for_id(PREFERENCES)
        self.probe.press("sidebar.destination.monitoring")
        self.assert_root(MONITORING)
        assert not any(node["id"] == PREFERENCES for node in self.probe.snapshot())
        print("PASS settings reselection closes nested Preferences", flush=True)

    def add_miner_reopening(self, miner):
        self.probe.press(OVERVIEW)
        for _ in range(2):
            self.probe.press("sidebar.addMiner")
            self.probe.wait_for_id(ADD_MINER)
            self.probe.press(OVERVIEW)
            self.assert_root(f"dashboard.miner.{miner}")
        print("PASS sidebar closes Add miner and it can reopen", flush=True)

    def run(self, *, sidebar=False):
        miner = self.workspace_miner()
        self.tuning_round_trips(miner)
        if sidebar:
            self.same_miner_reselection(miner)
            self.sidebar_destinations(miner)
            self.settings_reselection()
            self.add_miner_reopening(miner)


def main(argv=None):
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--app", required=True, type=Path)
    parser.add_argument("--work-dir", required=True, type=Path)
    parser.add_argument("--sidebar", action="store_true", help="Also verify sidebar replacement and reselection")
    args = parser.parse_args(argv)
    probe = NativeMacProbe.connect(app=args.app, work=args.work_dir)
    print(f"Launched isolated demo PID {probe.pid}", flush=True)
    try:
        NavigationChecks(probe).run(sidebar=args.sidebar)
    finally:
        probe.close_owned()


if __name__ == "__main__":
    main()
