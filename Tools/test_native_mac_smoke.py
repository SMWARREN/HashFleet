"""Mock-only safety and acceptance-logic tests for explicit native AX helpers.

No test compiles a probe, launches an app, sends a real signal, or reads a saved
fleet. Stateful AX fixtures exercise the real checks, not a claimed GUI result.
"""
import contextlib
import importlib
import io
import json
from pathlib import Path
import signal
import subprocess
import sys
import tempfile
import unittest
from unittest.mock import Mock, call, patch


SCRIPTS = Path(__file__).resolve().parents[1] / "Scripts" / "tests"
with patch.object(sys, "path", [str(SCRIPTS), *sys.path]):
    navigation = importlib.import_module("native_mac_navigation_smoke")
    popup = importlib.import_module("native_mac_popup_smoke")


def node(identifier="", *, value="", title="", description="", role="AXButton", enabled=True):
    return {"id": identifier, "value": value, "title": title,
            "description": description, "role": role, "enabled": enabled}


def tuning_nodes():
    return [node("tuningSession.master.customInput", role="AXTextField", value="525"),
            node(navigation.VOLTAGE_INPUT, role="AXTextField", value="1150"),
            node("tuningSession.apply", enabled=False),
            node("tuningSession.writeRestriction", value="Demo writes are disabled"),
            node(navigation.BACK)]


