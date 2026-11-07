"""Exercise source guardrails with real repository inputs and isolated broken seams.

These checks never launch an app or touch miner settings. Mutations are confined
strictly to TemporaryDirectory fixtures, not the working repository.
"""
import contextlib
import importlib.util
import io
from pathlib import Path
import runpy
import tempfile
import unittest
from unittest.mock import patch


ROOT = Path(__file__).resolve().parents[1]


def load_guard(name, filename):
    specification = importlib.util.spec_from_file_location(name, ROOT / "Scripts" / filename)
    module = importlib.util.module_from_spec(specification)
    specification.loader.exec_module(module)
    return module


NAVIGATION = load_guard("navigation_guard_under_test", "check-native-navigation.py")
SHELLS = load_guard("page_shell_guard_under_test", "check-shared-page-shells.py")
NAVIGATION_FILES = (
    "App/Features/Dashboard/DashboardView+WideLayout.swift",
    "App/Features/Dashboard/DashboardView.swift",
    "App/Design/FleetDesktopBranding.swift",
    "App/Design/FleetHeaderTitle.swift",
    "App/Features/Miner/MinerDetailView.swift",
    "App/Features/Miner/MinerDetailView+QuickActions.swift",
)


class NativeNavigationGuardTests(unittest.TestCase):
    def setUp(self):
        temporary = tempfile.TemporaryDirectory()
        self.addCleanup(temporary.cleanup)
        self.root = Path(temporary.name)
        for relative in NAVIGATION_FILES:
            destination = self.root / relative
            destination.parent.mkdir(parents=True, exist_ok=True)
            destination.write_text((ROOT / relative).read_text())

    def replace(self, relative, old, new):
        path = self.root / relative
        source = path.read_text()
        self.assertIn(old, source, "The fixture mutation must target a real integration seam")
        path.write_text(source.replace(old, new))

    def test_actual_repository_satisfies_navigation_contract(self):
        self.assertEqual(NAVIGATION.check(ROOT), [])

    def test_isolated_copy_satisfies_the_same_contract(self):
        self.assertEqual(NAVIGATION.check(self.root), [])

    def test_missing_sidebar_surface_is_detected(self):
        self.replace(NAVIGATION_FILES[0], ".fleetMacSidebarSurface(fill: FleetTheme.sidebarSurface)", "")
        self.assertEqual(len(NAVIGATION.check_dashboard(self.root)), 1)

    def test_toolbar_style_override_is_detected(self):
        self.replace(NAVIGATION_FILES[1], ".fleetToolbarMenu()",
                     ".fleetDesignedMenu()\n                .fleetToolbarMenu()")
        self.assertTrue(any("inner plain style" in error for error in NAVIGATION.check_dashboard(self.root)))

    def test_missing_shared_or_principal_toolbar_brands_are_detected(self):
        self.replace(NAVIGATION_FILES[1], "FleetHeaderTitle()", "MissingHeaderTitle()")
        self.replace(NAVIGATION_FILES[1], "FleetMacToolbarBrand()", "MissingToolbarBrand()")
        self.assertEqual(len(NAVIGATION.check_dashboard(self.root)), 2)

    def test_missing_page_branding_contracts_are_detected(self):
        self.replace(NAVIGATION_FILES[2], "placement: .principal", "placement: .automatic")
        self.replace(NAVIGATION_FILES[2], "FleetHeaderArtwork()", "MissingArtwork()")
        self.replace(NAVIGATION_FILES[2], "includesPrincipalBrand", "duplicateBrand")
        self.assertEqual(len(NAVIGATION.check_branding(self.root)), 3)

    def test_missing_shared_wordmark_returns_a_clear_error(self):
        (self.root / NAVIGATION_FILES[3]).unlink()
        self.assertTrue(any("Missing shared original" in error for error in NAVIGATION.check_branding(self.root)))

    def test_wordmark_contract_and_replacement_typeface_are_detected(self):
        (self.root / NAVIGATION_FILES[3]).write_text("Text(\"Replacement\") .font(.system(size: 25))")
        self.assertEqual(len(NAVIGATION.check_branding(self.root)), 5)

    def test_miner_action_and_destination_seams_are_both_required(self):
        self.replace(NAVIGATION_FILES[4], ".navigationDestination(for: MinerEndpoint.self)", "")
        self.replace(NAVIGATION_FILES[5], "NavigationLink(value: endpoint)", "MissingNavigationLink()")
        self.assertEqual(len(NAVIGATION.check_miner_detail(self.root)), 2)

    def test_real_command_line_guard_runs_without_launching_an_app(self):
        output = io.StringIO()
        with contextlib.redirect_stdout(output):
            runpy.run_path(str(ROOT / "Scripts/check-native-navigation.py"), run_name="__main__")
        self.assertIn("guard passed", output.getvalue())


