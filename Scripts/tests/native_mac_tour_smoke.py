#!/usr/bin/env python3
"""Bounded PID-scoped native Mac tour smoke test and acceptance harness.

Verifies the 17-step FleetGuidedDemoSteps guided tour sequence, interactive
spotlight actions, and transitions (openMiner -> cooling, cooling -> openCoins).
Preserves diagnostics sample on failure with an 8 MiB cap enforced via RLIMIT_FSIZE
and a 10 s timeout. Fails closed on any PID identity ambiguity; never kills an
attached PID.
"""
from dataclasses import dataclass
import argparse
import datetime
import json
import math
import os
from pathlib import Path
import resource
import signal
import subprocess
import sys
import time
from typing import Any, Callable, Dict, List, Optional, Tuple

SCRIPTS_DIR = Path(__file__).resolve().parent
if str(SCRIPTS_DIR) not in sys.path:
    sys.path.insert(0, str(SCRIPTS_DIR))

try:
    from native_mac_navigation_smoke import NativeMacProbe
except ImportError:
    NativeMacProbe = None  # Handled or mocked in offline test harnesses


# Accessibility identifiers from FleetTourView, FleetGuidedSpotlight, and Dashboard
TOUR_VIEW = "tour.view"
TOUR_CLOSE = "tour.close"
TOUR_NEXT = "tour.next"
TOUR_BACK = "tour.back"
TOUR_DONE = "tour.done"
TOUR_PROGRESS = "tour.progress"
TOUR_CHOOSER = "tour.chooser"
TOUR_SAMPLE_BANNER = "tour.sampleBanner"
TOUR_INSTRUCTION = "tour.instruction"
TOUR_DONT_SHOW_AGAIN = "tour.dontShowAgain"
TOUR_TAP_TARGET = "tour.tapTarget"
TOUR_HIGHLIGHT = "tour.highlight"
TOUR_PREPARING = "tour.preparing"

# Sample 8 MiB cap and 10 s deadline
SAMPLE_MAX_BYTES = 8 * 1024 * 1024
SAMPLE_TIMEOUT_SECONDS = 10

# Maximum permitted nominal run duration in seconds (8 minutes)
MAX_NOMINAL_DURATION_SECONDS = 480.0


@dataclass(frozen=True)
class TourStepSpec:
    """Exact step specification derived from FleetGuidedDemoSteps.swift."""
    id: str
    screen: str
    target: str
    title: str
    instruction_substr: str
    tap_title: Optional[str] = None


