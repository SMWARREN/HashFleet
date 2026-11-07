#!/usr/bin/env python3
"""Supplement runtime layout tests with a guard against private page shells.

Native page content must use fleetPageContainer, directly or through the shared
FleetSettingsList/Form. The sidebar is navigation, not a detail page. This check
never changes source and does not substitute for actual-window acceptance.
"""
from pathlib import Path
import re
import sys

ROOT = Path(__file__).resolve().parents[1]
RAW_CONTAINER = re.compile(r"^\s*(?:Form|List)\s*[({]", re.MULTILINE)
PAGE_CONTAINER = ".fleetPageContainer("
SETTINGS_LIST = "FleetSettingsList {"
SETTINGS_FORM = "FleetSettingsForm {"
PAGE_ROOTS = {
    "Dashboard/DashboardView+Sections.swift": PAGE_CONTAINER,
    "Miner/MinerDetailView.swift": PAGE_CONTAINER,
    "Network/NetworkInsightsView.swift": PAGE_CONTAINER,
    "Network/PoolStatsHubView.swift": PAGE_CONTAINER,
    "Network/CKPoolLookupView.swift": PAGE_CONTAINER,
    "Backup/FleetBackupView.swift": PAGE_CONTAINER,
    "Energy/FleetEnergyView.swift": SETTINGS_FORM,
    "Reports/FleetReportView.swift": SETTINGS_LIST,
    "Achievements/MiningAchievementsView.swift": SETTINGS_LIST,
    "About/AboutView.swift": SETTINGS_LIST,
    "Settings/MonitoringSettingsView.swift": SETTINGS_LIST,
    "Settings/FleetPreferencesView.swift": SETTINGS_FORM,
}


def sidebar_owns_offset(source: str, offset: int) -> bool:
    start = source.find("private struct FleetSidebarList<")
    end = source.find("private struct FleetSidebarSearchModifier:", start)
    return start >= 0 and end > start and start <= offset < end


def feature_file_violations(path: Path) -> list[str]:
    errors = []
    source = path.read_text()
    for match in RAW_CONTAINER.finditer(source):
        if path.name == "DashboardView+WideLayout.swift" and sidebar_owns_offset(source, match.start()):
            continue
        line = source.count("\n", 0, match.start()) + 1
        errors.append(f"{path.relative_to(ROOT)}:{line}: raw page container bypasses the common shell")
    if ".fleetReadableForm(" in source:
        errors.append(f"{path.relative_to(ROOT)}: use FleetSettingsList/Form, not a second form page adapter")
    return errors


def shell_violations() -> list[str]:
    errors = []
    layout = (ROOT / "App/Design/FleetAdaptiveLayout.swift").read_text()
    shell = layout.split("private struct FleetPageContainerModifier:", 1)[1].split(
        "private struct FleetMacScreenSizingModifier:", 1
    )[0]
    if shell.count(".padding(FleetLayout.pagePadding)") != 1:
        errors.append("Common shell must apply the shared outer padding exactly once")
    if ".fleetFont(.body)" not in shell:
        errors.append("Common shell must inherit the shared body text role")
    errors.extend(
        f"Common page shell must not use {forbidden}"
        for forbidden in [".scaleEffect(", ".transformEffect(", ".dynamicTypeSize("]
        if forbidden in shell
    )
    return errors


def violations() -> list[str]:
    features = ROOT / "App/Features"
    errors = []
    for path in sorted(features.rglob("*.swift")):
        errors.extend(feature_file_violations(path))
    errors.extend(
        f"App/Features/{relative}: shared page boundary is missing"
        for relative, boundary in PAGE_ROOTS.items()
        if boundary not in (features / relative).read_text()
    )
    errors.extend(shell_violations())
    return errors


def self_test() -> None:
    assert RAW_CONTAINER.search("    Form { Text(\"Example\") }")
    assert RAW_CONTAINER.search("    List(selection: $selection) { content }")
    assert not RAW_CONTAINER.search("    FleetSettingsForm { content }")
    assert not RAW_CONTAINER.search("    FleetSettingsList { content }")
    source = "private struct FleetSidebarList<T> {\n List { content }\n}\nprivate struct FleetSidebarSearchModifier: ViewModifier {}"
    assert sidebar_owns_offset(source, source.index(" List"))
    assert not sidebar_owns_offset(source, len(source) - 1)


if __name__ == "__main__":
    self_test()
    errors = violations()
    for error in errors:
        print(error, file=sys.stderr)
    if errors:
        raise SystemExit(1)
    print("Shared page-shell source guard passed. Runtime layout acceptance is separate.")