class SharedPageShellGuardTests(unittest.TestCase):
    def setUp(self):
        temporary = tempfile.TemporaryDirectory()
        self.addCleanup(temporary.cleanup)
        self.root = Path(temporary.name)
        root_patch = patch.object(SHELLS, "ROOT", self.root)
        root_patch.start()
        self.addCleanup(root_patch.stop)
        self.layout = self.root / "App/Design/FleetAdaptiveLayout.swift"
        self.layout.parent.mkdir(parents=True)
        self.layout.write_text(
            "private struct FleetPageContainerModifier: ViewModifier {\n"
            " .padding(FleetLayout.pagePadding)\n .fleetFont(.body)\n}\n"
            "private struct FleetMacScreenSizingModifier: ViewModifier {}\n"
        )
        for relative, boundary in SHELLS.PAGE_ROOTS.items():
            path = self.root / "App/Features" / relative
            path.parent.mkdir(parents=True, exist_ok=True)
            path.write_text(boundary + " content }\n")

    def feature(self, filename, source):
        path = self.root / "App/Features" / filename
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_text(source)
        return path

    def test_real_shell_source_guard_and_its_self_test_pass(self):
        with patch.object(SHELLS, "ROOT", ROOT):
            SHELLS.self_test()
            self.assertEqual(SHELLS.violations(), [])

    def test_complete_shared_boundary_fixture_passes(self):
        self.assertEqual(SHELLS.violations(), [])

    def test_raw_form_and_list_are_reported_with_file_and_line(self):
        path = self.feature("Example/Example.swift", "struct Example {\n List { content }\n Form { content }\n}\n")
        errors = SHELLS.feature_file_violations(path)
        self.assertEqual(len(errors), 2)
        self.assertIn("Example/Example.swift:2:", errors[0])
        self.assertIn("Example/Example.swift:3:", errors[1])

    def test_only_sidebar_list_owns_the_raw_container_exception(self):
        source = (
            "private struct FleetSidebarList<T> {\n List { content }\n}\n"
            "private struct FleetSidebarSearchModifier: ViewModifier {}\n"
            "List { unrelatedPage }\n"
        )
        path = self.feature("Dashboard/DashboardView+WideLayout.swift", source)
        self.assertEqual(len(SHELLS.feature_file_violations(path)), 1)
        self.assertEqual(len(SHELLS.feature_file_violations(self.feature("Other.swift", source))), 2)

    def test_sidebar_bounds_and_missing_or_reversed_markers(self):
        source = "private struct FleetSidebarList<T> {} private struct FleetSidebarSearchModifier: M {}"
        end = source.index("private struct FleetSidebarSearchModifier:")
        self.assertTrue(SHELLS.sidebar_owns_offset(source, 0))
        self.assertTrue(SHELLS.sidebar_owns_offset(source, end - 1))
        self.assertFalse(SHELLS.sidebar_owns_offset(source, -1))
        self.assertFalse(SHELLS.sidebar_owns_offset(source, end))
        self.assertFalse(SHELLS.sidebar_owns_offset("no markers", 0))
        self.assertFalse(SHELLS.sidebar_owns_offset("private struct FleetSidebarList<T> {}", 1))
        reversed_markers = "private struct FleetSidebarSearchModifier: M {} private struct FleetSidebarList<T> {}"
        self.assertFalse(SHELLS.sidebar_owns_offset(reversed_markers, len(reversed_markers) - 1))

    def test_private_readable_form_adapter_is_rejected(self):
        path = self.feature("Example.swift", "content.fleetReadableForm()")
        self.assertEqual(len(SHELLS.feature_file_violations(path)), 1)

    def test_duplicate_padding_missing_font_and_transformations_are_rejected(self):
        source = self.layout.read_text().replace(".fleetFont(.body)", "")
        source = source.replace(".padding(FleetLayout.pagePadding)",
                                ".padding(FleetLayout.pagePadding) .padding(FleetLayout.pagePadding)")
        self.layout.write_text(source.replace(" ViewModifier {", " ViewModifier { .scaleEffect(1) .transformEffect(x) .dynamicTypeSize(x)", 1))
        self.assertEqual(len(SHELLS.shell_violations()), 5)

    def test_missing_feature_boundary_is_detected(self):
        relative = next(iter(SHELLS.PAGE_ROOTS))
        (self.root / "App/Features" / relative).write_text("No shared page boundary")
        self.assertEqual(len(SHELLS.violations()), 1)

    def test_real_command_line_guard_runs_without_launching_an_app(self):
        output = io.StringIO()
        with contextlib.redirect_stdout(output):
            runpy.run_path(str(ROOT / "Scripts/check-shared-page-shells.py"), run_name="__main__")
        self.assertIn("guard passed", output.getvalue())


if __name__ == "__main__":
    unittest.main()
