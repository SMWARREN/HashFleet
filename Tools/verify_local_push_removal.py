#!/usr/bin/env python3
"""Read-only Local Push removal guard. Builds and signed-device acceptance are separate."""

import argparse
import json
import plistlib
import re
import subprocess
from pathlib import Path

CONFIGURATIONS = {
    "Debug": "development",
    "DebugNoAppPush": "development",
    "Release": "production",
    "ReleaseNoAppPush": "production",
}
APP_GROUP = "group.app.hashfleet.shared"
REJECTED_SYMBOLS = re.compile(
    r"\b(?:FleetLocalPush|NEAppPushProvider|NEAppPushManager|NetworkExtension|"
    r"APP_PUSH_PROVIDER_ENABLED|PushProvider)\b"
)
REJECTED_ENTITLEMENTS = {
    "com.apple.developer.networking.networkextension",
    "com.apple.developer.networking.wifi-info",
}
REJECTED_UI = (
    "preferences.localPush", "matchedSSIDs", "backgroundAlertsSection",
    "toggleLocalPush", "removeSSID", "CLLocationManager",
)


def symbol_violations(text, label):
    return [f"{label}: rejected symbol {symbol}" for symbol in sorted(set(REJECTED_SYMBOLS.findall(text)))]


def entitlement_violations(value, label, app=False):
    errors = []
    if any(key in value for key in REJECTED_ENTITLEMENTS):
        errors.append(f"{label}: rejected Network Extension or Wi-Fi entitlement")
    if value.get("com.apple.security.application-groups") != [APP_GROUP]:
        errors.append(f"{label}: existing App Group mismatch")
    if app and value.get("aps-environment") != "$(APS_ENVIRONMENT)":
        errors.append(f"{label}: standard APNs environment must use the configuration setting")
    return errors


def target_settings_violations(settings, configuration, target):
    errors = []
    prefix = f"{configuration}/{target}"
    if settings.get("APS_ENVIRONMENT") != CONFIGURATIONS[configuration]:
        errors.append(f"{prefix}: incorrect resolved APNs environment")
    errors.extend(symbol_violations(str(settings.get("SWIFT_ACTIVE_COMPILATION_CONDITIONS", "")), prefix))
    expected_path = (
        "App/Resources/HashFleetNoAppPush.entitlements" if target == "HashFleet"
        else "NotificationService/Resources/NotificationService.entitlements"
    )
    if settings.get("CODE_SIGN_ENTITLEMENTS") != expected_path:
        errors.append(f"{prefix}: incorrect resolved entitlement template")
    expected_id = "app.hashfleet" + (".notification-service" if target != "HashFleet" else "")
    if settings.get("PRODUCT_BUNDLE_IDENTIFIER") != expected_id:
        errors.append(f"{prefix}: incorrect bundle identifier")
    return errors


def is_settings_capture(rows):
    return isinstance(rows, list) and all(
        isinstance(row, dict) and isinstance(row.get("buildSettings"), dict) for row in rows
    )


def settings_violations(rows, configuration):
    if not is_settings_capture(rows):
        return [f"{configuration}: malformed resolved build-settings capture"]
    errors = []
    for target in ("HashFleet", "HashFleetNotificationService"):
        matches = [row.get("buildSettings", {}) for row in rows if row.get("target") == target]
        if len(matches) != 1:
            errors.append(f"{configuration}: expected exactly one {target} settings row")
            continue
        errors.extend(target_settings_violations(matches[0], configuration, target))
    return errors


def load_plist(path):
    with path.open("rb") as stream:
        return plistlib.load(stream)


def legacy_source_violations(root):
    errors = []
    coordinator = root / "App/Store/FleetLocalPush.swift"
    if coordinator.exists() or coordinator.is_symlink():
        errors.append("App/Store/FleetLocalPush.swift: rejected source still exists on disk")
    provider = root / "PushProvider"
    # Git deletion leaves empty folders on disk. They contain no shippable code.
    if provider.is_file() or provider.is_symlink() or any(
        item.is_file() or item.is_symlink() for item in provider.rglob("*")
    ):
        errors.append("PushProvider: rejected source or resource still exists on disk")
    return errors


def source_tree_violations(root):
    errors = []
    for directory in ("App", "Shared", "Sources", "Widgets", "MacMenuBar", "NotificationService"):
        for source in sorted((root / directory).rglob("*.swift")):
            errors.extend(symbol_violations(source.read_text(), str(source.relative_to(root))))
    errors.extend(
        f"{source.relative_to(root)}: legacy device mirror restored"
        for source in (root / "App").rglob("*.swift")
        if re.search(r"\bFleetSharedStore\s*\.\s*writeDevices\s*\(", source.read_text())
    )
    preferences = (root / "App/Features/Settings/FleetPreferencesView.swift").read_text()
    errors.extend(f"FleetPreferencesView.swift: rejected setup UI {token}" for token in REJECTED_UI if token in preferences)
    persistence = (root / "App/Store/FleetStore+Persistence.swift").read_text()
    if "JSONEncoder().encode(devices)" not in persistence or "defaults.set(encoded, forKey: Self.storageKey)" not in persistence:
        errors.append("FleetStore+Persistence.swift: ordinary local fleet persistence missing")
    return errors