# Canonical 17 steps with discriminating substrings from current FleetGuidedDemoSteps.swift
TOUR_STEPS: Tuple[TourStepSpec, ...] = (
    TourStepSpec(
        id="overview",
        screen="fleet",
        target="guide.hero",
        title="Meet your fleet",
        instruction_substr="adds up their hashrate and power",
        tap_title=None,
    ),
    TourStepSpec(
        id="history",
        screen="fleet",
        target="guide.history",
        title="View hashrate over time",
        instruction_substr="Swipe left or right on the history chart",
        tap_title=None,
    ),
    TourStepSpec(
        id="openMiner",
        screen="fleet",
        target="guide.miner",
        title="Open a miner",
        instruction_substr="hand points to the same kind of card",
        tap_title="Open the sample miner",
    ),
    TourStepSpec(
        id="cooling",
        screen="miner",
        target="guide.cooling",
        title="Check temperature and cooling",
        instruction_substr="chip temperature and fan speed",
        tap_title=None,
    ),
    TourStepSpec(
        id="openCoins",
        screen="fleet",
        target="guide.coinSelection",
        title="Choose what the dashboard shows",
        instruction_substr="Back on Fleet, tap Coins to show",
        tap_title="Open Coins to show",
    ),
    TourStepSpec(
        id="chooseDGB",
        screen="coins",
        target="guide.coin.DGB",
        title="Try a display choice",
        instruction_substr="add DigiByte",
        tap_title="Turn on DigiByte in the demo",
    ),
    TourStepSpec(
        id="coinResult",
        screen="fleet",
        target="guide.chain.DGB",
        title="See your choice take effect",
        instruction_substr="DGB now shows up once",
        tap_title=None,
    ),
    TourStepSpec(
        id="openPreferences",
        screen="settings",
        target="guide.preferencesEntry",
        title="Find display settings",
        instruction_substr="In Settings, tap Preferences",
        tap_title="Open Preferences",
    ),
    TourStepSpec(
        id="appearance",
        screen="preferences",
        target="guide.appearance",
        title="Choose your appearance",
        instruction_substr="Light, Dark, or System mode",
        tap_title=None,
    ),
    TourStepSpec(
        id="openEnergy",
        screen="settings",
        target="guide.energyEntry",
        title="Find your fleet tools",
        instruction_substr="Electricity estimates",
        tap_title="Open Electricity estimates",
    ),
    TourStepSpec(
        id="energy",
        screen="energy",
        target="guide.dailyCost",
        title="Understand the estimate",
        instruction_substr="0.15 USD per kWh",
        tap_title=None,
    ),
    TourStepSpec(
        id="openReports",
        screen="settings",
        target="guide.reportEntry",
        title="Find snapshot reports",
        instruction_substr="Fleet reports",
        tap_title="Open Fleet reports",
    ),
    TourStepSpec(
        id="previewReport",
        screen="report",
        target="guide.previewPDF",
        title="Preview before you share",
        instruction_substr="Preview PDF",
        tap_title="Preview the sample fleet PDF",
    ),
    TourStepSpec(
        id="pdf",
        screen="pdf",
        target="guide.pdf",
        title="Here's the actual report",
        instruction_substr="anonymous sample readings",
        tap_title=None,
    ),
    TourStepSpec(
        id="openAlerts",
        screen="settings",
        target="guide.notificationsEntry",
        title="Set up alerts from Settings",
        instruction_substr="Notifications and banners",
        tap_title="Expand Notifications and banners",
    ),
    TourStepSpec(
        id="alerts",
        screen="notifications",
        target="guide.notificationTest",
        title="Know where to test delivery",
        instruction_substr="notification controls",
        tap_title=None,
    ),
    TourStepSpec(
        id="complete",
        screen="fleet",
        target="guide.hero",
        title="Ready for your own fleet",
        instruction_substr="fleet you left",
        tap_title=None,
    ),
)


def _validate_cli_values(cycles: int, dwell: float, wait_seconds: float) -> None:
    """Reject invalid values before calculating the requested tour duration."""
    for name, val in (("cycles", cycles), ("dwell", dwell), ("wait-seconds", wait_seconds)):
        if isinstance(val, float) and (math.isnan(val) or math.isinf(val)):
            raise ValueError(f"Argument '{name}' must be finite: {val}")
        if val < 0:
            raise ValueError(f"Argument '{name}' must be non-negative: {val}")

    if wait_seconds <= 0:
        raise ValueError(f"Argument 'wait-seconds' must be strictly positive: {wait_seconds}")
    if cycles > 50:
        raise ValueError(f"Argument 'cycles' exceeds maximum safe bound (50): {cycles}")
    if dwell > 10.0:
        raise ValueError(f"Argument 'dwell' exceeds maximum safe bound (10.0s): {dwell}")
    if wait_seconds > 60.0:
        raise ValueError(f"Argument 'wait-seconds' exceeds maximum safe bound (60.0s): {wait_seconds}")


def _nominal_tour_actions(cycles: int, full_tour: bool, optional_controls: bool) -> int:
    """Count the actions that contribute to the nominal dwell-time ceiling."""
    nominal_actions = 0
    if full_tour:
        nominal_actions += 17
        if cycles > 0 or optional_controls:
            nominal_actions += 16
    if cycles > 0:
        nominal_actions += 2 + (cycles * 4)
        if optional_controls:
            nominal_actions += 2
    if optional_controls:
        nominal_actions += 3
    return nominal_actions


def validate_cli_bounds(
    cycles: int,
    dwell: float,
    wait_seconds: float,
    full_tour: bool,
    optional_controls: bool,
) -> None:
    """Validate finite, non-negative bounds and enforce <= 480 s (8 min) nominal ceiling."""
    _validate_cli_values(cycles, dwell, wait_seconds)
    nominal_actions = _nominal_tour_actions(cycles, full_tour, optional_controls)

    nominal_dwell_time = nominal_actions * dwell
    if nominal_dwell_time > MAX_NOMINAL_DURATION_SECONDS:
        raise ValueError(
            f"Requested parameters ({cycles} cycles, {dwell}s dwell) nominal dwell time {nominal_dwell_time:.1f}s "
            f"exceeds {MAX_NOMINAL_DURATION_SECONDS}s (8 min) ceiling"
        )


