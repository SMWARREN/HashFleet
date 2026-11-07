#!/usr/bin/env python3
"""Exercise the actual native popup's two tabs using a PID-scoped AX probe.

Use --app for an isolated demo process that is terminated on completion, or
--pid to inspect an explicitly selected running app without terminating it.
Only display/navigation controls are pressed, never hardware or payment actions.
Requires Accessibility permission. Snapshots remain in the selected work directory.
"""
import argparse
from pathlib import Path

from native_mac_navigation_smoke import NativeMacProbe, QUICK_TUNING


MINER_PREFIX = "hashfleet.native.miner."
NOTIFICATION_PREFIX = "hashfleet.native.notification."
STATUS_ITEM = "hashfleet.native.status-item"
MENU_SECTION = "hashfleet.native.menu-section"
RECENT_NOTIFICATIONS = "Recent notifications"
EMPTY_NOTIFICATIONS = "No recent notifications."
EMPTY_MINERS = "Add a miner in the workspace to get started."


def ids(nodes, prefix):
    return [node["id"] for node in nodes if node["id"].startswith(prefix)]


def has_text(nodes, text):
    return any(text in (node["value"], node["title"], node["description"]) for node in nodes)


class PopupChecks:
    def __init__(self, probe, expect_miners, expect_notifications=None):
        self.probe = probe
        self.expect_miners = expect_miners
        self.expect_notifications = expect_notifications

    def check_miners(self, nodes):
        assert len(ids(nodes, MINER_PREFIX)) == self.expect_miners
        assert not ids(nodes, NOTIFICATION_PREFIX)
        assert not has_text(nodes, RECENT_NOTIFICATIONS)
        if self.expect_miners:
            miners = [node for node in nodes if node["id"].startswith(MINER_PREFIX)]
            assert all("Session best:" in (node["value"] + node["description"]) for node in miners)
        else:
            assert has_text(nodes, EMPTY_MINERS)

    def check_notifications(self, nodes):
        assert not ids(nodes, MINER_PREFIX)
        rows = ids(nodes, NOTIFICATION_PREFIX)
        empty = has_text(nodes, EMPTY_NOTIFICATIONS)
        assert bool(rows) != empty
        if self.expect_notifications == "empty":
            assert empty
        elif self.expect_notifications == "populated":
            assert rows
        print(f"PASS Notifications tab, {len(rows)} history rows, no miner cards")

    def open_popup(self):
        self.probe.wait_for_id(STATUS_ITEM)
        print(self.probe.call("press", STATUS_ITEM).strip())
        nodes = self.probe.wait_for_id(MENU_SECTION)
        self.check_miners(nodes)
        print("PASS default Miners tab, current cards and session bests, no history")

    def switch_tabs(self):
        for _ in range(2):
            print(self.probe.call("segment", "Notifications").strip())
            nodes = self.probe.wait_for(lambda current: has_text(current, RECENT_NOTIFICATIONS))
            self.check_notifications(nodes)
            print(self.probe.call("segment", "Miners").strip())
            nodes = self.probe.wait_for(lambda current: not has_text(current, RECENT_NOTIFICATIONS))
            self.check_miners(nodes)
        return nodes

    def dismiss_popup(self, nodes):
        if self.expect_miners:
            miner = ids(nodes, MINER_PREFIX)[0]
            print(self.probe.call("press", miner).strip())
            self.probe.wait_for(lambda current: MENU_SECTION not in [node["id"] for node in current]
                                and QUICK_TUNING in [node["id"] for node in current])
            print("PASS miner click dismisses popup and opens miner detail")
        else:
            print(self.probe.call("press", STATUS_ITEM).strip())

    def run(self):
        self.open_popup()
        nodes = self.switch_tabs()
        self.dismiss_popup(nodes)
        print("PASS native two-tab popup acceptance")


def main(argv=None):
    parser = argparse.ArgumentParser(description=__doc__)
    source = parser.add_mutually_exclusive_group(required=True)
    source.add_argument("--app", type=Path)
    source.add_argument("--pid", type=int)
    parser.add_argument("--work-dir", type=Path, required=True)
    parser.add_argument("--expect-miners", type=int, required=True)
    parser.add_argument("--expect-notifications", choices=["empty", "populated"])
    args = parser.parse_args(argv)
    probe = NativeMacProbe.connect(app=args.app, pid=args.pid, work=args.work_dir,
                                   probe_name="popup-probe", snapshot_prefix="popup-ax",
                                   wait_seconds=15, private=True)
    try:
        PopupChecks(probe, args.expect_miners, args.expect_notifications).run()
    finally:
        probe.close_owned()


if __name__ == "__main__":
    main()