class QuietTemporaryTest(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory()
        self.addCleanup(self.temporary.cleanup)
        self.work = Path(self.temporary.name)
        self.output = io.StringIO()
        self.redirect = contextlib.redirect_stdout(self.output)
        self.redirect.__enter__()
        self.addCleanup(self.redirect.__exit__, None, None, None)

    def probe(self, *, owned=False):
        return navigation.NativeMacProbe(self.work / "probe", 4242, self.work, owned=owned)


class NativeMacProbeTests(QuietTemporaryTest):
    def test_connect_owned_app_uses_bounded_compile_and_launch(self):
        app = self.work / "Fixture.app"
        app.mkdir()
        with patch.object(navigation.subprocess, "run") as compile_probe, \
                patch.object(navigation.subprocess, "check_output", return_value="4242\n") as launch:
            probe = navigation.NativeMacProbe.connect(app=app, work=self.work)
        compile_probe.assert_called_once_with(
            ["xcrun", "swiftc", str(SCRIPTS / "NativeMacNavigationProbe.swift"),
             "-o", str(self.work / "navigation-probe")], check=True, timeout=120)
        launch.assert_called_once_with(
            [str(self.work / "navigation-probe"), "launch", str(app)], text=True, timeout=30)
        self.assertEqual(probe.pid, 4242)
        self.assertTrue(probe.owned)
        self.assertEqual(probe.wait_seconds, 12)

    def test_connect_existing_pid_is_private_and_never_launches(self):
        with patch.object(navigation.subprocess, "run") as compile_probe, \
                patch.object(navigation.subprocess, "check_output") as launch:
            probe = navigation.NativeMacProbe.connect(
                pid=4242, work=self.work / "private", probe_name="popup-probe",
                snapshot_prefix="popup-ax", wait_seconds=15, private=True)
        self.assertEqual(probe.work.stat().st_mode & 0o777, 0o700)
        self.assertEqual(probe.snapshot_prefix, "popup-ax")
        self.assertEqual(probe.wait_seconds, 15)
        self.assertFalse(probe.owned)
        compile_probe.assert_called_once()
        launch.assert_not_called()

    def test_connect_requires_exactly_one_source(self):
        for arguments in ({}, {"app": self.work, "pid": 4242}):
            with self.subTest(arguments=arguments), \
                    patch.object(navigation.subprocess, "run") as compile_probe:
                with self.assertRaises(ValueError):
                    navigation.NativeMacProbe.connect(work=self.work, **arguments)
                compile_probe.assert_not_called()

    def test_invalid_or_system_pid_is_never_targeted(self):
        for pid in (-3, 0, 1):
            with self.subTest(pid=pid), patch.object(navigation.subprocess, "run"), \
                    patch.object(navigation.subprocess, "check_output") as external:
                with self.assertRaisesRegex(AssertionError, "PID"):
                    navigation.NativeMacProbe.connect(pid=pid, work=self.work)
                external.assert_not_called()

    def test_missing_app_and_failed_launch_do_not_return_a_probe(self):
        with patch.object(navigation.subprocess, "run"), \
                patch.object(navigation.subprocess, "check_output") as launch:
            with self.assertRaises(FileNotFoundError):
                navigation.NativeMacProbe.connect(app=self.work / "absent.app", work=self.work)
            launch.assert_not_called()
        app = self.work / "Fixture.app"
        app.mkdir()
        failure = subprocess.CalledProcessError(3, ["probe", "launch"])
        with patch.object(navigation.subprocess, "run"), \
                patch.object(navigation.subprocess, "check_output", side_effect=failure):
            with self.assertRaises(subprocess.CalledProcessError):
                navigation.NativeMacProbe.connect(app=app, work=self.work)

    def test_compile_failure_never_launches(self):
        with patch.object(navigation.subprocess, "run", side_effect=subprocess.TimeoutExpired("swiftc", 120)), \
                patch.object(navigation.subprocess, "check_output") as launch:
            with self.assertRaises(subprocess.TimeoutExpired):
                navigation.NativeMacProbe.connect(pid=4242, work=self.work)
            launch.assert_not_called()

    def test_launch_returning_system_pid_is_rejected(self):
        with patch.object(navigation.subprocess, "run"), \
                patch.object(navigation.subprocess, "check_output", return_value="1\n"):
            with self.assertRaisesRegex(AssertionError, "PID"):
                navigation.NativeMacProbe.connect(app=self.work, work=self.work)

    def test_call_is_scoped_to_exact_pid_and_has_hard_timeout(self):
        probe = self.probe()
        with patch.object(navigation.subprocess, "check_output", return_value="result") as external:
            self.assertEqual(probe.call("press", "safe-control"), "result")
        external.assert_called_once_with(
            [str(self.work / "probe"), "4242", "press", "safe-control"], text=True, timeout=8)

    def test_snapshot_persists_each_actual_response_sequentially(self):
        probe = self.probe()
        probe.snapshot_prefix = "popup-ax"
        fixtures = [[node("first")], [node("second")]]
        with patch.object(probe, "call", side_effect=[json.dumps(value) for value in fixtures]) as external:
            for expected in fixtures:
                self.assertEqual(probe.snapshot(), expected)
        self.assertEqual(external.call_args_list, [call("list"), call("list")])
        for index, expected in enumerate(fixtures, 1):
            self.assertEqual(json.loads((self.work / f"popup-ax-{index:03d}.json").read_text()), expected)

    def test_wait_for_polls_until_actual_predicate_matches(self):
        probe = self.probe()
        ready = [node("ready")]
        with patch.object(probe, "snapshot", side_effect=[[], ready]) as snapshot, \
                patch.object(navigation.time, "monotonic", side_effect=[0, 0, 1]), \
                patch.object(navigation.time, "sleep") as sleep:
            self.assertEqual(probe.wait_for(lambda nodes: bool(nodes)), ready)
        self.assertEqual(snapshot.call_count, 2)
        sleep.assert_called_once_with(0.2)

    def test_wait_for_reports_timeout_without_action(self):
        probe = self.probe()
        with patch.object(probe, "snapshot", return_value=[]), \
                patch.object(navigation.time, "monotonic", side_effect=[0, 0, 12]), \
                patch.object(navigation.time, "sleep"):
            with self.assertRaisesRegex(AssertionError, "Expected popup state"):
                probe.wait_for(bool)

    def test_wait_for_id_requires_exact_id_not_a_prefix(self):
        probe = self.probe()
        with patch.object(probe, "snapshot", side_effect=[[node("ready-child")], [node("ready")]]), \
                patch.object(navigation.time, "monotonic", side_effect=[0, 0, 1]), \
                patch.object(navigation.time, "sleep"):
            self.assertEqual(probe.wait_for_id("ready"), [node("ready")])
        with patch.object(navigation.time, "monotonic", side_effect=[0, 12]):
            with self.assertRaisesRegex(AssertionError, "Missing or unresponsive control: absent"):
                probe.wait_for_id("absent")

    def test_press_retries_only_proven_pre_action_lookup_failure(self):
        probe = self.probe()
        failure = subprocess.CalledProcessError(2, "probe")
        with patch.object(probe, "wait_for_id") as lookup, \
                patch.object(probe, "call", side_effect=[failure, failure, "pressed"]) as action, \
                patch.object(navigation.time, "sleep") as sleep:
            probe.press("safe-control")
        self.assertEqual(lookup.call_args_list, [call("safe-control")] * 3)
        self.assertEqual(action.call_args_list, [call("press", "safe-control")] * 3)
        self.assertEqual(sleep.call_args_list, [call(0.2)] * 2)

    def test_third_lookup_failure_is_not_retried(self):
        probe = self.probe()
        with patch.object(probe, "wait_for_id"), \
                patch.object(probe, "call", side_effect=subprocess.CalledProcessError(2, "probe")) as action, \
                patch.object(navigation.time, "sleep") as sleep:
            with self.assertRaises(subprocess.CalledProcessError):
                probe.press("safe-control")
        self.assertEqual(action.call_count, 3)
        self.assertEqual(sleep.call_count, 2)

    def test_action_failure_and_timeout_are_never_retried(self):
        errors = [subprocess.CalledProcessError(3, "probe"), subprocess.TimeoutExpired("probe", 8)]
        for error in errors:
            with self.subTest(error=type(error).__name__):
                probe = self.probe()
                with patch.object(probe, "wait_for_id"), \
                        patch.object(probe, "call", side_effect=error) as action, \
                        patch.object(navigation.time, "sleep") as sleep:
                    with self.assertRaises(type(error)):
                        probe.press("safe-control")
                action.assert_called_once()
                sleep.assert_not_called()

    def test_missing_control_never_attempts_press(self):
        probe = self.probe()
        with patch.object(probe, "wait_for_id", side_effect=AssertionError("missing")), \
                patch.object(probe, "call") as action:
            with self.assertRaises(AssertionError):
                probe.press("safe-control")
            action.assert_not_called()

    def test_close_owned_is_pid_scoped_and_idempotent(self):
        probe = self.probe(owned=True)
        with patch.object(navigation.os, "kill") as terminate:
            probe.close_owned()
            probe.close_owned()
        terminate.assert_called_once_with(4242, signal.SIGTERM)
        self.assertFalse(probe.owned)

    def test_close_existing_pid_never_sends_signal(self):
        with patch.object(navigation.os, "kill") as terminate:
            self.probe(owned=False).close_owned()
        terminate.assert_not_called()

    def test_owned_process_already_exited_is_harmless(self):
        probe = self.probe(owned=True)
        with patch.object(navigation.os, "kill", side_effect=ProcessLookupError) as terminate:
            probe.close_owned()
            probe.close_owned()
        terminate.assert_called_once()


class NavigationFixture(navigation.NativeMacProbe):
    """Small independent AX state machine. Only transport is replaced."""
    MINER = "demo-one"
    ROOT_MARKERS = {
        "overview": "dashboard.miner." + MINER, "network": "insights.poolNetworks",
        "energy": "energy.rateField", "achievements": "achievements.filter",
        "reports": "fleetReport.capture", "backup": "fleetBackup.export",
        "monitoring": navigation.MONITORING, "about": "about.hero",
    }

    def __init__(self, work):
        super().__init__(work / "fake-probe", 4242, work, owned=False, wait_seconds=0.01)
        self.state = "overview"
        self.actions = []

    def nodes(self):
        sidebar = [node(f"sidebar.destination.{name}") for name in self.ROOT_MARKERS]
        sidebar += [node(navigation.MINER_PREFIX + self.MINER, description="Little Supra fixture"),
                    node("sidebar.addMiner")]
        screens = {
            "detail": [node(navigation.QUICK_TUNING), node("detail.tuning.settings")],
            "tuning": tuning_nodes(), "add": [node(navigation.ADD_MINER), node(navigation.BACK)],
            "preferences": [node(navigation.PREFERENCES), node(navigation.BACK)],
        }
        if self.state in screens:
            return sidebar + screens[self.state]
        result = sidebar + [node(self.ROOT_MARKERS[self.state])]
        if self.state == "monitoring":
            result.append(node("monitoring.fleet"))
        return result

    def call(self, *arguments):
        if arguments == ("list",):
            return json.dumps(self.nodes())
        self.actions.append(arguments)
        action, identifier = arguments
        if action == "menu":
            self.state = "overview"
        elif identifier in ("dashboard.miner." + self.MINER, navigation.MINER_PREFIX + self.MINER,
                             navigation.BACK):
            self.state = "detail"
        elif identifier in (navigation.QUICK_TUNING, "detail.tuning.settings"):
            self.state = "tuning"
        elif identifier == "sidebar.addMiner":
            self.state = "add"
        elif identifier == "monitoring.fleet":
            self.state = "preferences"
        else:
            self.state = identifier.removeprefix("sidebar.destination.")
        return "fixture action"


class NavigationChecksTests(QuietTemporaryTest):
    def test_full_sidebar_flow_preserves_every_route_and_reselection(self):
        probe = NavigationFixture(self.work)
        navigation.NavigationChecks(probe).run(sidebar=True)
        self.assertEqual(probe.state, "overview")
        self.assertEqual(probe.actions.count(("press", navigation.BACK)), 6)
        self.assertEqual(probe.actions.count(("press", "detail.tuning.settings")), 2)
        self.assertEqual(probe.actions.count(("press", navigation.QUICK_TUNING)), 14)
        self.assertEqual(probe.actions.count(("press", "sidebar.addMiner")), 2)
        self.assertEqual(probe.actions.count(("press", "monitoring.fleet")), 1)
        for destination in NavigationFixture.ROOT_MARKERS:
            self.assertIn(("press", "sidebar.destination." + destination), probe.actions)
        self.assertGreater(probe.sequence, 50)

    def test_default_flow_does_not_add_optional_sidebar_checks(self):
        probe = NavigationFixture(self.work)
        navigation.NavigationChecks(probe).run()
        self.assertEqual(probe.actions.count(("press", navigation.BACK)), 6)
        self.assertNotIn(("press", "sidebar.addMiner"), probe.actions)
        self.assertNotIn(("press", "sidebar.destination.about"), probe.actions)

    def test_cold_workspace_restoration_uses_only_show_menu(self):
        probe = NavigationFixture(self.work)
        real_wait = probe.wait_for_id
        cold = True

        def wait(identifier):
            nonlocal cold
            if cold:
                cold = False
                raise AssertionError("cold")
            return real_wait(identifier)

        with patch.object(probe, "wait_for_id", side_effect=wait):
            self.assertEqual(navigation.NavigationChecks(probe).workspace_miner(), probe.MINER)
        self.assertEqual(probe.actions[0], ("menu", "Show Hash Fleet"))

    def test_missing_expected_demo_miner_fails_instead_of_selecting_another(self):
        probe = Mock()
        probe.snapshot.return_value = [node(navigation.MINER_PREFIX + "other", description="Another miner")]
        checks = navigation.NavigationChecks(probe)
        with self.assertRaises(StopIteration):
            checks.workspace_miner()

    def test_tuning_rejects_wrong_values_roles_disabled_fields_and_write_access(self):
        mutations = [
            ("tuningSession.master.customInput", "value", "526"),
            (navigation.VOLTAGE_INPUT, "value", "1151"),
            (navigation.VOLTAGE_INPUT, "role", "AXStaticText"),
            ("tuningSession.master.customInput", "enabled", False),
            (navigation.VOLTAGE_INPUT, "enabled", False),
            ("tuningSession.apply", "enabled", True),
            ("tuningSession.writeRestriction", "value", "Live"),
        ]
        for identifier, key, value in mutations:
            with self.subTest(identifier=identifier, key=key):
                nodes = tuning_nodes()
                next(current for current in nodes if current["id"] == identifier)[key] = value
                probe = Mock()
                probe.wait_for_id.return_value = nodes
                checks = navigation.NavigationChecks(probe)
                with self.assertRaises(AssertionError):
                    checks.verify_tuning()
                probe.press.assert_not_called()

    def test_root_rejects_each_leftover_child(self):
        for forbidden in (navigation.VOLTAGE_INPUT, navigation.ADD_MINER, navigation.BACK):
            with self.subTest(forbidden=forbidden):
                probe = Mock()
                probe.wait_for_id.return_value = [node("root"), node(forbidden)]
                checks = navigation.NavigationChecks(probe)
                with self.assertRaises(AssertionError):
                    checks.assert_root("root")

    def test_settings_reselection_rejects_preferences_that_reappear(self):
        probe = Mock()
        probe.wait_for_id.return_value = [node(navigation.MONITORING)]
        probe.snapshot.return_value = [node(navigation.PREFERENCES)]
        checks = navigation.NavigationChecks(probe)
        with self.assertRaises(AssertionError):
            checks.settings_reselection()


class PopupFixture(navigation.NativeMacProbe):
    def __init__(self, work, *, miners, notifications):
        super().__init__(work / "fake-probe", 4242, work, owned=False, wait_seconds=0.01)
        self.miners = miners
        self.notifications = notifications
        self.state = "closed"
        self.actions = []

    def nodes(self):
        nodes = [node(popup.STATUS_ITEM)]
        if self.state == "detail":
            return nodes + [node(navigation.QUICK_TUNING)]
        if self.state == "closed":
            return nodes
        nodes.append(node(popup.MENU_SECTION))
        if self.state == "Miners":
            if self.miners:
                nodes += [node(popup.MINER_PREFIX + str(index), value="Session best: fixture")
                          for index in range(self.miners)]
            else:
                nodes.append(node(value=popup.EMPTY_MINERS))
        else:
            nodes.append(node(title=popup.RECENT_NOTIFICATIONS))
            if self.notifications:
                nodes += [node(popup.NOTIFICATION_PREFIX + str(index))
                          for index in range(self.notifications)]
            else:
                nodes.append(node(description=popup.EMPTY_NOTIFICATIONS))
        return nodes

    def call(self, *arguments):
        if arguments == ("list",):
            return json.dumps(self.nodes())
        self.actions.append(arguments)
        action, identifier = arguments
        if action == "segment":
            self.state = identifier
        elif identifier == popup.STATUS_ITEM:
            self.state = "Miners" if self.state == "closed" else "closed"
        else:
            self.state = "detail"
        return "fixture action"


class PopupChecksTests(QuietTemporaryTest):
    def test_real_checks_switch_tabs_twice_for_empty_and_populated_fleets(self):
        cases = [(0, 0, "empty"), (2, 3, "populated"), (1, 0, None), (0, 1, None)]
        for miners, notifications, expected in cases:
            with self.subTest(miners=miners, notifications=notifications, expected=expected):
                probe = PopupFixture(self.work, miners=miners, notifications=notifications)
                popup.PopupChecks(probe, miners, expected).run()
                self.assertEqual(probe.actions.count(("segment", "Notifications")), 2)
                self.assertEqual(probe.actions.count(("segment", "Miners")), 2)
                self.assertEqual(probe.state, "detail" if miners else "closed")
                expected_presses = 1 if miners else 2
                self.assertEqual(probe.actions.count(("press", popup.STATUS_ITEM)), expected_presses)
                self.assertGreater(probe.sequence, 5)

    def test_text_matching_is_exact_in_each_accessibility_field(self):
        for field in ("value", "title", "description"):
            with self.subTest(field=field):
                self.assertTrue(popup.has_text([node(**{field: popup.RECENT_NOTIFICATIONS})],
                                               popup.RECENT_NOTIFICATIONS))
                self.assertFalse(popup.has_text([node(**{field: "prefix " + popup.RECENT_NOTIFICATIONS})],
                                                popup.RECENT_NOTIFICATIONS))
        self.assertFalse(popup.has_text([], "absent"))
        self.assertEqual(popup.ids([node("row.1"), node("other")], "row."), ["row.1"])

    def test_miners_reject_wrong_count_history_heading_and_missing_session_best(self):
        valid = [node(popup.MINER_PREFIX + "one", description="Session best: fixture")]
        variants = [[], valid + [node(popup.NOTIFICATION_PREFIX + "one")],
                    valid + [node(value=popup.RECENT_NOTIFICATIONS)], [node(popup.MINER_PREFIX + "one")]]
        checks = popup.PopupChecks(Mock(), 1)
        for index, nodes in enumerate(variants):
            with self.subTest(index=index), self.assertRaises(AssertionError):
                checks.check_miners(nodes)
        empty_checks = popup.PopupChecks(Mock(), 0)
        with self.assertRaises(AssertionError):
            empty_checks.check_miners([])

    def test_notifications_require_exclusive_rows_or_empty_message_and_no_miner_bleed(self):
        row = node(popup.NOTIFICATION_PREFIX + "one")
        empty = node(value=popup.EMPTY_NOTIFICATIONS)
        checks = popup.PopupChecks(Mock(), 0)
        for nodes in ([], [row, empty], [row, node(popup.MINER_PREFIX + "one")]):
            with self.subTest(nodes=nodes), self.assertRaises(AssertionError):
                checks.check_notifications(nodes)
        for expectation, nodes in (("empty", [row]), ("populated", [empty])):
            checks = popup.PopupChecks(Mock(), 0, expectation)
            with self.subTest(expectation=expectation), self.assertRaises(AssertionError):
                checks.check_notifications(nodes)

    def test_miner_click_requires_both_popup_dismissal_and_detail_marker(self):
        probe = Mock()
        predicates = []
        probe.wait_for.side_effect = lambda predicate: predicates.append(predicate)
        popup.PopupChecks(probe, 1).dismiss_popup([node(popup.MINER_PREFIX + "one")])
        predicate = predicates[0]
        self.assertFalse(predicate([node(popup.MENU_SECTION), node(navigation.QUICK_TUNING)]))
        self.assertFalse(predicate([]))
        self.assertTrue(predicate([node(navigation.QUICK_TUNING)]))
        # Matching is exact, not a broader prefix restriction.
        self.assertTrue(predicate([node(popup.MENU_SECTION + ".child"), node(navigation.QUICK_TUNING)]))
        probe.call.assert_called_once_with("press", popup.MINER_PREFIX + "one")


class SmokeEntryPointTests(QuietTemporaryTest):
    def test_navigation_success_and_failure_always_close_only_owned_probe(self):
        for fail in (False, True):
            with self.subTest(fail=fail):
                probe = self.probe(owned=True)
                error = AssertionError("fixture failure") if fail else None
                with patch.object(navigation.NativeMacProbe, "connect", return_value=probe) as connect, \
                        patch.object(navigation.NavigationChecks, "run", side_effect=error) as run, \
                        patch.object(navigation.os, "kill") as terminate:
                    arguments = ["--app", str(self.work), "--work-dir", str(self.work), "--sidebar"]
                    if fail:
                        with self.assertRaises(AssertionError):
                            navigation.main(arguments)
                    else:
                        navigation.main(arguments)
                connect.assert_called_once_with(app=self.work, work=self.work)
                run.assert_called_once_with(sidebar=True)
                terminate.assert_called_once_with(4242, signal.SIGTERM)

    def test_popup_existing_pid_is_never_terminated_on_success_or_failure(self):
        for fail in (False, True):
            with self.subTest(fail=fail):
                probe = self.probe(owned=False)
                error = AssertionError("fixture failure") if fail else None
                with patch.object(navigation.NativeMacProbe, "connect", return_value=probe) as connect, \
                        patch.object(popup.PopupChecks, "run", side_effect=error) as run, \
                        patch.object(navigation.os, "kill") as terminate:
                    arguments = ["--pid", "4242", "--work-dir", str(self.work),
                                 "--expect-miners", "2", "--expect-notifications", "populated"]
                    if fail:
                        with self.assertRaises(AssertionError):
                            popup.main(arguments)
                    else:
                        popup.main(arguments)
                connect.assert_called_once_with(app=None, pid=4242, work=self.work,
                                                probe_name="popup-probe", snapshot_prefix="popup-ax",
                                                wait_seconds=15, private=True)
                run.assert_called_once_with()
                terminate.assert_not_called()

    def test_popup_owned_demo_is_terminated_even_when_acceptance_fails(self):
        probe = self.probe(owned=True)
        arguments = ["--app", str(self.work), "--work-dir", str(self.work), "--expect-miners", "0"]
        with patch.object(navigation.NativeMacProbe, "connect", return_value=probe), \
                patch.object(popup.PopupChecks, "run", side_effect=AssertionError("fixture")), \
                patch.object(navigation.os, "kill") as terminate:
            with self.assertRaises(AssertionError):
                popup.main(arguments)
        terminate.assert_called_once_with(4242, signal.SIGTERM)

    def test_invalid_cli_source_and_notification_options_cannot_launch(self):
        common = ["--work-dir", str(self.work), "--expect-miners", "0"]
        invalid_popup = [common, common + ["--app", str(self.work), "--pid", "4242"],
                         common + ["--pid", "4242", "--expect-notifications", "unknown"]]
        navigation_arguments = ["--work-dir", str(self.work)]
        with patch.object(navigation.NativeMacProbe, "connect") as connect, contextlib.redirect_stderr(io.StringIO()):
            for arguments in invalid_popup:
                with self.subTest(arguments=arguments), self.assertRaises(SystemExit) as error:
                    popup.main(arguments)
                self.assertEqual(error.exception.code, 2)
            with self.assertRaises(SystemExit) as error:
                navigation.main(navigation_arguments)
            self.assertEqual(error.exception.code, 2)
        connect.assert_not_called()


if __name__ == "__main__":
    unittest.main()
