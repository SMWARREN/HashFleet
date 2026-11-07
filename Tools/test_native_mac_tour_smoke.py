"""Offline safety, boundary, ownership, and acceptance-logic tests for Mac tour smoke.

The tour tests never compile a probe, launch an application, execute xcodebuild,
send signals to real processes, or conduct network scans. The separate Swift
serialization regression executes an isolated Swift snippet. A stateful AX fixture
simulates the 17-step FleetGuidedDemoSteps guided tour sequence, target frames,
interactive spotlight actions, transitions, and failure sample preservation.
"""
import contextlib
import io
import json
import math
import os
from pathlib import Path
import resource
import signal
import subprocess
import sys
import tempfile
import time
import unittest
from unittest.mock import MagicMock, Mock, call, patch

SCRIPTS = Path(__file__).resolve().parents[1] / "Scripts" / "tests"
if str(SCRIPTS) not in sys.path:
    sys.path.insert(0, str(SCRIPTS))

import native_mac_navigation_smoke as nav_smoke
import native_mac_tour_smoke as tour_smoke


def ax_node(
    identifier: str = "",
    *,
    value: str = "",
    title: str = "",
    description: str = "",
    role: str = "AXButton",
    enabled: bool = True,
    frame: dict = None,
) -> dict:
    node = {
        "id": identifier,
        "value": value,
        "title": title,
        "description": description,
        "role": role,
        "enabled": enabled,
    }
    if frame is not None:
        node["frame"] = frame
    return node


