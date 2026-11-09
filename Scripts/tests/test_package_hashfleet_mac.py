#!/usr/bin/env python3
"""Offline tests of native macOS packaging and transactional installation scripts."""
import os
from pathlib import Path
import shutil
import subprocess
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[2]


class NativeMacPackagingTests(unittest.TestCase):
    def setUp(self):
        scratch = ROOT / ".build" / "native-mac-package-tests"
        scratch.mkdir(parents=True, exist_ok=True)
        self.temp = tempfile.TemporaryDirectory(dir=scratch)
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)
        self.scripts = self.root / "Scripts"
        (self.scripts / "tests").mkdir(parents=True)
        for name in ("package-hashfleet-mac.sh", "install-hashfleet-mac.sh", "validate-native-mac-app.sh", "hash-fleet-menu-bar.sh"):
            shutil.copy2(ROOT / "Scripts" / name, self.scripts / name)
        self.tools = self.root / "tools"
        self.tools.mkdir()
        self.env = {k: v for k, v in os.environ.items() if not k.startswith("HASH_FLEET_")}
        self.env.update(PATH=f"{self.tools}:/usr/bin:/bin:/usr/sbin:/sbin", FIXTURE_ROOT=str(self.root))
        self.write_tool("PlistBuddy", '''#!/bin/bash
set -euo pipefail
key="${2##*:}"
value="$(awk -F= -v key="$key" '$1 == key { print substr($0, index($0, "=") + 1); exit }' "$3")"
[[ -n "$value" ]] || exit 1
printf '%s\\n' "$value"
''')
        self.write_tool("file", '''#!/bin/bash
printf 'Mach-O 64-bit executable arm64\\n'
''')
        self.write_tool("otool", '''#!/bin/bash
cat <<'OUT'
Load command 0
      cmd LC_BUILD_VERSION
 platform 1
OUT
''')
        self.write_tool("codesign", '''#!/bin/bash
printf '%s\\n' "$*" >> "$FIXTURE_ROOT/codesign-log"
exit 0
''')
        self.write_tool("ditto", '''#!/bin/bash
set -euo pipefail
if [[ "$1" == -c ]]; then
  for arg in "$@"; do dest="$arg"; done
  printf 'archive fixture\\n' > "$dest"
else
  mkdir -p "$2"
  cp -R "$1/." "$2/"
fi
''')
        self.write_tool("install", '''#!/bin/bash
exec /usr/bin/install "$@"
''')
        self.write_tool("pkgbuild", '''#!/bin/bash
set -euo pipefail
[[ "${FAIL_PKGBUILD:-0}" != 1 ]] || exit 70
printf '%s\\n' "$*" > "$FIXTURE_ROOT/pkgbuild-log"
for arg in "$@"; do dest="$arg"; done
printf 'native installer fixture\\n' > "$dest"
''')
        self.write_tool("xcodebuild", '''#!/bin/bash
set -euo pipefail
printf 'xcodebuild %s\\n' "$*" >> "$FIXTURE_ROOT/build-log"
[[ "${FAIL_BUILD:-0}" != 1 ]] || exit 65
if [[ "${BAD_PLATFORM:-0}" == 1 ]]; then platform=iPhoneOS; else platform=MacOSX; fi
make_app "$FIXTURE_ROOT/.build/hashfleet-mac-xcode/Build/Products/Release/Hash Fleet.app" "$platform" "${REVISION:-one}"
''')
        self.write_tool("swift", '''#!/bin/bash
set -euo pipefail
if [[ "$*" == *--show-bin-path* ]]; then
  printf '%s\\n' "$FIXTURE_ROOT/swift-products"
else
  mkdir -p "$FIXTURE_ROOT/swift-products"
  printf 'cli-%s\\n' "${REVISION:-one}" > "$FIXTURE_ROOT/swift-products/hashfleet"
  chmod +x "$FIXTURE_ROOT/swift-products/hashfleet"
fi
''')
        # Fixture helper is sourced by xcodebuild in a separate process via BASH_ENV.
        self.make_app_function = self.root / "make-app.sh"
        self.make_app_function.write_text('''make_app() {
  local app="$1" platform="$2" revision="$3"
  mkdir -p "$app/Contents/MacOS"
  cat > "$app/Contents/Info.plist" <<PLIST
CFBundlePackageType=APPL
CFBundleIdentifier=app.hashfleet.mac
CFBundleExecutable=Hash Fleet
CFBundleName=Hash Fleet
CFBundleShortVersionString=0.1.0
CFBundleSupportedPlatforms=$platform
PLIST
  printf 'native-%s\\n' "$revision" > "$app/Contents/MacOS/Hash Fleet"
  chmod +x "$app/Contents/MacOS/Hash Fleet"
}
''')
        self.env["BASH_ENV"] = str(self.make_app_function)
        self.env.update(
            PLIST_BUDDY=str(self.tools / "PlistBuddy"),
            FILE_TOOL=str(self.tools / "file"),
            OTOOL=str(self.tools / "otool"),
            CODESIGN=str(self.tools / "codesign"),
            DITTO=str(self.tools / "ditto"),
            INSTALL=str(self.tools / "install"),
        )

    def write_tool(self, name, contents):
        path = self.tools / name
        path.write_text(contents)
        path.chmod(0o755)

    def run_script(self, name, *args, **extra):
        return subprocess.run(["/bin/bash", str(self.scripts / name), *map(str, args)], cwd=self.root,
                              env=dict(self.env, **extra), text=True, capture_output=True, timeout=30)

    def package(self, **extra):
        return self.run_script("package-hashfleet-mac.sh", **extra)

    def install(self, **extra):
        return self.run_script("install-hashfleet-mac.sh", **extra)

    def test_build_uses_native_scheme_and_outputs_contents_layout(self):
        result = self.package()
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        app = self.root / "dist/hashfleet-mac/Hash Fleet.app"
        self.assertTrue((app / "Contents/MacOS/Hash Fleet").is_file())
        self.assertTrue((app / "Contents/MacOS/hashfleet").is_file())
        self.assertFalse((app / "Wrapper").exists())
        self.assertTrue((self.root / "dist/Hash Fleet.pkg").is_file())
        self.assertTrue((self.root / "dist/Hash Fleet Mac.zip").is_file())
        self.assertIn("-scheme HashFleetMac", (self.root / "build-log").read_text())
        self.assertIn("platform=macOS,arch=arm64", (self.root / "build-log").read_text())
        signing = (self.root / "codesign-log").read_text()
        sign_commands = [line for line in signing.splitlines() if "--sign" in line]
        self.assertEqual(len(sign_commands), 2)
        self.assertTrue(all("--deep" not in line for line in sign_commands))
        self.assertIn("--preserve-metadata=identifier,entitlements,flags,runtime", sign_commands[1])
        self.assertTrue(all("--sign -" in line for line in sign_commands))

    def test_rejects_ipad_wrapper_before_replacing_existing_output(self):
        self.assertEqual(self.package().returncode, 0)
        app = self.root / "dist/hashfleet-mac/Hash Fleet.app"
        marker = app / "keep-marker"
        marker.write_text("old package")
        bad = self.root / "bad.app"
        subprocess.run(["/bin/bash", "-c", f'. "{self.make_app_function}"; make_app "$1" iPhoneOS bad', "fixture", str(bad)], check=True)
        result = self.package(HASH_FLEET_USE_PREBUILT_APP="1", HASH_FLEET_APP_SOURCE=str(bad))
        self.assertNotEqual(result.returncode, 0)
        self.assertTrue(marker.exists())
        self.assertIn("does not include MacOSX", result.stderr)

    def test_rejects_catalyst_mach_o_platform(self):
        bad = self.root / "catalyst.app"
        subprocess.run(["/bin/bash", "-c", f'. "{self.make_app_function}"; make_app "$1" MacOSX test', "fixture", str(bad)], check=True)
        self.write_tool("otool", '''#!/bin/bash
printf 'Load command 0\\n      cmd LC_BUILD_VERSION\\n platform 6\\n'
''')
        result = self.run_script("validate-native-mac-app.sh", str(bad))
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("expected native macOS", result.stderr)

    def test_rejects_ios_requirement_even_with_macos_platform_metadata(self):
        self.assertEqual(self.package().returncode, 0)
        app = self.root / "dist/hashfleet-mac/Hash Fleet.app"
        with (app / "Contents/Info.plist").open("a") as info:
            info.write("LSRequiresIPhoneOS=true\n")
        result = self.run_script("validate-native-mac-app.sh", app)
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("iOS application requirement", result.stderr)

    def test_rejects_nested_apps_and_extensions(self):
        self.assertEqual(self.package().returncode, 0)
        app = self.root / "dist/hashfleet-mac/Hash Fleet.app"
        for name in ("iPad.app", "Widget.appex", "Wrapper"):
            with self.subTest(name=name):
                nested = app / "Contents/Resources" / name
                nested.mkdir(parents=True)
                result = self.run_script("validate-native-mac-app.sh", app)
                self.assertNotEqual(result.returncode, 0)
                self.assertIn("nested applications", result.stderr)
                nested.rmdir()

    def test_rejects_non_macho_before_package_replacement(self):
        self.assertEqual(self.package().returncode, 0)
        marker = self.root / "dist/hashfleet-mac/keep"
        marker.write_text("old package")
        self.write_tool("file", "#!/bin/bash\nprintf 'ELF 64-bit executable\\n'\n")
        result = self.package()
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("not Mach-O", result.stderr)
        self.assertTrue(marker.exists())

    def test_rejects_source_inside_output_before_replacing_it(self):
        output = self.root / "dist/hashfleet-mac"
        source = output / "source.app"
        subprocess.run(["/bin/bash", "-c", f'. "{self.make_app_function}"; make_app "$1" MacOSX source', "fixture", str(source)], check=True)
        marker = output / "preserve"
        marker.write_text("old")
        result = self.package(HASH_FLEET_USE_PREBUILT_APP="1", HASH_FLEET_APP_SOURCE=str(source))
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("inside output", result.stderr)
        self.assertTrue(marker.exists())
        self.assertTrue((source / "Contents/MacOS/Hash Fleet").exists())

    def test_failed_build_preserves_existing_distribution(self):
        self.assertEqual(self.package().returncode, 0)
        marker = self.root / "dist/hashfleet-mac/keep"
        marker.write_text("retain")
        result = self.package(FAIL_BUILD="1")
        self.assertNotEqual(result.returncode, 0)
        self.assertTrue(marker.exists())

    def test_failed_installer_packaging_preserves_existing_distribution(self):
        self.assertEqual(self.package().returncode, 0)
        marker = self.root / "dist/hashfleet-mac/keep"
        marker.write_text("retain")
        old_zip = (self.root / "dist/Hash Fleet Mac.zip").read_bytes()
        old_pkg = (self.root / "dist/Hash Fleet.pkg").read_bytes()
        result = self.package(FAIL_PKGBUILD="1", REVISION="two")
        self.assertNotEqual(result.returncode, 0)
        self.assertTrue(marker.exists())
        self.assertEqual((self.root / "dist/Hash Fleet Mac.zip").read_bytes(), old_zip)
        self.assertEqual((self.root / "dist/Hash Fleet.pkg").read_bytes(), old_pkg)

    def test_installer_rejects_bad_source_without_touching_destination(self):
        dest_parent = self.root / "install"
        dest = dest_parent / "Hash Fleet.app"
        dest.parent.mkdir()
        dest.mkdir()
        (dest / "preserve").write_text("old")
        bad_package = self.root / "bad-package"
        bad = bad_package / "Hash Fleet.app"
        bad.parent.mkdir()
        subprocess.run(["/bin/bash", "-c", f'. "{self.make_app_function}"; make_app "$1" iPhoneOS bad', "fixture", str(bad)], check=True)
        result = self.install(HASH_FLEET_PACKAGE_DIR=str(bad_package), HASH_FLEET_APP_DEST=str(dest), HASH_FLEET_CLI_DIR=str(self.root / "bin"))
        self.assertNotEqual(result.returncode, 0)
        self.assertTrue((dest / "preserve").exists())

    def test_installer_rolls_back_app_and_cli_on_link_failure(self):
        self.assertEqual(self.package().returncode, 0)
        dest = self.root / "install/Hash Fleet.app"
        dest.parent.mkdir()
        dest.mkdir()
        (dest / "old-data").write_text("preserve through backup")
        cli_dir = self.root / "bin"
        cli_dir.mkdir()
        cli = cli_dir / "hashfleet"
        cli.write_text("old cli")
        self.write_tool("ln", '''#!/bin/bash
exit 73
''')
        result = self.install(HASH_FLEET_APP_DEST=str(dest), HASH_FLEET_CLI_DIR=str(cli_dir))
        self.assertNotEqual(result.returncode, 0)
        self.assertTrue((dest / "old-data").exists())
        self.assertEqual(cli.read_text(), "old cli")
        self.assertEqual(list(dest.parent.glob("Hash Fleet.app.backup.*")), [])
        self.assertEqual(list((dest.parent / ".hashfleet-backups.noindex").glob("*")), [])

    def test_installer_rejects_symlinked_hidden_backup_storage(self):
        self.assertEqual(self.package().returncode, 0)
        dest = self.root / "install/Hash Fleet.app"
        dest.mkdir(parents=True)
        (dest / "keep").write_text("original")
        outside = self.root / "outside"
        outside.mkdir()
        (dest.parent / ".hashfleet-backups.noindex").symlink_to(outside, target_is_directory=True)
        result = self.install(HASH_FLEET_APP_DEST=str(dest), HASH_FLEET_CLI_DIR=str(self.root / "bin"))
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("symlinked app backup", result.stderr)
        self.assertEqual((dest / "keep").read_text(), "original")
        self.assertEqual(list(outside.iterdir()), [])

    def prepare_replacement(self):
        self.assertEqual(self.package().returncode, 0)
        dest = self.root / "install/Hash Fleet.app"
        source = self.root / "dist/hashfleet-mac/Hash Fleet.app"
        shutil.copytree(source, dest)
        cli_dir = self.root / "bin"
        cli_dir.mkdir()
        (cli_dir / "hashfleet").write_text("old cli")
        self.assertEqual(self.package(REVISION="two").returncode, 0)
        return dest, cli_dir, source

    def test_installer_success_deletes_only_current_app_backup_and_keeps_cli(self):
        dest, cli_dir, source = self.prepare_replacement()
        old_cli = cli_dir / "hashfleet"
        backup_dir = dest.parent / ".hashfleet-backups.noindex"
        historical = backup_dir / "Hash Fleet.backup.unrelated"
        historical.mkdir(parents=True)
        (historical / "keep").write_text("not this transaction")
        other_app = dest.parent / "Other.app"
        other_app.mkdir()
        (other_app / "keep").write_text("other app")
        preferences = self.root / "owner-preferences-history"
        preferences.write_text("owner data")
        result = self.install(HASH_FLEET_APP_DEST=str(dest), HASH_FLEET_CLI_DIR=str(cli_dir))
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertTrue((dest / "Contents/MacOS/hashfleet").exists())
        self.assertEqual((dest / "Contents/MacOS/Hash Fleet").read_text(), "native-two\n")
        self.assertEqual(os.readlink(old_cli), str(dest / "Contents/MacOS/hashfleet"))
        self.assertEqual(list(backup_dir.iterdir()), [historical])
        self.assertEqual((historical / "keep").read_text(), "not this transaction")
        self.assertEqual((other_app / "keep").read_text(), "other app")
        self.assertEqual(preferences.read_text(), "owner data")
        self.assertEqual((source / "Contents/MacOS/Hash Fleet").read_text(), "native-two\n")
        cli_backups = list(cli_dir.glob(".hashfleet-cli-backup.*"))
        self.assertEqual(list(dest.parent.glob("Hash Fleet.app.backup.*")), [])
        self.assertEqual(set(dest.parent.glob("*.app")), {dest, other_app})
        self.assertEqual(len(cli_backups), 1)
        self.assertEqual(cli_backups[0].read_text(), "old cli")
        self.assertNotIn("Previous app retained", result.stdout)

    def test_repeated_installs_do_not_accumulate_app_backups(self):
        self.assertEqual(self.package().returncode, 0)
        dest = self.root / "install/Hash Fleet.app"
        cli_dir = self.root / "bin"
        for attempt in range(3):
            with self.subTest(attempt=attempt):
                result = self.install(HASH_FLEET_APP_DEST=str(dest), HASH_FLEET_CLI_DIR=str(cli_dir))
                self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
                self.assertEqual(list((dest.parent / ".hashfleet-backups.noindex").glob("*")), [])
                self.assertEqual(list(dest.parent.glob("*.app")), [dest])
                self.assertEqual((cli_dir / "hashfleet").read_text(), "cli-one\n")

    def test_unknown_backup_identity_is_restored_not_deleted(self):
        dest, cli_dir, _ = self.prepare_replacement()
        info = dest / "Contents/Info.plist"
        info.write_text(info.read_text().replace("app.hashfleet.mac", "app.someone.else"))
        (dest / "user-data").write_text("keep")
        result = self.install(HASH_FLEET_APP_DEST=str(dest), HASH_FLEET_CLI_DIR=str(cli_dir))
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("unexpected bundle identifier", result.stderr)
        self.assertEqual((dest / "user-data").read_text(), "keep")
        self.assertIn("app.someone.else", info.read_text())
        self.assertEqual((cli_dir / "hashfleet").read_text(), "old cli")
        self.assertEqual(list((dest.parent / ".hashfleet-backups.noindex").glob("*")), [])

    def test_installed_validation_failure_restores_app_and_cli(self):
        dest, cli_dir, _ = self.prepare_replacement()
        self.write_tool("codesign", '''#!/bin/bash
for arg in "$@"; do
  [[ "$arg" != "$FIXTURE_ROOT/install/Hash Fleet.app" ]] || exit 74
done
exit 0
''')
        result = self.install(HASH_FLEET_APP_DEST=str(dest), HASH_FLEET_CLI_DIR=str(cli_dir))
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("signature verification failed", result.stderr)
        self.assertEqual((dest / "Contents/MacOS/Hash Fleet").read_text(), "native-one\n")
        self.assertEqual((cli_dir / "hashfleet").read_text(), "old cli")
        self.assertEqual(list((dest.parent / ".hashfleet-backups.noindex").glob("*")), [])

    def test_backup_validation_failure_restores_app_and_cli(self):
        dest, cli_dir, _ = self.prepare_replacement()
        self.write_tool("codesign", '''#!/bin/bash
for arg in "$@"; do
  case "$arg" in */.hashfleet-backups.noindex/"Hash Fleet.backup."*) exit 74 ;; esac
done
exit 0
''')
        result = self.install(HASH_FLEET_APP_DEST=str(dest), HASH_FLEET_CLI_DIR=str(cli_dir))
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("signature verification failed", result.stderr)
        self.assertEqual((dest / "Contents/MacOS/Hash Fleet").read_text(), "native-one\n")
        self.assertEqual((cli_dir / "hashfleet").read_text(), "old cli")
        self.assertEqual(list((dest.parent / ".hashfleet-backups.noindex").glob("*")), [])

    def test_partial_backup_deletion_failure_never_rolls_back_validated_install(self):
        dest, cli_dir, _ = self.prepare_replacement()
        self.write_tool("rm", '''#!/bin/bash
for arg in "$@"; do
  case "$arg" in
    "$FIXTURE_ROOT"/install/.hashfleet-backups.noindex/"Hash Fleet.backup."*)
      /bin/rm -f "$arg/Contents/MacOS/Hash Fleet"
      exit 75
      ;;
  esac
done
exec /bin/rm "$@"
''')
        result = self.install(HASH_FLEET_APP_DEST=str(dest), HASH_FLEET_CLI_DIR=str(cli_dir))
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("Installation validated, but superseded app cleanup failed", result.stderr)
        self.assertEqual((dest / "Contents/MacOS/Hash Fleet").read_text(), "native-two\n")
        self.assertEqual(os.readlink(cli_dir / "hashfleet"), str(dest / "Contents/MacOS/hashfleet"))
        backups = list((dest.parent / ".hashfleet-backups.noindex").glob("Hash Fleet.backup.*"))
        self.assertEqual(len(backups), 1)
        self.assertFalse((backups[0] / "Contents/MacOS/Hash Fleet").exists())
        cli_backups = list(cli_dir.glob(".hashfleet-cli-backup.*"))
        self.assertEqual(len(cli_backups), 1)
        self.assertEqual(cli_backups[0].read_text(), "old cli")

    def test_signal_during_backup_deletion_does_not_restore_partial_backup(self):
        dest, cli_dir, _ = self.prepare_replacement()
        self.write_tool("rm", '''#!/bin/bash
for arg in "$@"; do
  case "$arg" in
    "$FIXTURE_ROOT"/install/.hashfleet-backups.noindex/"Hash Fleet.backup."*)
      /bin/rm -f "$arg/Contents/MacOS/Hash Fleet"
      kill -TERM "$PPID"
      exit 76
      ;;
  esac
done
exec /bin/rm "$@"
''')
        result = self.install(HASH_FLEET_APP_DEST=str(dest), HASH_FLEET_CLI_DIR=str(cli_dir))
        self.assertEqual(result.returncode, 143, result.stdout + result.stderr)
        self.assertEqual((dest / "Contents/MacOS/Hash Fleet").read_text(), "native-two\n")
        self.assertEqual(os.readlink(cli_dir / "hashfleet"), str(dest / "Contents/MacOS/hashfleet"))
        backups = list((dest.parent / ".hashfleet-backups.noindex").glob("Hash Fleet.backup.*"))
        self.assertEqual(len(backups), 1)
        self.assertFalse((backups[0] / "Contents/MacOS/Hash Fleet").exists())
        self.assertEqual(list(cli_dir.glob(".hashfleet-cli-backup.*"))[0].read_text(), "old cli")

    def test_installer_restores_old_cli_symlink_when_bundle_is_temporarily_moved(self):
        self.assertEqual(self.package().returncode, 0)
        dest = self.root / "install/Hash Fleet.app"
        old_binary = dest / "Contents/MacOS/hashfleet"
        old_binary.parent.mkdir(parents=True)
        old_binary.write_text("old bundled cli")
        cli_dir = self.root / "bin"
        cli_dir.mkdir()
        cli = cli_dir / "hashfleet"
        cli.symlink_to(old_binary)
        self.write_tool("ln", "#!/bin/bash\nexit 73\n")
        result = self.install(HASH_FLEET_APP_DEST=str(dest), HASH_FLEET_CLI_DIR=str(cli_dir))
        self.assertNotEqual(result.returncode, 0)
        self.assertTrue(cli.is_symlink())
        self.assertEqual(os.readlink(cli), str(old_binary))
        self.assertEqual(cli.read_text(), "old bundled cli")
        self.assertEqual(list(cli_dir.glob(".hashfleet-cli-backup.*")), [])

    def test_unsafe_output_path_is_rejected_without_deletion(self):
        sentinel = self.root / "sentinel"
        sentinel.mkdir()
        (sentinel / "keep").write_text("safe")
        result = self.package(HASH_FLEET_DIST_DIR=str(sentinel))
        self.assertNotEqual(result.returncode, 0)
        self.assertEqual((sentinel / "keep").read_text(), "safe")

    def test_unsafe_install_destination_is_rejected(self):
        self.assertEqual(self.package().returncode, 0)
        dest = self.root / "install/Other.app"
        dest.parent.mkdir()
        dest.mkdir()
        (dest / "keep").write_text("safe")
        result = self.install(HASH_FLEET_APP_DEST=str(dest), HASH_FLEET_CLI_DIR=str(self.root / "bin"))
        self.assertNotEqual(result.returncode, 0)
        self.assertTrue((dest / "keep").exists())

    def test_retired_companion_install_is_refused_before_system_changes(self):
        home = self.root / "isolated-home"
        self.write_tool("launchctl", '#!/bin/bash\necho called > "$FIXTURE_ROOT/launchctl-called"\nexit 0\n')
        result = self.run_script("hash-fleet-menu-bar.sh", "install", HOME=str(home))
        self.assertEqual(result.returncode, 64)
        self.assertIn("retired", result.stderr)
        self.assertFalse(home.exists())
        self.assertFalse((self.root / "launchctl-called").exists())


if __name__ == "__main__":
    unittest.main(verbosity=2)