def get_process_identity(pid: int) -> Tuple[Optional[str], Optional[str]]:
    """Query live process comm full path and lstart start-time using two separate bounded ps calls.

    Fails closed on any error. Never splits comm output so space-containing paths
    like '/Applications/Hash Fleet.app/Contents/MacOS/Hash Fleet' remain intact.
    """
    if pid <= 1:
        return None, None
    try:
        os.kill(pid, 0)
    except (ProcessLookupError, PermissionError):
        return None, None

    try:
        comm = subprocess.check_output(
            ["ps", "-p", str(pid), "-o", "comm="],
            text=True,
            timeout=5,
        ).strip()
    except (subprocess.CalledProcessError, subprocess.TimeoutExpired, FileNotFoundError):
        return None, None

    if not comm:
        return None, None

    try:
        lstart = subprocess.check_output(
            ["ps", "-p", str(pid), "-o", "lstart="],
            text=True,
            timeout=5,
        ).strip()
    except (subprocess.CalledProcessError, subprocess.TimeoutExpired, FileNotFoundError):
        return None, None

    if not lstart:
        return None, None

    return comm, lstart


def verify_pid_identity(
    pid: int,
    expected_app_path: Optional[Path] = None,
    expected_lstart: Optional[str] = None,
) -> Tuple[bool, str]:
    """Verify PID exists, is alive, and matches exact canonical executable path and start time.

    Fails closed (returns False) on any lookup error, dead process, mismatched executable path,
    or changed start time. Never uses loose substring matching.
    """
    comm, lstart = get_process_identity(pid)
    if comm is None:
        return False, f"Process {pid} identity lookup failed (dead process or unavailable ps)"

    if expected_lstart is not None:
        if lstart is None or lstart != expected_lstart:
            return False, (
                f"PID {pid} start time mismatch (PID reuse detected): "
                f"expected '{expected_lstart}', got '{lstart}'"
            )

    if expected_app_path is not None:
        expected_resolved = expected_app_path.resolve()
        candidates = [expected_resolved]
        if expected_resolved.suffix == ".app":
            candidates.append(expected_resolved / "Contents" / "MacOS" / expected_resolved.stem)

        comm_resolved = Path(comm).resolve()
        comm_path = Path(comm)
        if comm_resolved not in candidates and comm_path not in candidates:
            return False, (
                f"PID {pid} executable '{comm}' does not match "
                f"canonical expected path '{expected_resolved}'"
            )

    return True, f"{comm} (lstart: {lstart})"


def _record_sample_result(
    sample_file: Path,
    proc: Optional[subprocess.CompletedProcess],
    metadata: Dict[str, Any],
    max_bytes: int,
) -> None:
    """Classify sampler evidence without treating partial output as a capture."""
    if not sample_file.exists():
        return
    size = sample_file.stat().st_size
    metadata["sample_size_bytes"] = size
    was_signaled = proc is not None and (
        proc.returncode < 0 or proc.returncode in (128 + getattr(signal, "SIGXFSZ", 25), 25)
    )
    if was_signaled or size >= max_bytes:
        metadata["sample_truncated"] = True
        metadata["sample_partial"] = True
        metadata["sample_captured"] = False
        metadata["sample_error"] = "Sampler output exceeded max byte limit during execution"
    elif size == 0:
        metadata["sample_captured"] = False
        metadata["sample_error"] = "Sampler produced 0 bytes"
    elif proc is not None and proc.returncode == 0:
        metadata["sample_captured"] = True
        metadata["sample_path"] = str(sample_file)
    else:
        metadata["sample_captured"] = False
        metadata["sample_partial"] = True
        metadata["sample_error"] = f"Sampler exited with non-zero code {getattr(proc, 'returncode', 'unknown')}"


