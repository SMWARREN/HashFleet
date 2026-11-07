import copy
import io
import json
import plistlib
import tempfile
import unittest
from contextlib import redirect_stdout
from pathlib import Path
from unittest.mock import patch

if __package__:
    from . import verify_local_push_removal as guard
else:
    import verify_local_push_removal as guard


class LocalPushRemovalGuardTests(unittest.TestCase):
    def test_empty_historical_directories_are_not_shipping_provider_code(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            (root / "PushProvider/Resources").mkdir(parents=True)
            self.assertEqual(guard.legacy_source_violations(root), [])

    def test_remaining_ignored_or_untracked_legacy_source_or_resource_is_rejected(self):
        for name in ("App/Store/FleetLocalPush.swift", "PushProvider/PushProvider.swift",
                     "PushProvider/Resources/PushProvider.entitlements"):
            with self.subTest(name=name), tempfile.TemporaryDirectory() as directory:
                root = Path(directory)
                path = root / name
                path.parent.mkdir(parents=True)
                path.write_text("rejected fixture")
                self.assertTrue(guard.legacy_source_violations(root))

    def test_dangling_legacy_symlink_is_rejected(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            (root / "PushProvider").symlink_to(root / "missing", target_is_directory=True)
            self.assertTrue(guard.legacy_source_violations(root))

    def valid_settings(self, configuration):
        return [
            {"target": target, "buildSettings": {
                "APS_ENVIRONMENT": guard.CONFIGURATIONS[configuration],
                "SWIFT_ACTIVE_COMPILATION_CONDITIONS": "DEBUG" if configuration.startswith("Debug") else "",
                "CODE_SIGN_ENTITLEMENTS": path,
                "PRODUCT_BUNDLE_IDENTIFIER": bundle_id,
            }}
            for target, path, bundle_id in [
                ("HashFleet", "App/Resources/HashFleetNoAppPush.entitlements", "app.hashfleet"),
                ("HashFleetNotificationService", "NotificationService/Resources/NotificationService.entitlements",
                 "app.hashfleet.notification-service"),
            ]
        ]

    def test_every_rejected_symbol_is_detected(self):
        for symbol in ("FleetLocalPush", "NEAppPushProvider", "NEAppPushManager", "NetworkExtension",
                       "APP_PUSH_PROVIDER_ENABLED", "PushProvider"):
            with self.subTest(symbol=symbol):
                self.assertTrue(guard.symbol_violations(f"import {symbol}", "fixture"))

    def test_ordinary_notification_api_diagnostics_and_legacy_shared_api_are_not_rejected(self):
        text = "UNNotificationServiceExtension wifiSSID Wi-Fi SSID FleetSharedStore.writeDevices FleetRemotePushCoordinator"
        self.assertEqual(guard.symbol_violations(text, "fixture"), [])

    def test_standard_entitlement_and_existing_group_are_required(self):
        good = {"aps-environment": "$(APS_ENVIRONMENT)", "com.apple.security.application-groups": [guard.APP_GROUP]}
        self.assertEqual(guard.entitlement_violations(good, "app", app=True), [])
        for bad in ({}, {**good, "aps-environment": "development"},
                    {**good, "com.apple.security.application-groups": ["wrong.group"]}):
            self.assertTrue(guard.entitlement_violations(bad, "app", app=True))

    def test_rejected_entitlements_are_detected_for_app_and_extension(self):
        good = {"aps-environment": "$(APS_ENVIRONMENT)", "com.apple.security.application-groups": [guard.APP_GROUP]}
        for key in guard.REJECTED_ENTITLEMENTS:
            for app in (False, True):
                with self.subTest(key=key, app=app):
                    self.assertTrue(guard.entitlement_violations({**good, key: ["app-push-provider"]}, "fixture", app=app))

    def test_all_four_resolved_environment_mappings_are_checked(self):
        for configuration in guard.CONFIGURATIONS:
            rows = self.valid_settings(configuration)
            self.assertEqual(guard.settings_violations(rows, configuration), [])
            rows[0]["buildSettings"]["APS_ENVIRONMENT"] = "production" if configuration.startswith("Debug") else "development"
            self.assertTrue(guard.settings_violations(rows, configuration))

    def test_resolved_provider_flag_wrong_identifier_and_template_fail(self):
        for key, value in (("SWIFT_ACTIVE_COMPILATION_CONDITIONS", "DEBUG APP_PUSH_PROVIDER_ENABLED"),
                           ("CODE_SIGN_ENTITLEMENTS", "PushProvider/PushProvider.entitlements"),
                           ("PRODUCT_BUNDLE_IDENTIFIER", "wrong.bundle")):
            rows = self.valid_settings("Debug")
            rows[0]["buildSettings"][key] = value
            self.assertTrue(guard.settings_violations(rows, "Debug"), key)

    def test_missing_and_duplicate_target_settings_fail_closed(self):
        rows = self.valid_settings("Release")
        self.assertTrue(guard.settings_violations(rows[:1], "Release"))
        self.assertTrue(guard.settings_violations(rows + [copy.deepcopy(rows[0])], "Release"))

    def test_malformed_settings_capture_is_not_a_pass(self):
        for rows in (None, {}, ["invalid"], [{"target": "HashFleet", "buildSettings": []}]):
            self.assertTrue(guard.settings_violations(rows, "Debug"))

    @patch.object(guard, "repository_violations", return_value=[])
    def test_cli_requires_explicit_app_and_extension_captures(self, _):
        for status in ("complete", "missing_service", "malformed_app"):
            with self.subTest(status=status), tempfile.TemporaryDirectory() as directory:
                root = Path(directory)
                for configuration in guard.CONFIGURATIONS:
                    rows = self.valid_settings(configuration)
                    app_rows = {} if status == "malformed_app" else rows[:1]
                    (root / f"settings-{configuration}.json").write_text(json.dumps(app_rows))
                    if status != "missing_service":
                        (root / f"settings-service-{configuration}.json").write_text(json.dumps(rows[1:]))
                out = io.StringIO()
                with redirect_stdout(out):
                    result = guard.main(["--root", directory, "--build-settings-dir", directory])
                self.assertEqual(result, 0 if status == "complete" else 1)
                self.assertIn("4 resolved configuration captures" if status == "complete" else "FAIL:", out.getvalue())

    def create_bundle(self, root):
        bundle = root / "HashFleet.app"
        self.write_component(bundle, "app.hashfleet")
        for name, point, identifier in (
            ("HashFleetNotificationService", "com.apple.usernotifications.service", "app.hashfleet.notification-service"),
            ("HashFleetWidgets", "com.apple.widgetkit-extension", "app.hashfleet.widgets"),
        ):
            self.write_component(bundle / "PlugIns" / f"{name}.appex", identifier, point)
        return bundle

    def write_component(self, path, identifier, point=None):
        path.mkdir(parents=True, exist_ok=True)
        info = {"CFBundleIdentifier": identifier, "CFBundleExecutable": path.stem}
        if point:
            info["NSExtension"] = {"NSExtensionPointIdentifier": point}
        (path / "Info.plist").write_bytes(plistlib.dumps(info))
        (path / path.stem).write_bytes(b"fixture, not executable")

    @patch.object(guard.subprocess, "check_output", return_value="/System/Library/Frameworks/UserNotifications.framework/UserNotifications")
    def test_standard_packaged_service_and_preserved_widgets_pass(self, _):
        with tempfile.TemporaryDirectory() as directory:
            self.assertEqual(guard.bundle_violations(self.create_bundle(Path(directory))), [])

    @patch.object(guard.subprocess, "check_output", return_value="fixture")
    def test_extra_legacy_provider_bundle_is_rejected(self, _):
        with tempfile.TemporaryDirectory() as directory:
            bundle = self.create_bundle(Path(directory))
            self.write_component(bundle / "PlugIns" / "PushProvider.appex", "app.hashfleet.push-provider", "com.apple.networkextension.app-push")
            self.assertTrue(guard.bundle_violations(bundle))

    @patch.object(guard.subprocess, "check_output", return_value="fixture")
    def test_wrong_service_extension_point_and_location_permission_fail(self, _):
        with tempfile.TemporaryDirectory() as directory:
            bundle = self.create_bundle(Path(directory))
            info_path = bundle / "PlugIns/HashFleetNotificationService.appex/Info.plist"
            info = guard.load_plist(info_path)
            info["NSExtension"]["NSExtensionPointIdentifier"] = "com.apple.networkextension.app-push"
            info["NSLocationWhenInUseUsageDescription"] = "obsolete"
            info_path.write_bytes(plistlib.dumps(info))
            self.assertEqual(len(guard.bundle_violations(bundle)), 2)

    def test_debug_dylib_cannot_hide_rejected_framework_link(self):
        with tempfile.TemporaryDirectory() as directory:
            bundle = self.create_bundle(Path(directory))
            (bundle / "HashFleet.debug.dylib").write_bytes(b"fixture")
            def dependencies(args, **kwargs):
                return "NetworkExtension.framework" if args[-1].endswith(".debug.dylib") else "UserNotifications.framework"
            with patch.object(guard.subprocess, "check_output", side_effect=dependencies):
                errors = guard.bundle_violations(bundle)
            self.assertEqual(len(errors), 1)
            self.assertIn("HashFleet.debug.dylib", errors[0])

    def test_missing_input_is_failure_not_source_only_pass(self):
        with tempfile.TemporaryDirectory() as directory:
            out = io.StringIO()
            with redirect_stdout(out):
                result = guard.main(["--root", directory, "--build-settings-dir", directory])
            self.assertEqual(result, 1)
            self.assertIn("FAIL:", out.getvalue())
            self.assertNotIn("PASS:", out.getvalue())


if __name__ == "__main__":
    unittest.main()