class QuietTestBase(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory()
        self.addCleanup(self.temporary.cleanup)
        self.work = Path(self.temporary.name)
        self.output = io.StringIO()
        self.redirect = contextlib.redirect_stdout(self.output)
        self.redirect.__enter__()
        self.addCleanup(self.redirect.__exit__, None, None, None)


class TourStepSpecificationTests(unittest.TestCase):
    def test_tour_steps_count_and_exact_order(self):
        self.assertEqual(len(tour_smoke.TOUR_STEPS), 17)
        expected_ids = [
            "overview", "history", "openMiner", "cooling", "openCoins",
            "chooseDGB", "coinResult", "openPreferences", "appearance",
            "openEnergy", "energy", "openReports", "previewReport",
            "pdf", "openAlerts", "alerts", "complete",
        ]
        actual_ids = [s.id for s in tour_smoke.TOUR_STEPS]
        self.assertEqual(actual_ids, expected_ids)

    def test_screens_and_targets_match_fleet_guided_demo_steps(self):
        by_id = {s.id: s for s in tour_smoke.TOUR_STEPS}
        self.assertEqual(by_id["overview"].screen, "fleet")
        self.assertEqual(by_id["overview"].target, "guide.hero")
        self.assertEqual(by_id["cooling"].screen, "miner")
        self.assertEqual(by_id["cooling"].target, "guide.cooling")
        self.assertEqual(by_id["openCoins"].screen, "fleet")
        self.assertEqual(by_id["openCoins"].target, "guide.coinSelection")
        self.assertEqual(by_id["pdf"].screen, "pdf")
        self.assertEqual(by_id["pdf"].target, "guide.pdf")

    def test_interactive_steps_have_tap_titles(self):
        interactive_ids = {"openMiner", "openCoins", "chooseDGB", "openPreferences", "openEnergy", "openReports", "previewReport", "openAlerts"}
        for s in tour_smoke.TOUR_STEPS:
            if s.id in interactive_ids:
                self.assertIsNotNone(s.tap_title, f"Step {s.id} should have tap_title")
            else:
                self.assertIsNone(s.tap_title, f"Step {s.id} should not have tap_title")

    def test_discriminating_substrings_present_for_all_steps(self):
        for s in tour_smoke.TOUR_STEPS:
            self.assertGreater(len(s.instruction_substr), 5, f"Step {s.id} should have meaningful substring")

    def test_all_17_steps_match_live_fleet_guided_demo_steps_swift_source(self):
        source_path = Path(__file__).resolve().parents[1] / "App" / "Features" / "Tour" / "FleetGuidedDemoSteps.swift"
        self.assertTrue(source_path.exists(), f"Source file must exist at {source_path}")
        source_text = source_path.read_text(encoding="utf-8")

        for step in tour_smoke.TOUR_STEPS:
            with self.subTest(step=step.id):
                self.assertIn(f'id: "{step.id}"', source_text, f"Step ID {step.id} missing in source")
                self.assertIn(f'title: "{step.title}"', source_text, f"Step title {step.title} missing in source")
                self.assertIn(f'target: "{step.target}"', source_text, f"Step target {step.target} missing in source")
                self.assertIn(step.instruction_substr, source_text, f"Instruction substring '{step.instruction_substr}' missing in source")
                if step.tap_title is not None:
                    self.assertIn(f'tapTitle: "{step.tap_title}"', source_text, f"Tap title {step.tap_title} missing in source")


class TourProbeConnectionTests(QuietTestBase):
    def test_connect_tour_owned_app_uses_launch_tour_probe_mode(self):
        app = self.work / "Hash Fleet.app"
        app.mkdir()
        with patch.object(tour_smoke.subprocess, "run") as compile_probe, \
             patch.object(tour_smoke.subprocess, "check_output", side_effect=["5555\n", '[{"id":"tour.view"}]']) as launch_tour, \
             patch.object(tour_smoke, "get_process_identity", return_value=("/bin/app", "Fri Nov 6 10:48:13 2026")):
            probe = tour_smoke.NativeMacTourProbe.connect_tour(app=app, work=self.work)

        compile_probe.assert_called_once_with(
            ["xcrun", "swiftc", str(SCRIPTS / "NativeMacNavigationProbe.swift"),
             "-o", str(self.work / "tour-probe")], check=True, timeout=120)
        self.assertIn(
            call([str(self.work / "tour-probe"), "launch-tour", str(app.resolve())], text=True, timeout=30),
            launch_tour.call_args_list,
        )
        self.assertEqual(probe.pid, 5555)
        self.assertTrue(probe.owned)
        self.assertEqual(probe.app_path, app.resolve())
        self.assertEqual(probe.expected_lstart, "Fri Nov 6 10:48:13 2026")

    def test_connect_tour_attached_pid_is_private_and_never_launches(self):
        with patch.object(tour_smoke.subprocess, "run") as compile_probe, \
             patch.object(tour_smoke.subprocess, "check_output") as launch, \
             patch.object(tour_smoke, "get_process_identity", return_value=("/bin/app", "Fri Nov 6 10:48:13 2026")):
            probe = tour_smoke.NativeMacTourProbe.connect_tour(
                pid=7777, work=self.work / "private", probe_name="custom-tour",
                wait_seconds=15, private=True)

        self.assertEqual(probe.work.stat().st_mode & 0o777, 0o700)
        self.assertEqual(probe.pid, 7777)
        self.assertFalse(probe.owned)
        self.assertIsNone(probe.app_path)
        compile_probe.assert_called_once()
        launch.assert_not_called()

    def test_connect_tour_requires_exactly_one_target(self):
        for args in ({}, {"app": self.work, "pid": 1234}):
            with self.subTest(args=args), patch.object(tour_smoke.subprocess, "run"):
                with self.assertRaises(ValueError):
                    tour_smoke.NativeMacTourProbe.connect_tour(work=self.work, **args)

    def test_invalid_or_system_pids_rejected(self):
        for pid in (-5, 0, 1):
            with self.subTest(pid=pid), patch.object(tour_smoke.subprocess, "run"):
                with self.assertRaisesRegex(AssertionError, "PID"):
                    tour_smoke.NativeMacTourProbe.connect_tour(pid=pid, work=self.work)

    def test_missing_app_raises_file_not_found(self):
        with patch.object(tour_smoke.subprocess, "run"):
            with self.assertRaises(FileNotFoundError):
                tour_smoke.NativeMacTourProbe.connect_tour(app=self.work / "NonExistent.app", work=self.work)


class ProcessIdentityAndCleanupTests(QuietTestBase):
    def test_get_process_identity_uses_two_calls_and_preserves_spaces_in_path(self):
        space_path = "/Applications/Hash Fleet.app/Contents/MacOS/Hash Fleet"
        start_time = "Fri Nov 6 10:48:13 2026"
        with patch.object(tour_smoke.os, "kill"), \
             patch.object(tour_smoke.subprocess, "check_output", side_effect=[f"{space_path}\n", f"{start_time}\n"]) as mock_ps:
            comm, lstart = tour_smoke.get_process_identity(4242)

        self.assertEqual(comm, space_path)
        self.assertEqual(lstart, start_time)
        self.assertEqual(
            mock_ps.call_args_list,
            [
                call(["ps", "-p", "4242", "-o", "comm="], text=True, timeout=5),
                call(["ps", "-p", "4242", "-o", "lstart="], text=True, timeout=5),
            ]
        )

    def test_verify_pid_identity_valid_and_matching(self):
        app = Path("/Applications/Hash Fleet.app")
        with patch.object(tour_smoke, "get_process_identity", return_value=("/Applications/Hash Fleet.app/Contents/MacOS/Hash Fleet", "Fri Nov 6 10:48:13 2026")):
            valid, msg = tour_smoke.verify_pid_identity(8888, app, "Fri Nov 6 10:48:13 2026")
        self.assertTrue(valid)

    def test_verify_pid_identity_fails_closed_on_lookup_error(self):
        app = Path("/Applications/Hash Fleet.app")
        with patch.object(tour_smoke, "get_process_identity", return_value=(None, None)):
            valid, msg = tour_smoke.verify_pid_identity(8888, app, "Fri Nov 6 10:48:13 2026")
        self.assertFalse(valid)
        self.assertIn("failed", msg)

    def test_verify_pid_identity_detects_pid_reuse_via_lstart(self):
        app = Path("/Applications/Hash Fleet.app")
        with patch.object(tour_smoke, "get_process_identity", return_value=("/Applications/Hash Fleet.app/Contents/MacOS/Hash Fleet", "Fri Nov 6 11:05:00 2026")):
            valid, msg = tour_smoke.verify_pid_identity(8888, app, "Fri Nov 6 10:48:13 2026")
        self.assertFalse(valid)
        self.assertIn("start time mismatch (PID reuse detected)", msg)

    def test_verify_pid_identity_mismatched_comm_rejected(self):
        app = Path("/Applications/Hash Fleet.app")
        with patch.object(tour_smoke, "get_process_identity", return_value=("/usr/bin/python3", "Fri Nov 6 10:48:13 2026")):
            valid, msg = tour_smoke.verify_pid_identity(8888, app, "Fri Nov 6 10:48:13 2026")
        self.assertFalse(valid)
        self.assertIn("does not match", msg)

    def test_verify_pid_identity_dead_pid_rejected(self):
        with patch.object(tour_smoke.os, "kill", side_effect=ProcessLookupError):
            valid, msg = tour_smoke.verify_pid_identity(8888)
        self.assertFalse(valid)

    def test_close_owned_terminates_only_when_identity_verified(self):
        app = Path("/Applications/Hash Fleet.app")
        probe = tour_smoke.NativeMacTourProbe(
            self.work / "probe", 8888, self.work, owned=True, app_path=app, expected_lstart="Fri Nov 6 10:48:13 2026")
        with patch.object(tour_smoke, "verify_pid_identity", return_value=(True, "Hash Fleet")), \
             patch.object(tour_smoke.os, "kill") as mock_kill:
            probe.close_owned()
            probe.close_owned()  # Idempotent second call
        mock_kill.assert_called_once_with(8888, signal.SIGTERM)
        self.assertFalse(probe.owned)

    def test_close_owned_refuses_kill_when_identity_unverified(self):
        app = Path("/Applications/Hash Fleet.app")
        probe = tour_smoke.NativeMacTourProbe(
            self.work / "probe", 8888, self.work, owned=True, app_path=app, expected_lstart="Fri Nov 6 10:48:13 2026")
        with patch.object(tour_smoke, "verify_pid_identity", return_value=(False, "mismatch")), \
             patch.object(tour_smoke.os, "kill") as mock_kill:
            probe.close_owned()
        mock_kill.assert_not_called()
        self.assertFalse(probe.owned)

    def test_close_attached_pid_never_kills_or_signals(self):
        probe = tour_smoke.NativeMacTourProbe(self.work / "probe", 8888, self.work, owned=False)
        with patch.object(tour_smoke, "verify_pid_identity") as mock_verify, \
             patch.object(tour_smoke.os, "kill") as mock_kill:
            probe.close_owned()
        mock_verify.assert_not_called()
        mock_kill.assert_not_called()

    def test_close_owned_handles_process_lookup_error(self):
        app = Path("/Applications/Hash Fleet.app")
        probe = tour_smoke.NativeMacTourProbe(
            self.work / "probe", 8888, self.work, owned=True, app_path=app, expected_lstart="time")
        with patch.object(tour_smoke, "verify_pid_identity", return_value=(True, "Hash Fleet")), \
             patch.object(tour_smoke.os, "kill", side_effect=ProcessLookupError):
            probe.close_owned()
        self.assertFalse(probe.owned)


class SamplePreservationTests(QuietTestBase):
    def test_sample_classification_at_cap_and_process_exit_boundaries(self):
        sample = self.work / "classification.sample.txt"
        for size, code, captured, partial, truncated in (
            (7, 0, True, False, False),
            (8, 0, False, True, True),
            (0, 0, False, False, False),
            (7, 1, False, True, False),
            (7, -9, False, True, True),
            (7, 128 + getattr(signal, "SIGXFSZ", 25), False, True, True),
            (7, 25, False, True, True),
            (7, None, False, True, False),
        ):
            with self.subTest(size=size, code=code):
                sample.write_bytes(b"X" * size)
                metadata = {"sample_captured": False, "sample_partial": False}
                proc = subprocess.CompletedProcess([], code) if code is not None else None
                tour_smoke._record_sample_result(sample, proc, metadata, 8)
                self.assertEqual(metadata["sample_size_bytes"], size)
                self.assertEqual(metadata["sample_captured"], captured)
                self.assertEqual(metadata["sample_partial"], partial)
                self.assertEqual(metadata.get("sample_truncated", False), truncated)

    def test_missing_sample_preserves_invocation_error(self):
        metadata = {"sample_captured": False, "sample_error": "Sampler timed out after 10s"}
        original = metadata.copy()
        tour_smoke._record_sample_result(self.work / "missing.sample.txt", None, metadata, 8)
        self.assertEqual(metadata, original)

    def test_preserve_failure_sample_success_and_metadata(self):
        sampler = self.work / "sample"
        sampler.write_text("#!/bin/sh\necho 'sample data' > \"$7\"\n")
        sampler.chmod(0o755)

        def run_sampler(*args, **kwargs):
            file_arg = args[0][6]
            Path(file_arg).write_text("Call graph sample output\n")
            self.assertIn("preexec_fn", kwargs)
            with patch.object(tour_smoke.resource, "setrlimit") as set_limit:
                kwargs["preexec_fn"]()
            set_limit.assert_called_once_with(
                resource.RLIMIT_FSIZE, (tour_smoke.SAMPLE_MAX_BYTES, tour_smoke.SAMPLE_MAX_BYTES)
            )
            return subprocess.CompletedProcess(args[0], 0)

        with patch.object(tour_smoke, "verify_pid_identity", return_value=(True, "Hash Fleet")), \
             patch.object(tour_smoke.subprocess, "run", side_effect=run_sampler):
            sample_path = tour_smoke.preserve_failure_sample(
                4242, self.work, "Stall detected in tour", sampler_binary=str(sampler))

        self.assertIsNotNone(sample_path)
        self.assertTrue(sample_path.exists())
        self.assertIn("Call graph sample output", sample_path.read_text())

        meta_files = list(self.work.glob("tour-failure-*.json"))
        self.assertEqual(len(meta_files), 1)
        meta = json.loads(meta_files[0].read_text())
        self.assertEqual(meta["pid"], 4242)
        self.assertEqual(meta["reason"], "Stall detected in tour")
        self.assertTrue(meta["identity_verified"])
        self.assertTrue(meta["sample_captured"])
        self.assertFalse(meta["sample_partial"])

    def test_preserve_failure_sample_enforces_rlimit_cap_during_execution(self):
        sampler = self.work / "sample"
        sampler.write_text("#!/bin/sh\n")
        sampler.chmod(0o755)

        def write_large_sample(*args, **kwargs):
            file_arg = args[0][6]
            # Simulate exceeding cap
            with open(file_arg, "wb") as f:
                f.write(b"X" * tour_smoke.SAMPLE_MAX_BYTES)
            # Process was terminated by signal (SIGXFSZ)
            return subprocess.CompletedProcess(args[0], -25)

        with patch.object(tour_smoke, "verify_pid_identity", return_value=(True, "Hash Fleet")), \
             patch.object(tour_smoke.subprocess, "run", side_effect=write_large_sample):
            sample_path = tour_smoke.preserve_failure_sample(
                4242, self.work, "Size cap test", sampler_binary=str(sampler))

        # Must not claim successful complete capture
        self.assertIsNone(sample_path)
        meta = json.loads(list(self.work.glob("tour-failure-*.json"))[0].read_text())
        self.assertTrue(meta["sample_truncated"])
        self.assertTrue(meta["sample_partial"])
        self.assertFalse(meta["sample_captured"])
        self.assertIn("exceeded max byte limit", meta["sample_error"])

    def test_preserve_failure_sample_zero_bytes_does_not_claim_captured(self):
        sampler = self.work / "sample"
        sampler.write_text("#!/bin/sh\n")
        sampler.chmod(0o755)

        def empty_sample(*args, **kwargs):
            file_arg = args[0][6]
            Path(file_arg).write_bytes(b"")
            return subprocess.CompletedProcess(args[0], 0)

        with patch.object(tour_smoke, "verify_pid_identity", return_value=(True, "Hash Fleet")), \
             patch.object(tour_smoke.subprocess, "run", side_effect=empty_sample):
            sample_path = tour_smoke.preserve_failure_sample(
                4242, self.work, "Empty sample test", sampler_binary=str(sampler))

        self.assertIsNone(sample_path)
        meta = json.loads(list(self.work.glob("tour-failure-*.json"))[0].read_text())
        self.assertFalse(meta["sample_captured"])
        self.assertIn("0 bytes", meta["sample_error"])

    def test_preserve_failure_sample_dead_pid_writes_metadata_only(self):
        with patch.object(tour_smoke, "verify_pid_identity", return_value=(False, "Dead process")), \
             patch.object(tour_smoke.subprocess, "run") as mock_run:
            sample_path = tour_smoke.preserve_failure_sample(4242, self.work, "Dead process test")
        self.assertIsNone(sample_path)
        mock_run.assert_not_called()
        meta = json.loads(list(self.work.glob("tour-failure-*.json"))[0].read_text())
        self.assertFalse(meta["identity_verified"])
        self.assertFalse(meta["sample_captured"])

    def test_preserve_failure_sample_handles_sampler_timeout(self):
        sampler = self.work / "sample"
        sampler.write_text("#!/bin/sh\n")
        sampler.chmod(0o755)

        with patch.object(tour_smoke, "verify_pid_identity", return_value=(True, "Hash Fleet")), \
             patch.object(tour_smoke.subprocess, "run", side_effect=subprocess.TimeoutExpired("sample", 10)):
            sample_path = tour_smoke.preserve_failure_sample(
                4242, self.work, "Timeout test", sampler_binary=str(sampler))

        self.assertIsNone(sample_path)
        meta = json.loads(list(self.work.glob("tour-failure-*.json"))[0].read_text())
        self.assertIn("timed out", meta["sample_error"])

    def test_preserve_failure_sample_missing_sampler_binary(self):
        with patch.object(tour_smoke, "verify_pid_identity", return_value=(True, "Hash Fleet")):
            sample_path = tour_smoke.preserve_failure_sample(
                4242, self.work, "Missing binary test", sampler_binary=str(self.work / "nonexistent-sampler"))
        self.assertIsNone(sample_path)
        meta = json.loads(list(self.work.glob("tour-failure-*.json"))[0].read_text())
        self.assertIn("not found", meta["sample_error"])

    def test_preserve_failure_sample_rlimit_failure_fails_closed_without_sampling(self):
        sampler = self.work / "sample"
        sampler.write_text("#!/bin/sh\n")
        sampler.chmod(0o755)

        with patch.object(tour_smoke, "verify_pid_identity", return_value=(True, "Hash Fleet")), \
             patch.object(tour_smoke.subprocess, "run", side_effect=OSError("Failed to set RLIMIT_FSIZE")):
            sample_path = tour_smoke.preserve_failure_sample(
                4242, self.work, "RLIMIT fail test", sampler_binary=str(sampler))

        self.assertIsNone(sample_path)
        meta = json.loads(list(self.work.glob("tour-failure-*.json"))[0].read_text())
        self.assertFalse(meta["sample_captured"])
        self.assertIn("RLIMIT", meta["sample_error"])


class StepAssertionAndFrameTests(unittest.TestCase):
    def setUp(self):
        self.probe = Mock()
        self.checks = tour_smoke.TourChecks(self.probe, dwell_seconds=0.0)

    def test_assert_step_state_valid(self):
        step = tour_smoke.TOUR_STEPS[0]
        nodes = [
            ax_node("tour.step.overview", title="Meet your fleet"),
            ax_node("tour.progress", value="1/17"),
            ax_node("tour.instruction", value="adds up their hashrate and power"),
            ax_node("tour.back", enabled=False),
            ax_node("tour.highlight", frame={"x": 50.0, "y": 60.0, "width": 400.0, "height": 200.0}),
        ]
        self.checks.assert_step_state(0, step, nodes)

    def test_assert_step_state_accepts_title_in_axheading_description(self):
        step = tour_smoke.TOUR_STEPS[0]
        nodes = [
            # Title is empty, but description contains the heading
            ax_node("tour.step.overview", title="", description="Meet your fleet"),
            ax_node("tour.progress", value="1/17"),
            ax_node("tour.instruction", value="adds up their hashrate and power"),
            ax_node("tour.back", enabled=False),
            ax_node("tour.highlight", frame={"x": 50.0, "y": 60.0, "width": 400.0, "height": 200.0}),
        ]
        self.checks.assert_step_state(0, step, nodes)

    def test_assert_step_state_mismatched_title_raises(self):
        step = tour_smoke.TOUR_STEPS[0]
        nodes = [
            ax_node("tour.step.overview", title="Wrong Title"),
            ax_node("tour.progress", value="1/17"),
        ]
        with self.assertRaisesRegex(AssertionError, "title mismatch"):
            self.checks.assert_step_state(0, step, nodes)

    def test_assert_step_state_mismatched_instruction_raises(self):
        step = tour_smoke.TOUR_STEPS[0]
        nodes = [
            ax_node("tour.step.overview", title="Meet your fleet"),
            ax_node("tour.progress", value="1/17"),
            ax_node("tour.instruction", value="Completely different text without match"),
        ]
        with self.assertRaisesRegex(AssertionError, "instruction mismatch"):
            self.checks.assert_step_state(0, step, nodes)

    def test_assert_step_state_mismatched_progress_raises(self):
        step = tour_smoke.TOUR_STEPS[0]
        nodes = [
            ax_node("tour.step.overview", title="Meet your fleet"),
            ax_node("tour.progress", value="2/17"),
        ]
        with self.assertRaisesRegex(AssertionError, "progress mismatch"):
            self.checks.assert_step_state(0, step, nodes)

    def test_assert_step_state_missing_step_marker_raises(self):
        step = tour_smoke.TOUR_STEPS[0]
        nodes = [
            ax_node("tour.step.other", title="Meet your fleet"),
            ax_node("tour.progress", value="1/17"),
        ]
        with self.assertRaisesRegex(AssertionError, "Missing step marker"):
            self.checks.assert_step_state(0, step, nodes)

    def test_target_frame_positive_dimensions_validation(self):
        step = tour_smoke.TOUR_STEPS[2]  # openMiner
        by_id = {
            "tour.tapTarget": ax_node("tour.tapTarget", frame={"x": 10.0, "y": 20.0, "width": 100.0, "height": 50.0})
        }
        self.checks.assert_target_frame_if_exposed(step, by_id)

    def test_target_frame_zero_or_negative_dimensions_rejected(self):
        step = tour_smoke.TOUR_STEPS[2]
        for w, h in ((0.0, 50.0), (100.0, -5.0), (-1.0, -1.0)):
            with self.subTest(w=w, h=h):
                by_id = {
                    "tour.tapTarget": ax_node("tour.tapTarget", frame={"x": 10.0, "y": 20.0, "width": w, "height": h})
                }
                with self.assertRaisesRegex(AssertionError, "non-positive frame dimensions"):
                    self.checks.assert_target_frame_if_exposed(step, by_id)

    def test_target_frame_nan_or_infinite_dimensions_rejected(self):
        step = tour_smoke.TOUR_STEPS[2]
        for val in (float("inf"), float("-inf"), float("nan")):
            with self.subTest(val=val):
                by_id = {
                    "tour.tapTarget": ax_node("tour.tapTarget", frame={"x": 0.0, "y": 0.0, "width": val, "height": 50.0})
                }
                with self.assertRaisesRegex(AssertionError, "finite"):
                    self.checks.assert_target_frame_if_exposed(step, by_id)

    def test_assert_step_state_missing_instruction_node_raises(self):
        step = tour_smoke.TOUR_STEPS[0]
        nodes = [
            ax_node("tour.step.overview", title="Meet your fleet"),
            ax_node("tour.progress", value="1/17"),
            ax_node("tour.back", enabled=False),
            ax_node("tour.highlight"),
        ]
        with self.assertRaisesRegex(AssertionError, "missing tour instruction"):
            self.checks.assert_step_state(0, step, nodes)

    def test_assert_step_state_missing_back_button_raises(self):
        step = tour_smoke.TOUR_STEPS[0]
        nodes = [
            ax_node("tour.step.overview", title="Meet your fleet"),
            ax_node("tour.progress", value="1/17"),
            ax_node("tour.instruction", value="adds up their hashrate and power"),
            ax_node("tour.highlight"),
        ]
        with self.assertRaisesRegex(AssertionError, "missing tour back"):
            self.checks.assert_step_state(0, step, nodes)

    def test_assert_step_state_back_button_enabled_at_step_zero_raises(self):
        step = tour_smoke.TOUR_STEPS[0]
        nodes = [
            ax_node("tour.step.overview", title="Meet your fleet"),
            ax_node("tour.progress", value="1/17"),
            ax_node("tour.instruction", value="adds up their hashrate and power"),
            ax_node("tour.back", enabled=True),
            ax_node("tour.highlight"),
        ]
        with self.assertRaisesRegex(AssertionError, "disabled on initial step 0"):
            self.checks.assert_step_state(0, step, nodes)

    def test_assert_step_state_back_button_disabled_at_step_one_raises(self):
        step = tour_smoke.TOUR_STEPS[1]
        nodes = [
            ax_node("tour.step.history", title="View hashrate over time"),
            ax_node("tour.progress", value="2/17"),
            ax_node("tour.instruction", value="Swipe left or right on the history chart"),
            ax_node("tour.back", enabled=False),
            ax_node("tour.highlight"),
        ]
        with self.assertRaisesRegex(AssertionError, "enabled on step 1"):
            self.checks.assert_step_state(1, step, nodes)

    def test_assert_step_state_missing_tap_target_for_interactive_step_raises(self):
        step = tour_smoke.TOUR_STEPS[2]  # openMiner (interactive)
        nodes = [
            ax_node("tour.step.openMiner", title="Open a miner"),
            ax_node("tour.progress", value="3/17"),
            ax_node("tour.instruction", value="hand points to the same kind of card"),
            ax_node("tour.back", enabled=True),
        ]
        with self.assertRaisesRegex(AssertionError, "missing tap target"):
            self.checks.assert_step_state(2, step, nodes)

    def test_assert_step_state_disabled_tap_target_raises(self):
        step = tour_smoke.TOUR_STEPS[2]
        nodes = [
            ax_node("tour.step.openMiner", title="Open a miner"),
            ax_node("tour.progress", value="3/17"),
            ax_node("tour.instruction", value="hand points to the same kind of card"),
            ax_node("tour.back", enabled=True),
            ax_node("tour.tapTarget", title="Open the sample miner", enabled=False),
        ]
        with self.assertRaisesRegex(AssertionError, "is disabled"):
            self.checks.assert_step_state(2, step, nodes)

    def test_assert_step_state_mismatched_tap_target_label_raises(self):
        step = tour_smoke.TOUR_STEPS[2]
        nodes = [
            ax_node("tour.step.openMiner", title="Open a miner"),
            ax_node("tour.progress", value="3/17"),
            ax_node("tour.instruction", value="hand points to the same kind of card"),
            ax_node("tour.back", enabled=True),
            ax_node("tour.tapTarget", title="Completely Wrong Label", enabled=True),
        ]
        with self.assertRaisesRegex(AssertionError, "tap target label mismatch"):
            self.checks.assert_step_state(2, step, nodes)

    def test_assert_step_state_missing_highlight_for_informational_step_raises(self):
        step = tour_smoke.TOUR_STEPS[0]
        nodes = [
            ax_node("tour.step.overview", title="Meet your fleet"),
            ax_node("tour.progress", value="1/17"),
            ax_node("tour.instruction", value="adds up their hashrate and power"),
            ax_node("tour.back", enabled=False),
        ]
        with self.assertRaisesRegex(AssertionError, "missing target highlight"):
            self.checks.assert_step_state(0, step, nodes)

    def test_target_frame_rejects_nonfinite_frame_status(self):
        step = tour_smoke.TOUR_STEPS[2]
        by_id = {
            "tour.tapTarget": {"id": "tour.tapTarget", "frame": None, "frame_status": "nonfinite"}
        }
        with self.assertRaisesRegex(AssertionError, "nonfinite geometry"):
            self.checks.assert_target_frame_if_exposed(step, by_id)

    def test_target_frame_rejects_unreadable_frame_status(self):
        step = tour_smoke.TOUR_STEPS[2]
        by_id = {
            "tour.tapTarget": {"id": "tour.tapTarget", "frame": None, "frame_status": "unreadable"}
        }
        with self.assertRaisesRegex(AssertionError, "unreadable geometry"):
            self.checks.assert_target_frame_if_exposed(step, by_id)

    def test_advance_step_last_step_calls_press_done(self):
        step = tour_smoke.TOUR_STEPS[16]  # complete (last step)
        self.checks.advance_step(16, step)
        self.probe.press.assert_called_once_with(tour_smoke.TOUR_DONE)

    def test_advance_step_interactive_never_falls_back_on_tap_target_error(self):
        step = tour_smoke.TOUR_STEPS[2]  # openMiner (interactive)
        error = subprocess.TimeoutExpired("probe", 8)
        self.probe.press.side_effect = error
        with self.assertRaises(subprocess.TimeoutExpired):
            self.checks.advance_step(2, step)
        self.probe.press.assert_called_once_with(tour_smoke.TOUR_TAP_TARGET)

    def test_advance_step_non_interactive_calls_next_directly(self):
        step = tour_smoke.TOUR_STEPS[0]  # overview (non-interactive)
        self.checks.advance_step(0, step)
        self.probe.press.assert_called_once_with(tour_smoke.TOUR_NEXT)


class TourFixture(nav_smoke.NativeMacProbe):
    """Simulates the 17-step FleetTourView state machine for offline verification."""

    def __init__(self, work: Path):
        super().__init__(work / "fake-probe", 4242, work, owned=False, wait_seconds=0.01)
        self.step_index = 0
        self.actions = []
        self.dismissed = False
        self.preparing_frames_left = 0
        self.nonfinite_frames_left = 0

    def nodes(self):
        if self.dismissed:
            return [ax_node("dashboard.miner.demo-one")]

        step = tour_smoke.TOUR_STEPS[self.step_index]
        result = [
            ax_node(tour_smoke.TOUR_VIEW),
            ax_node(f"tour.step.{step.id}", title=step.title),
            ax_node(tour_smoke.TOUR_PROGRESS, value=f"{self.step_index + 1}/17"),
            ax_node(tour_smoke.TOUR_INSTRUCTION, value=f"Demo instruction containing {step.instruction_substr}."),
            ax_node(tour_smoke.TOUR_BACK, enabled=(self.step_index > 0)),
            ax_node(tour_smoke.TOUR_CLOSE),
        ]
        is_last = self.step_index == len(tour_smoke.TOUR_STEPS) - 1
        result.append(ax_node(tour_smoke.TOUR_DONE if is_last else tour_smoke.TOUR_NEXT))

        if self.preparing_frames_left > 0:
            self.preparing_frames_left -= 1
            result.append(ax_node(tour_smoke.TOUR_PREPARING, title="Preparing this view…"))
            return result

        if self.nonfinite_frames_left > 0:
            self.nonfinite_frames_left -= 1
            target_id = tour_smoke.TOUR_TAP_TARGET if step.tap_title is not None else tour_smoke.TOUR_HIGHLIGHT
            result.append({
                "id": target_id,
                "title": step.tap_title or step.title,
                "enabled": True,
                "frame": None,
                "frame_status": "nonfinite",
            })
            return result

        # Spotlight target / highlight with valid frame
        if step.tap_title is not None:
            result.append(ax_node(
                tour_smoke.TOUR_TAP_TARGET,
                title=step.tap_title,
                frame={"x": 100.0, "y": 150.0, "width": 250.0, "height": 80.0},
            ))
        else:
            result.append(ax_node(
                tour_smoke.TOUR_HIGHLIGHT,
                title=f"Highlighted area: {step.title}",
                frame={"x": 80.0, "y": 120.0, "width": 300.0, "height": 100.0},
            ))
        return result

    def call(self, *arguments):
        if arguments == ("list",):
            return json.dumps(self.nodes())

        self.actions.append(arguments)
        action, target = arguments
        if action == "press":
            if target in (tour_smoke.TOUR_NEXT, tour_smoke.TOUR_TAP_TARGET):
                if self.step_index < len(tour_smoke.TOUR_STEPS) - 1:
                    self.step_index += 1
            elif target == tour_smoke.TOUR_BACK:
                if self.step_index > 0:
                    self.step_index -= 1
            elif target == tour_smoke.TOUR_DONE:
                self.dismissed = True
            elif target == tour_smoke.TOUR_CLOSE:
                self.dismissed = True
        return "fixture action"


class TourWorkflowAndTransitionTests(QuietTestBase):
    def test_polling_checks_all_steps_and_ax_fallbacks(self):
        fixture = TourFixture(self.work)
        for index, step in enumerate(tour_smoke.TOUR_STEPS):
            with self.subTest(step=step.id):
                fixture.step_index = index
                by_id = {node["id"]: node for node in fixture.nodes()}
                checks = tour_smoke.TourChecks(fixture, dwell_seconds=0.0)
                self.assertTrue(checks._step_content_matches(index, step, by_id))
                self.assertTrue(checks._step_controls_match(index, step, by_id))
                heading = by_id[f"tour.step.{step.id}"]
                heading.update(title="", description="", value=step.title)
                by_id[tour_smoke.TOUR_PROGRESS].update(value="", title=f"{index + 1}/17")
                by_id[tour_smoke.TOUR_INSTRUCTION].update(
                    value="", description="", title=step.instruction_substr
                )
                self.assertTrue(checks._step_content_matches(index, step, by_id))
                if step.tap_title is not None:
                    by_id[tour_smoke.TOUR_TAP_TARGET].update(title="", description=step.tap_title)
                    self.assertTrue(checks._step_controls_match(index, step, by_id))
                by_id[tour_smoke.TOUR_PREPARING] = ax_node(tour_smoke.TOUR_PREPARING)
                self.assertFalse(checks._step_controls_match(index, step, by_id))

    def test_polling_timeout_preserves_last_snapshot_diagnostic(self):
        fixture = TourFixture(self.work)
        nodes = fixture.nodes()
        by_id = {node["id"]: node for node in nodes}
        by_id["tour.step.overview"]["title"] = "Wrong title"
        probe = Mock()

        def time_out(predicate, *, message):
            self.assertFalse(predicate(nodes))
            raise AssertionError(message)

        probe.wait_for.side_effect = time_out
        checks = tour_smoke.TourChecks(probe, dwell_seconds=0.0)
        with self.assertRaisesRegex(AssertionError, "title mismatch"):
            checks.wait_for_step(0, tour_smoke.TOUR_STEPS[0])

    def test_run_all_17_steps_walks_complete_sequence(self):
        fixture = TourFixture(self.work)
        checks = tour_smoke.TourChecks(fixture, dwell_seconds=0.0)
        checks.run_all_17_steps()
        self.assertEqual(fixture.step_index, 16)
        self.assertEqual(len(fixture.actions), 16)
        self.assertGreater(fixture.sequence, 16)

    def test_wait_for_step_retries_and_settles_after_preparing_badge(self):
        fixture = TourFixture(self.work)
        fixture.wait_seconds = 2.0
        fixture.preparing_frames_left = 2
        checks = tour_smoke.TourChecks(fixture, dwell_seconds=0.0)
        step = tour_smoke.TOUR_STEPS[0]
        with patch.object(nav_smoke.time, "sleep"):
            nodes = checks.wait_for_step(0, step)
        self.assertNotIn(tour_smoke.TOUR_PREPARING, [n.get("id") for n in nodes])
        self.assertEqual(fixture.preparing_frames_left, 0)

    def test_wait_for_step_retries_transient_nonfinite_frame_until_settled(self):
        fixture = TourFixture(self.work)
        fixture.wait_seconds = 2.0
        fixture.nonfinite_frames_left = 2
        checks = tour_smoke.TourChecks(fixture, dwell_seconds=0.0)
        step = tour_smoke.TOUR_STEPS[0]
        with patch.object(nav_smoke.time, "sleep"):
            nodes = checks.wait_for_step(0, step)
        by_id = {n.get("id"): n for n in nodes}
        highlight = by_id[tour_smoke.TOUR_HIGHLIGHT]
        self.assertIsNone(highlight.get("frame_status"))  # settled node has valid frame
        self.assertIsNotNone(highlight.get("frame"))
        self.assertEqual(fixture.nonfinite_frames_left, 0)

    def test_transition_cycles_exercises_miner_cooling_coins_repeatedly(self):
        fixture = TourFixture(self.work)
        checks = tour_smoke.TourChecks(fixture, dwell_seconds=0.0)

        checks.run_transition_cycles(cycles=3)

        back_count = fixture.actions.count(("press", tour_smoke.TOUR_BACK))
        self.assertEqual(back_count, 6)
        self.assertEqual(fixture.step_index, 2)

    def test_run_optional_controls_back_and_close(self):
        fixture = TourFixture(self.work)
        checks = tour_smoke.TourChecks(fixture, dwell_seconds=0.0)
        checks.run_optional_controls()
        self.assertTrue(fixture.dismissed)
        self.assertIn(("press", tour_smoke.TOUR_CLOSE), fixture.actions)

    def test_return_to_overview_from_step_16(self):
        fixture = TourFixture(self.work)
        fixture.step_index = 16
        checks = tour_smoke.TourChecks(fixture, dwell_seconds=0.0)
        checks.return_to_overview(16)
        self.assertEqual(fixture.step_index, 0)
        self.assertEqual(fixture.actions.count(("press", tour_smoke.TOUR_BACK)), 16)

    def test_return_to_overview_from_step_2(self):
        fixture = TourFixture(self.work)
        fixture.step_index = 2
        checks = tour_smoke.TourChecks(fixture, dwell_seconds=0.0)
        checks.return_to_overview(2)
        self.assertEqual(fixture.step_index, 0)
        self.assertEqual(fixture.actions.count(("press", tour_smoke.TOUR_BACK)), 2)

    def test_run_tour_acceptance_combined_trace_end_to_end(self):
        fixture = TourFixture(self.work)
        # Execute the complete trace: full tour -> cycles -> optional controls
        tour_smoke.run_tour_acceptance(
            fixture,
            full_tour=True,
            cycles=2,
            dwell_seconds=0.0,
            optional_controls=True,
            work_dir=self.work,
        )
        # Tour must finish dismissed via Close after seamless return_to_overview transitions
        self.assertTrue(fixture.dismissed)
        self.assertIn(("press", tour_smoke.TOUR_CLOSE), fixture.actions)

    def test_run_tour_acceptance_preserves_sample_on_failure(self):
        fixture = TourFixture(self.work)
        checks = tour_smoke.TourChecks(fixture, dwell_seconds=0.0)

        real_call = fixture.call

        def failing_call(*arguments):
            if fixture.step_index == 3 and arguments == ("list",):
                nodes = fixture.nodes()
                for n in nodes:
                    if n.get("id") == "tour.step.cooling":
                        n["title"] = "Wrong Cooling Title"
                        n["description"] = ""
                return json.dumps(nodes)
            return real_call(*arguments)

        fixture.call = failing_call

        def mock_sampler(*args, **kwargs):
            file_arg = args[0][6]
            Path(file_arg).write_text("failure sample stack\n")
            return subprocess.CompletedProcess(args[0], 0)

        with patch.object(tour_smoke, "verify_pid_identity", return_value=(True, "Hash Fleet")), \
             patch.object(tour_smoke.subprocess, "run", side_effect=mock_sampler):
            with self.assertRaises(AssertionError):
                tour_smoke.run_tour_acceptance(fixture, full_tour=True, work_dir=self.work)

        meta_files = list(self.work.glob("tour-failure-*.json"))
        self.assertEqual(len(meta_files), 1)
        meta = json.loads(meta_files[0].read_text())
        self.assertIn("title mismatch", meta["reason"])


class CLIBoundsValidationTests(unittest.TestCase):
    def test_nominal_action_counts_cover_all_modes(self):
        for cycles, full_tour, optional, expected in (
            (0, False, False, 0), (0, False, True, 3),
            (0, True, False, 17), (0, True, True, 36),
            (3, False, False, 14), (3, False, True, 19),
            (3, True, False, 47), (3, True, True, 52),
        ):
            with self.subTest(cycles=cycles, full_tour=full_tour, optional=optional):
                self.assertEqual(tour_smoke._nominal_tour_actions(cycles, full_tour, optional), expected)

    def test_exact_nominal_duration_ceiling_is_inclusive(self):
        args = dict(cycles=10, wait_seconds=60.0, full_tour=True, optional_controls=True)
        tour_smoke.validate_cli_bounds(dwell=6.0, **args)
        with self.assertRaisesRegex(ValueError, "exceeds 480"):
            tour_smoke.validate_cli_bounds(dwell=math.nextafter(6.0, math.inf), **args)
        tour_smoke.validate_cli_bounds(50, 0.0, 60.0, True, True)
        tour_smoke.validate_cli_bounds(0, 10.0, 60.0, False, False)

    def test_nonfinite_values_in_each_numeric_argument_fail_closed(self):
        for name in ("cycles", "dwell", "wait_seconds"):
            for value in (math.nan, math.inf, -math.inf):
                with self.subTest(name=name, value=value):
                    args = dict(cycles=3, dwell=0.2, wait_seconds=12.0,
                                full_tour=True, optional_controls=True)
                    args[name] = value
                    with self.assertRaisesRegex(ValueError, "must be finite"):
                        tour_smoke.validate_cli_bounds(**args)

    def test_valid_cli_bounds_pass(self):
        tour_smoke.validate_cli_bounds(
            cycles=3, dwell=0.2, wait_seconds=12.0, full_tour=True, optional_controls=True
        )

    def test_negative_or_invalid_values_raise_value_error(self):
        for kwargs in (
            {"cycles": -1, "dwell": 0.2, "wait_seconds": 12.0, "full_tour": True, "optional_controls": False},
            {"cycles": 3, "dwell": -0.1, "wait_seconds": 12.0, "full_tour": True, "optional_controls": False},
            {"cycles": 3, "dwell": 0.2, "wait_seconds": 0.0, "full_tour": True, "optional_controls": False},
            {"cycles": 3, "dwell": 0.2, "wait_seconds": -5.0, "full_tour": True, "optional_controls": False},
            {"cycles": 3, "dwell": float("nan"), "wait_seconds": 12.0, "full_tour": True, "optional_controls": False},
            {"cycles": 3, "dwell": float("inf"), "wait_seconds": 12.0, "full_tour": True, "optional_controls": False},
            {"cycles": 100, "dwell": 0.2, "wait_seconds": 12.0, "full_tour": True, "optional_controls": False},
            {"cycles": 3, "dwell": 15.0, "wait_seconds": 12.0, "full_tour": True, "optional_controls": False},
            {"cycles": 3, "dwell": 0.2, "wait_seconds": 100.0, "full_tour": True, "optional_controls": False},
        ):
            with self.subTest(kwargs=kwargs):
                with self.assertRaises(ValueError):
                    tour_smoke.validate_cli_bounds(**kwargs)

    def test_dwell_exceeding_8min_ceiling_raises_value_error(self):
        # 17 + 16 + 2 + (10 * 4) + 2 + 3 = 80 actions * 7.0s dwell = 560s > 480s
        with self.assertRaisesRegex(ValueError, "exceeds 480"):
            tour_smoke.validate_cli_bounds(
                cycles=10, dwell=7.0, wait_seconds=12.0, full_tour=True, optional_controls=True
            )


class MainCLITests(QuietTestBase):
    def test_main_cli_launches_app_and_runs_acceptance(self):
        app = self.work / "Hash Fleet.app"
        app.mkdir()
        mock_probe = Mock(spec=tour_smoke.NativeMacTourProbe)
        mock_probe.pid = 9999
        mock_probe.owned = True
        mock_probe.expected_lstart = "start_time"

        with patch.object(tour_smoke.NativeMacTourProbe, "connect_tour", return_value=mock_probe) as mock_connect, \
             patch.object(tour_smoke, "run_tour_acceptance") as mock_run:
            tour_smoke.main(["--app", str(app), "--work-dir", str(self.work), "--cycles", "2", "--dwell", "0.1"])

        mock_connect.assert_called_once_with(
            app=app, pid=None, work=self.work, wait_seconds=12.0)
        mock_run.assert_called_once_with(
            mock_probe,
            full_tour=True,
            cycles=2,
            dwell_seconds=0.1,
            optional_controls=False,
            work_dir=self.work,
            expected_app_path=app,
            expected_lstart="start_time",
        )
        mock_probe.close_owned.assert_called_once()

    def test_main_cli_attaches_to_pid(self):
        mock_probe = Mock(spec=tour_smoke.NativeMacTourProbe)
        mock_probe.pid = 3333
        mock_probe.owned = False
        mock_probe.expected_lstart = "start_time"

        with patch.object(tour_smoke.NativeMacTourProbe, "connect_tour", return_value=mock_probe) as mock_connect, \
             patch.object(tour_smoke, "run_tour_acceptance") as mock_run:
            tour_smoke.main(["--pid", "3333", "--work-dir", str(self.work)])

        mock_connect.assert_called_once_with(
            app=None, pid=3333, work=self.work, wait_seconds=12.0)
        mock_run.assert_called_once()
        mock_probe.close_owned.assert_called_once()

    def test_ensure_workspace_raised_invokes_menu_when_window_hidden(self):
        calls = []

        def mock_run(cmd, *args, **kwargs):
            calls.append(cmd)
            return subprocess.CompletedProcess(cmd, 0)

        with patch.object(tour_smoke.subprocess, "check_output", side_effect=['[{"id":"other"}]', '[{"id":"tour.view"}]']), \
             patch.object(tour_smoke.subprocess, "run", side_effect=mock_run):
            tour_smoke.NativeMacTourProbe._ensure_workspace_raised(Path("/fake/probe"), 4242, 2.0)

        self.assertTrue(any("Show Hash Fleet" in cmd for cmd in calls))

    def test_connect_tour_attached_never_raises_workspace(self):
        with patch.object(tour_smoke.NativeMacTourProbe, "_ensure_workspace_raised") as mock_raise, \
             patch.object(tour_smoke.subprocess, "run"), \
             patch.object(tour_smoke, "get_process_identity", return_value=("/bin/app", "lstart")):
            tour_smoke.NativeMacTourProbe.connect_tour(pid=4242, work=self.work)
        mock_raise.assert_not_called()

    def test_main_cli_mutually_exclusive_args_rejected(self):
        err = io.StringIO()
        with contextlib.redirect_stderr(err):
            with self.assertRaises(SystemExit):
                tour_smoke.main(["--app", str(self.work), "--pid", "1234", "--work-dir", str(self.work)])


class SwiftProbeSerializationRegressionTests(unittest.TestCase):
    def test_swift_probe_serialization_regression_never_aborts_on_nonfinite_geometry(self):
        probe_path = SCRIPTS / "NativeMacNavigationProbe.swift"
        self.assertTrue(probe_path.exists(), f"Probe source must exist at {probe_path}")
        probe_source = probe_path.read_text(encoding="utf-8")

        start_marker = "if point.x.isFinite && point.y.isFinite && size.width.isFinite && size.height.isFinite {"
        end_marker = 'nodeInfo["frame_status"] = "nonfinite"\n                }'

        self.assertEqual(
            probe_source.count(start_marker), 1,
            f"Expected exactly 1 occurrence of finite guard in {probe_path}"
        )
        self.assertEqual(
            probe_source.count(end_marker), 1,
            f"Expected exactly 1 occurrence of nonfinite fallback block in {probe_path}"
        )

        start_idx = probe_source.index(start_marker)
        end_idx = probe_source.index(end_marker) + len(end_marker)
        extracted_guard_block = probe_source[start_idx:end_idx]

        swift_program = f"""
import Foundation

func processNode(point: CGPoint, size: CGSize) -> [String: Any] {{
    var nodeInfo: [String: Any] = ["id": "probe.target"]
    {extracted_guard_block}
    return nodeInfo
}}

// 1. Finite valid geometry
let finiteNode = processNode(point: CGPoint(x: 100.0, y: 150.0), size: CGSize(width: 250.0, height: 80.0))

// 2. Infinite geometry
let infNode = processNode(point: CGPoint(x: CGFloat.infinity, y: 100.0), size: CGSize(width: 200.0, height: 50.0))

// 3. NaN geometry
let nanNode = processNode(point: CGPoint(x: 50.0, y: 20.0), size: CGSize(width: CGFloat.nan, height: 80.0))

let allNodes = [finiteNode, infNode, nanNode]
assert(JSONSerialization.isValidJSONObject(allNodes), "allNodes must be valid JSON object")

let data = try JSONSerialization.data(withJSONObject: allNodes, options: [.sortedKeys])
let jsonStr = String(decoding: data, as: UTF8.self)

assert(jsonStr.contains("\\"frame_status\\":\\"valid\\""), "Finite node must have valid status")
assert(jsonStr.contains("\\"frame_status\\":\\"nonfinite\\""), "Nonfinite nodes must have nonfinite status")
assert(jsonStr.contains("\\"frame\\":null"), "Nonfinite nodes must have null frame")

print("PASS: Extracted probe serialization block handles finite, infinite, and NaN geometry safely")
"""
        proc = subprocess.run(
            ["xcrun", "swift", "-"],
            input=swift_program,
            text=True,
            capture_output=True,
            timeout=15,
        )
        self.assertEqual(proc.returncode, 0, f"Swift execution failed:\nSTDOUT: {proc.stdout}\nSTDERR: {proc.stderr}")
        self.assertIn("PASS: Extracted probe serialization block", proc.stdout)


if __name__ == "__main__":
    unittest.main()