def preserve_failure_sample(
    pid: int,
    work_dir: Path,
    reason: str,
    *,
    expected_app_path: Optional[Path] = None,
    expected_lstart: Optional[str] = None,
    sampler_binary: str = "/usr/bin/sample",
    timeout_seconds: int = SAMPLE_TIMEOUT_SECONDS,
    max_bytes: int = SAMPLE_MAX_BYTES,
) -> Optional[Path]:
    """Capture diagnostics sample on failure with RLIMIT_FSIZE cap enforced during execution."""
    work_dir = work_dir.resolve()
    work_dir.mkdir(parents=True, exist_ok=True)

    timestamp = datetime.datetime.now(datetime.timezone.utc).strftime("%Y%m%dT%H%M%SZ")
    sample_file = work_dir / f"tour-failure-{pid}-{timestamp}.sample.txt"
    meta_file = work_dir / f"tour-failure-{pid}-{timestamp}.json"

    is_valid, identity_msg = verify_pid_identity(pid, expected_app_path, expected_lstart)
    metadata = {
        "pid": pid,
        "timestamp_utc": timestamp,
        "reason": reason,
        "identity_verified": is_valid,
        "identity_detail": identity_msg,
        "expected_app_path": str(expected_app_path) if expected_app_path else None,
        "expected_lstart": expected_lstart,
        "sample_captured": False,
        "sample_size_bytes": 0,
        "sample_partial": False,
    }

    if not is_valid:
        meta_file.write_text(json.dumps(metadata, indent=2) + "\n")
        return None

    sample_bin_path = Path(sampler_binary)
    if not sample_bin_path.exists():
        metadata["sample_error"] = f"Sampler binary not found: {sampler_binary}"
        meta_file.write_text(json.dumps(metadata, indent=2) + "\n")
        return None

    def _set_file_limit():
        # Enforce RLIMIT_FSIZE strictly during child execution. If setrlimit fails,
        # raising prevents child execution without the cap in place.
        resource.setrlimit(resource.RLIMIT_FSIZE, (max_bytes, max_bytes))

    proc = None
    try:
        proc = subprocess.run(
            [str(sample_bin_path), str(pid), "2", "10", "-mayDie", "-file", str(sample_file)],
            timeout=timeout_seconds,
            check=False,
            stdout=subprocess.DEVNULL,
            stderr=subprocess.DEVNULL,
            preexec_fn=_set_file_limit,
        )
    except subprocess.TimeoutExpired:
        metadata["sample_error"] = f"Sampler timed out after {timeout_seconds}s"
    except Exception as exc:
        metadata["sample_error"] = f"Sampler invocation failed (RLIMIT/exec error): {exc}"

    _record_sample_result(sample_file, proc, metadata, max_bytes)

    meta_file.write_text(json.dumps(metadata, indent=2) + "\n")
    return sample_file if metadata.get("sample_captured") else None


class NativeMacTourProbe(NativeMacProbe):
    """PID-scoped AX probe extending NativeMacProbe with launch-tour and identity cleanup."""

    def __init__(
        self,
        probe: Path,
        pid: int,
        work: Path,
        *,
        owned: bool,
        app_path: Optional[Path] = None,
        expected_lstart: Optional[str] = None,
        snapshot_prefix: str = "tour-ax",
        wait_seconds: float = 12,
    ):
        super().__init__(
            probe,
            pid,
            work,
            owned=owned,
            snapshot_prefix=snapshot_prefix,
            wait_seconds=wait_seconds,
        )
        self.app_path = app_path
        self.expected_lstart = expected_lstart

    @classmethod
    def connect_tour(
        cls,
        *,
        app: Optional[Path] = None,
        pid: Optional[int] = None,
        work: Path,
        probe_name: str = "tour-probe",
        snapshot_prefix: str = "tour-ax",
        wait_seconds: float = 12,
        private: bool = False,
    ) -> "NativeMacTourProbe":
        """Connect by launching app with launch-tour (--ui-testing --show-feature-tour) or attaching to pid."""
        if (app is None) == (pid is None):
            raise ValueError("Choose exactly one app or running PID")
        owned = app is not None
        app_resolved: Optional[Path] = None
        if owned:
            app_resolved = app.resolve(strict=True)
        else:
            assert pid > 1, f"Refusing an invalid or system PID: {pid}"

        work = work.resolve()
        work.mkdir(parents=True, exist_ok=True)
        if private:
            os.chmod(work, 0o700)

        probe = work / probe_name
        subprocess.run(
            [
                "xcrun",
                "swiftc",
                str(Path(__file__).with_name("NativeMacNavigationProbe.swift")),
                "-o",
                str(probe),
            ],
            check=True,
            timeout=120,
        )

        if owned:
            pid = int(
                subprocess.check_output(
                    [str(probe), "launch-tour", str(app_resolved)],
                    text=True,
                    timeout=30,
                ).strip()
            )

        assert pid > 1, f"Refusing an invalid or system PID: {pid}"
        _, expected_lstart = get_process_identity(pid)

        # For fresh owned launches, the workspace window might not be raised yet.
        # Boundedly wait for menu bar / status item and invoke Show Hash Fleet if tour.view is not visible.
        if owned:
            cls._ensure_workspace_raised(probe, pid, wait_seconds)

        return cls(
            probe,
            pid,
            work,
            owned=owned,
            app_path=app_resolved,
            expected_lstart=expected_lstart,
            snapshot_prefix=snapshot_prefix,
            wait_seconds=wait_seconds,
        )

    @staticmethod
    def _ensure_workspace_raised(probe: Path, pid: int, wait_seconds: float) -> None:
        """Boundedly wait for app window and raise workspace via menu if not already visible."""
        deadline = time.monotonic() + min(wait_seconds, 8.0)
        raised = False
        while time.monotonic() < deadline:
            try:
                raw = subprocess.check_output([str(probe), str(pid), "list"], text=True, timeout=8)
                nodes = json.loads(raw)
                if any(n.get("id") == TOUR_VIEW for n in nodes):
                    return
                if not raised:
                    subprocess.run(
                        [str(probe), str(pid), "menu", "Show Hash Fleet"],
                        timeout=5,
                        check=False,
                        stdout=subprocess.DEVNULL,
                        stderr=subprocess.DEVNULL,
                    )
                    raised = True
            except Exception:
                pass
            time.sleep(0.3)

    def close_owned(self) -> None:
        """Terminate owned PID only after verified process identity. Never kills attached PID."""
        if not self.owned:
            return

        is_valid, _ = verify_pid_identity(self.pid, self.app_path, self.expected_lstart)
        self.owned = False
        if not is_valid:
            return

        try:
            os.kill(self.pid, signal.SIGTERM)
        except ProcessLookupError:
            pass