def entitlement_and_plist_violations(root):
    errors = []
    for relative in ("App/Resources/HashFleet.entitlements", "App/Resources/HashFleetNoAppPush.entitlements",
                     "NotificationService/Resources/NotificationService.entitlements"):
        errors.extend(entitlement_violations(load_plist(root / relative), relative, app=relative.startswith("App/")))
    # Inspect shipping templates without traversing build outputs or cached packages.
    for directory in ("App", "Widgets", "MacMenuBar", "NotificationService"):
        errors.extend(
            f"{path.relative_to(root)}: rejected entitlement remains"
            for path in sorted((root / directory).rglob("*.entitlements"))
            if REJECTED_ENTITLEMENTS.intersection(load_plist(path))
        )
    app_info = load_plist(root / "App/Resources/Info.plist")
    if any(key.startswith("NSLocation") for key in app_info):
        errors.append("App Info.plist: rejected location-permission declaration remains")
    if not app_info.get("NSLocalNetworkUsageDescription"):
        errors.append("App Info.plist: required existing local-network explanation missing")
    extension = load_plist(root / "NotificationService/Resources/Info.plist")["NSExtension"]
    if extension.get("NSExtensionPointIdentifier") != "com.apple.usernotifications.service":
        errors.append("NotificationService: not the standard notification service extension point")
    return errors


def project_violations(root):
    errors = []
    project_path = root / "HashFleet.xcodeproj/project.pbxproj"
    for relative in ("project.yml", "HashFleet.xcodeproj/project.pbxproj"):
        errors.extend(symbol_violations((root / relative).read_text(), relative))
    project = json.loads(subprocess.check_output(["plutil", "-convert", "json", "-o", "-", str(project_path)]))
    objects = project["objects"]
    names = {value.get("name") for value in objects.values() if value.get("isa") == "PBXNativeTarget"}
    if not {"HashFleet", "HashFleetWidgets", "HashFleetNotificationService"}.issubset(names):
        errors.append("Generated project: expected app and preserved/new extension targets missing")
    return errors


def repository_violations(root):
    return (
        legacy_source_violations(root)
        + source_tree_violations(root)
        + entitlement_and_plist_violations(root)
        + project_violations(root)
    )


def bundle_violations(bundle):
    errors = []
    info = load_plist(bundle / "Info.plist")
    if info.get("CFBundleIdentifier") != "app.hashfleet":
        errors.append(f"{bundle.name}: wrong app bundle identifier")
    plugins = bundle / "PlugIns"
    actual = {item.name for item in plugins.iterdir() if item.suffix == ".appex"}
    expected = {"HashFleetNotificationService.appex", "HashFleetWidgets.appex"}
    if actual != expected:
        errors.append(f"{bundle.name}: embedded extension set differs from standard service and existing widgets")
    for component in (bundle, *sorted(plugins.glob("*.appex"))):
        component_info = load_plist(component / "Info.plist")
        if any(key.startswith("NSLocation") for key in component_info):
            errors.append(f"{component.name}: rejected location permission packaged")
        if component.name == "HashFleetNotificationService.appex":
            if component_info.get("NSExtension", {}).get("NSExtensionPointIdentifier") != "com.apple.usernotifications.service":
                errors.append(f"{component.name}: wrong embedded extension point")
        executable = component / component_info["CFBundleExecutable"]
        # Debug builds may put imports in a dylib rather than the executable stub.
        for image in (executable, *sorted(component.glob("*.dylib"))):
            linked = subprocess.check_output(["otool", "-L", str(image)], text=True)
            if "NetworkExtension.framework" in linked:
                errors.append(f"{component.name}/{image.name}: links rejected NetworkExtension framework")
    return errors


def main(argv=None):
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--root", type=Path, default=Path(__file__).resolve().parents[1])
    parser.add_argument("--build-settings-dir", type=Path,
                        help="Directory containing settings-CONFIG.json and settings-service-CONFIG.json for all four configurations")
    parser.add_argument("--app-bundle", type=Path, action="append", default=[], help="Fresh unsigned app bundle to inspect, repeatable")
    args = parser.parse_args(argv)
    try:
        errors = repository_violations(args.root.resolve())
        if args.build_settings_dir:
            for configuration in CONFIGURATIONS:
                app_rows = json.loads((args.build_settings_dir / f"settings-{configuration}.json").read_text())
                service_rows = json.loads((args.build_settings_dir / f"settings-service-{configuration}.json").read_text())
                if not isinstance(app_rows, list) or not isinstance(service_rows, list):
                    raise ValueError("Expected target settings arrays")
                errors.extend(settings_violations(app_rows + service_rows, configuration))
        for bundle in args.app_bundle:
            errors.extend(bundle_violations(bundle))
    except (OSError, ValueError, KeyError, subprocess.CalledProcessError) as error:
        print(f"FAIL: validation input or tool failed ({type(error).__name__})")
        return 1
    if errors:
        for error in errors:
            print("FAIL:", error)
        return 1
    print("PASS: rejected Local Push source, UI, target and mirror absent; normal storage and standard APNs templates preserved.")
    print(f"PASS: {len(CONFIGURATIONS) if args.build_settings_dir else 0} resolved configuration captures and {len(args.app_bundle)} built app bundles inspected.")
    print("Scope: read-only configuration/package guard, not compilation, signing, provisioning, delivery or LAN-runtime proof.")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