class TourChecks:
    """Verifies all 17 FleetGuidedDemoSteps, interactive spotlight, and key screen transitions."""

    def __init__(self, probe: NativeMacProbe, *, dwell_seconds: float = 0.2):
        self.probe = probe
        self.dwell_seconds = dwell_seconds

    @staticmethod
    def _step_content_matches(step_index: int, step: TourStepSpec, by_id: Dict[str, Any]) -> bool:
        """Check step identity and text using the AX fallback priority."""
        step_id_marker = f"tour.step.{step.id}"
        if step_id_marker not in by_id:
            return False
        step_node = by_id[step_id_marker]
        step_title = (
            step_node.get("title") or step_node.get("description") or step_node.get("value") or ""
        )
        if step.title != step_title and step.title not in step_title:
            return False
        if TOUR_PROGRESS not in by_id:
            return False
        prog_node = by_id[TOUR_PROGRESS]
        prog_text = prog_node.get("value") or prog_node.get("title") or ""
        expected_progress = f"{step_index + 1}/{len(TOUR_STEPS)}"
        if expected_progress not in prog_text and prog_text != expected_progress:
            return False
        if TOUR_INSTRUCTION not in by_id:
            return False
        inst_node = by_id[TOUR_INSTRUCTION]
        inst_text = (
            inst_node.get("value") or inst_node.get("description") or inst_node.get("title") or ""
        )
        return step.instruction_substr in inst_text

    @staticmethod
    def _step_controls_match(step_index: int, step: TourStepSpec, by_id: Dict[str, Any]) -> bool:
        """Wait for navigation and the appropriate interactive or informational target."""
        if TOUR_BACK not in by_id:
            return False
        back_enabled = by_id[TOUR_BACK].get("enabled", False)
        if step_index == 0 and back_enabled:
            return False
        if step_index > 0 and not back_enabled:
            return False
        if TOUR_PREPARING in by_id:
            return False
        if step.tap_title is None:
            return TOUR_HIGHLIGHT in by_id or step.target in by_id
        if TOUR_TAP_TARGET not in by_id:
            return False
        tap_node = by_id[TOUR_TAP_TARGET]
        if not tap_node.get("enabled", False):
            return False
        tap_title = tap_node.get("title") or tap_node.get("description") or ""
        return step.tap_title == tap_title or step.tap_title in tap_title

    def wait_for_step(self, step_index: int, step: TourStepSpec) -> List[Dict[str, Any]]:
        """Poll and wait until the requested step is fully displayed, settled, and valid."""
        last_nodes: List[Dict[str, Any]] = []

        def is_settled(nodes: List[Dict[str, Any]]) -> bool:
            nonlocal last_nodes
            last_nodes = nodes
            by_id = {node.get("id"): node for node in nodes if node.get("id")}
            if not self._step_content_matches(step_index, step, by_id):
                return False
            if not self._step_controls_match(step_index, step, by_id):
                return False

            try:
                self.assert_target_frame_if_exposed(step, by_id)
            except AssertionError:
                return False

            return True

        try:
            nodes = self.probe.wait_for(
                is_settled,
                message=f"Step {step.id} (index {step_index}) did not settle within wait timeout",
            )
        except AssertionError:
            if last_nodes:
                self.assert_step_state(step_index, step, last_nodes)
            raise
        self.assert_step_state(step_index, step, nodes)
        return nodes

    def assert_step_state(self, step_index: int, step: TourStepSpec, nodes: List[Dict[str, Any]]) -> None:
        """Assert step ID marker, title, progress text, and target frame when exposed."""
        by_id = {node.get("id"): node for node in nodes if node.get("id")}
        step_id_marker = f"tour.step.{step.id}"

        assert step_id_marker in by_id, f"Missing step marker: {step_id_marker}"
        step_node = by_id[step_id_marker]
        step_title = (
            step_node.get("title")
            or step_node.get("description")
            or step_node.get("value")
            or ""
        )
        assert (
            step.title == step_title or step.title in step_title
        ), f"Step {step.id} title mismatch: expected '{step.title}', got '{step_title}'"

        expected_progress = f"{step_index + 1}/{len(TOUR_STEPS)}"
        assert TOUR_PROGRESS in by_id, f"Missing tour progress marker '{TOUR_PROGRESS}'"
        prog_node = by_id[TOUR_PROGRESS]
        prog_text = prog_node.get("value") or prog_node.get("title") or ""
        assert (
            expected_progress in prog_text or prog_text == expected_progress
        ), f"Step {step.id} progress mismatch: expected '{expected_progress}', got '{prog_text}'"

        assert TOUR_INSTRUCTION in by_id, f"Step {step.id}: missing tour instruction marker '{TOUR_INSTRUCTION}'"
        inst_node = by_id[TOUR_INSTRUCTION]
        inst_text = (
            inst_node.get("value")
            or inst_node.get("description")
            or inst_node.get("title")
            or ""
        )
        assert (
            step.instruction_substr in inst_text
        ), f"Step {step.id} instruction mismatch: expected '{step.instruction_substr}' in '{inst_text}'"

        assert TOUR_BACK in by_id, f"Step {step.id}: missing tour back marker '{TOUR_BACK}'"
        back_enabled = by_id[TOUR_BACK].get("enabled", False)
        if step_index == 0:
            assert not back_enabled, f"Step {step.id}: Back button must be disabled on initial step 0"
        else:
            assert back_enabled, f"Step {step.id}: Back button must be enabled on step {step_index}"

        if step.tap_title is not None:
            assert TOUR_TAP_TARGET in by_id, f"Step {step.id} is interactive but missing tap target '{TOUR_TAP_TARGET}'"
            tap_node = by_id[TOUR_TAP_TARGET]
            assert tap_node.get("enabled", False) is True, f"Step {step.id} tap target '{TOUR_TAP_TARGET}' is disabled"
            tap_title = tap_node.get("title") or tap_node.get("description") or ""
            assert (
                step.tap_title == tap_title or step.tap_title in tap_title
            ), f"Step {step.id} tap target label mismatch: expected '{step.tap_title}', got '{tap_title}'"
        else:
            assert (
                TOUR_HIGHLIGHT in by_id or step.target in by_id
            ), f"Step {step.id} missing target highlight '{TOUR_HIGHLIGHT}' or '{step.target}'"

        self.assert_target_frame_if_exposed(step, by_id)

    def assert_target_frame_if_exposed(self, step: TourStepSpec, by_id: Dict[str, Dict[str, Any]]) -> None:
        """Assert that if spotlight target or highlight exposes frame, it has valid positive dimensions."""
        candidate_ids = [TOUR_TAP_TARGET, TOUR_HIGHLIGHT, step.target]
        for candidate_id in candidate_ids:
            if candidate_id in by_id:
                node = by_id[candidate_id]
                frame_status = node.get("frame_status")
                assert frame_status != "nonfinite", (
                    f"Step {step.id} target '{candidate_id}' has nonfinite geometry: frame_status='nonfinite'"
                )
                assert frame_status != "unreadable", (
                    f"Step {step.id} target '{candidate_id}' has unreadable geometry: frame_status='unreadable'"
                )
                frame = node.get("frame")
                if frame is not None and isinstance(frame, dict):
                    w = frame.get("width", 0)
                    h = frame.get("height", 0)
                    x = frame.get("x", 0)
                    y = frame.get("y", 0)
                    assert (
                        isinstance(w, (int, float)) and isinstance(h, (int, float))
                        and isinstance(x, (int, float)) and isinstance(y, (int, float))
                    ), f"Frame values must be numeric: {frame}"
                    assert math.isfinite(w) and math.isfinite(h) and math.isfinite(x) and math.isfinite(y), (
                        f"Frame values must be finite: {frame}"
                    )
                    assert w > 0 and h > 0, (
                        f"Step {step.id} target '{candidate_id}' has non-positive frame dimensions: {frame}"
                    )

    def advance_step(self, step_index: int, step: TourStepSpec) -> None:
        """Advance to next step via interactive tap target or next button. Never falls back on error."""
        is_last = step_index == len(TOUR_STEPS) - 1
        if is_last:
            self.probe.press(TOUR_DONE)
        elif step.tap_title is not None:
            self.probe.press(TOUR_TAP_TARGET)
        else:
            self.probe.press(TOUR_NEXT)

    def back_step(self) -> None:
        """Press the Back button in the tour coach."""
        self.probe.press(TOUR_BACK)

    def return_to_overview(self, current_index: int) -> None:
        """Return from current_index down to step 0 (overview) by pressing Back exactly count times."""
        for idx in range(current_index, 0, -1):
            self.back_step()
            self.wait_for_step(idx - 1, TOUR_STEPS[idx - 1])
            if self.dwell_seconds > 0:
                time.sleep(self.dwell_seconds)
        print(f"PASS: returned to overview from step index {current_index}", flush=True)

    def run_all_17_steps(self) -> None:
        """Walk through all 17 steps in order, verifying state and transitions without early Done dismissal."""
        for index, step in enumerate(TOUR_STEPS):
            self.wait_for_step(index, step)
            if self.dwell_seconds > 0:
                time.sleep(self.dwell_seconds)
            is_last = index == len(TOUR_STEPS) - 1
            if not is_last:
                self.advance_step(index, step)
        print("PASS: all 17 tour steps verified in sequence with valid states and frames", flush=True)

    def run_transition_cycles(self, cycles: int = 3) -> None:
        """Stress-test transitions openMiner -> cooling, cooling -> openCoins with dwell and repeated cycles."""
        idx_open_miner = 2
        idx_cooling = 3
        idx_open_coins = 4

        step_open_miner = TOUR_STEPS[idx_open_miner]
        step_cooling = TOUR_STEPS[idx_cooling]
        step_open_coins = TOUR_STEPS[idx_open_coins]

        # Navigate to openMiner if starting from overview or history
        nodes = self.probe.snapshot()
        by_id = {node.get("id"): node for node in nodes if node.get("id")}
        if f"tour.step.{step_open_miner.id}" not in by_id:
            for cur_idx in range(idx_open_miner):
                self.wait_for_step(cur_idx, TOUR_STEPS[cur_idx])
                self.advance_step(cur_idx, TOUR_STEPS[cur_idx])

        self.wait_for_step(idx_open_miner, step_open_miner)

        for cycle in range(1, cycles + 1):
            # Transition 1: openMiner -> cooling
            self.advance_step(idx_open_miner, step_open_miner)
            self.wait_for_step(idx_cooling, step_cooling)
            if self.dwell_seconds > 0:
                time.sleep(self.dwell_seconds)
            self.assert_step_state(idx_cooling, step_cooling, self.probe.snapshot())

            # Transition 2: cooling -> openCoins
            self.advance_step(idx_cooling, step_cooling)
            self.wait_for_step(idx_open_coins, step_open_coins)
            if self.dwell_seconds > 0:
                time.sleep(self.dwell_seconds)
            self.assert_step_state(idx_open_coins, step_open_coins, self.probe.snapshot())

            # Return back to openMiner for next cycle
            # openCoins -> cooling
            self.back_step()
            self.wait_for_step(idx_cooling, step_cooling)
            if self.dwell_seconds > 0:
                time.sleep(self.dwell_seconds)

            # cooling -> openMiner
            self.back_step()
            self.wait_for_step(idx_open_miner, step_open_miner)
            if self.dwell_seconds > 0:
                time.sleep(self.dwell_seconds)

            print(f"PASS: cycle {cycle}/{cycles} openMiner <-> cooling <-> openCoins completed successfully", flush=True)

        print(f"PASS: repeated {cycles} cycles of openMiner -> cooling and cooling -> openCoins", flush=True)

    def run_optional_controls(self, current_index: int = 0) -> None:
        """Verify Next, Back, Close, and tour dismissal starting from overview."""
        if current_index != 0:
            self.return_to_overview(current_index)

        self.wait_for_step(0, TOUR_STEPS[0])
        self.advance_step(0, TOUR_STEPS[0])
        self.wait_for_step(1, TOUR_STEPS[1])
        self.back_step()
        self.wait_for_step(0, TOUR_STEPS[0])
        self.probe.press(TOUR_CLOSE)

        deadline = time.monotonic() + self.probe.wait_seconds
        while time.monotonic() < deadline:
            nodes = self.probe.snapshot()
            if not any(node.get("id") == TOUR_VIEW for node in nodes):
                print("PASS: tour closed via Close button", flush=True)
                return
            time.sleep(0.2)
        raise AssertionError("Tour did not dismiss after pressing Close")


def run_tour_acceptance(
    probe: NativeMacProbe,
    *,
    full_tour: bool = True,
    cycles: int = 3,
    dwell_seconds: float = 0.2,
    optional_controls: bool = False,
    work_dir: Optional[Path] = None,
    expected_app_path: Optional[Path] = None,
    expected_lstart: Optional[str] = None,
) -> None:
    """Execute complete bounded tour acceptance with automated sample capture on failure."""
    checks = TourChecks(probe, dwell_seconds=dwell_seconds)
    current_index = 0
    try:
        if full_tour:
            checks.run_all_17_steps()
            current_index = 16
        if cycles > 0:
            if current_index != 0:
                checks.return_to_overview(current_index)
                current_index = 0
            checks.run_transition_cycles(cycles=cycles)
            current_index = 2
        if optional_controls:
            checks.run_optional_controls(current_index=current_index)
            current_index = -1
    except Exception as exc:
        if work_dir is not None:
            sample_path = preserve_failure_sample(
                probe.pid,
                work_dir,
                str(exc),
                expected_app_path=expected_app_path,
                expected_lstart=expected_lstart,
            )
            if sample_path:
                print(f"DIAGNOSTIC: Failure sample preserved at {sample_path}", file=sys.stderr)
        raise


def main(argv=None):
    parser = argparse.ArgumentParser(description=__doc__)
    source_group = parser.add_mutually_exclusive_group(required=True)
    source_group.add_argument("--app", type=Path, help="Launch canonical app bundle with --show-feature-tour")
    source_group.add_argument("--pid", type=int, help="Attach to running PID without launching or killing")

    parser.add_argument("--work-dir", required=True, type=Path, help="Working directory for artifacts")
    parser.add_argument("--cycles", type=int, default=3, help="Transition repeat cycles between miner and coins")
    parser.add_argument("--dwell", type=float, default=0.2, help="Dwell time in seconds after transitions")
    parser.add_argument("--full-tour", action="store_true", default=True, help="Verify all 17 steps in sequence")
    parser.add_argument("--optional-controls", action="store_true", help="Test Back and Close dismissal")
    parser.add_argument("--wait-seconds", type=float, default=12.0, help="Wait timeout per AX predicate")

    args = parser.parse_args(argv)

    validate_cli_bounds(
        cycles=args.cycles,
        dwell=args.dwell,
        wait_seconds=args.wait_seconds,
        full_tour=args.full_tour,
        optional_controls=args.optional_controls,
    )

    work = args.work_dir.resolve()
    work.mkdir(parents=True, exist_ok=True)

    probe = NativeMacTourProbe.connect_tour(
        app=args.app,
        pid=args.pid,
        work=work,
        wait_seconds=args.wait_seconds,
    )
    print(f"Connected tour probe to PID {probe.pid} (owned={probe.owned})", flush=True)

    try:
        run_tour_acceptance(
            probe,
            full_tour=args.full_tour,
            cycles=args.cycles,
            dwell_seconds=args.dwell,
            optional_controls=args.optional_controls,
            work_dir=work,
            expected_app_path=args.app,
            expected_lstart=probe.expected_lstart,
        )
    finally:
        probe.close_owned()


if __name__ == "__main__":
    main()
