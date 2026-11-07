"""Exercise the audit orchestrator with fake tools, never miners or simulators."""
import json
import os
from pathlib import Path
import shutil
import subprocess
import sys
import tempfile
import unittest


class SonarProjectRecipeTests(unittest.TestCase):
    def test_current_swiftpm_layout_and_failure_continuation(self):
        self.exercise_layout("HashFleetCoreTests")

    def test_legacy_swiftpm_layout_and_failure_continuation(self):
        self.exercise_layout("HashFleetCorePackageTests")

    def exercise_layout(self, product_name):
        with tempfile.TemporaryDirectory(prefix="sonar recipe ") as directory:
            root = Path(directory)
            tools = root / "Tools"
            tools.mkdir()
            shutil.copyfile(Path(__file__).with_name("sonar-project-test.sh"), tools / "sonar-project-test.sh")
            for shard in (1, 2, 3):
                (tools / f"sonar-test-identities-unit-{shard}.json").write_text(json.dumps(["ExampleTests/check()", "OtherTests/check()" if shard == 1 else "ExampleTests/other()", "ExampleTests/check(value:)?args=31"]))
            bin_dir = root / "fake-bin"
            bin_dir.mkdir()
            product = root / "products"
            (product / "codecov").mkdir(parents=True)
            (product / "codecov/default.profdata").touch()
            binary = product / f"{product_name}.xctest/Contents/MacOS/{product_name}"
            binary.parent.mkdir(parents=True)
            binary.touch()
            mock = "#!" + sys.executable + "\n" + '''import json, os, pathlib, subprocess, sys
name = pathlib.Path(sys.argv[0]).name
args = sys.argv[1:]
with open(os.environ['CALLS'], 'a') as stream:
    stream.write(json.dumps([name, *args]) + '\\n')
if name == 'python-fixture' and args[:1] == ['-c'] and 'json.load' in args[1]:
    sys.exit(subprocess.call([os.environ['REAL_PYTHON'], *args]))
if name == 'swift' and '--show-bin-path' in args:
    print(os.environ['PRODUCT'])
if name == 'xcodebuild' and 'build-for-testing' in args:
    sys.exit(70)
'''
            for name in ("xcodebuild", "xcrun", "swift", "python-fixture"):
                path = bin_dir / name
                path.write_text(mock)
                path.chmod(0o755)
            env = dict(os.environ, PATH=str(bin_dir) + os.pathsep + os.environ["PATH"],
                       PYTHON=str(bin_dir / "python-fixture"), REAL_PYTHON=sys.executable,
                       CALLS=str(root / "calls.jsonl"), PRODUCT=str(product))
            result = subprocess.run(["/bin/bash", str(tools / "sonar-project-test.sh")],
                                    env=env, capture_output=True, text=True, timeout=30)
            self.assertEqual(result.returncode, 1, result.stdout + result.stderr)
            phases = dict(line.split("\t") for line in (root / "build/swift-sonar-project/phase-exits.tsv").read_text().splitlines())
            self.assertEqual(phases["ios-build"], "70")
            self.assertEqual(len(phases), 18)
            self.assertEqual(phases["support-ui"], "0")
            self.assertEqual(phases["python-coverage"], "0")
            calls = [json.loads(line) for line in (root / "calls.jsonl").read_text().splitlines()]
            native_tests = [call for call in calls if call[0] == "xcodebuild" and call[1] in ("test", "test-without-building")]
            self.assertEqual(len(native_tests), 7)
            for call in native_tests:
                self.assertEqual(call[call.index("-collect-test-diagnostics") + 1], "never")
                self.assertEqual(call[call.index("-enableCodeCoverage") + 1], "YES")
                self.assertIn("-resultBundlePath", call)
            support = [call for call in calls if "-only-testing:HashFleetTests/FleetInformationPageViewportTests" in call]
            self.assertEqual(len(support), 1)
            self.assertIn("-only-testing:HashFleetUITests/DeveloperSupportUITests", support[0])
            merged = [call for call in calls if call[:3] == ["xcrun", "xcresulttool", "merge"]]
            self.assertEqual(len(merged), 1)
            self.assertIn("build/swift-sonar-project/support.xcresult", merged[0])
            swift_calls = [call for call in calls if call[0] == "swift"]
            self.assertEqual(len(swift_calls), 4)
            for call in swift_calls:
                self.assertIn("--force-resolved-versions", call)
                self.assertIn("--skip-update", call)
            shards = [call for call in calls if "-only-testing:HashFleetTests/ExampleTests" in call]
            self.assertEqual(len(shards), 3)
            self.assertEqual(shards[0].count("-only-testing:HashFleetTests/ExampleTests"), 1)
            self.assertIn("OS=26.5", shards[0][shards[0].index("-destination") + 1])
            self.assertIn("OS=26.4.1", shards[2][shards[2].index("-destination") + 1])
            repeat = subprocess.run(["/bin/bash", str(tools / "sonar-project-test.sh")],
                                    env=env, capture_output=True, text=True, timeout=10)
            self.assertNotEqual(repeat.returncode, 0)
            self.assertIn("Move it aside", repeat.stderr)

    def setup_fixture_tools(self, root, *, python_has_coverage=True):
        tools = root / "Tools"
        tools.mkdir(parents=True, exist_ok=True)
        shutil.copyfile(Path(__file__).with_name("sonar-project-test.sh"), tools / "sonar-project-test.sh")
        bin_dir = root / "fake-bin"
        bin_dir.mkdir(parents=True, exist_ok=True)
        calls_path = root / "calls.jsonl"
        mock = "#!" + sys.executable + "\n" + f'''import json, os, pathlib, sys
name = pathlib.Path(sys.argv[0]).name
args = sys.argv[1:]
with open({repr(str(calls_path))}, "a") as stream:
    stream.write(json.dumps([str(sys.argv[0]), *args]) + "\\n")
if args[:1] == ["-c"] and "import coverage" in args[1]:
    sys.exit(0 if {repr(python_has_coverage)} else 1)
if args[:1] == ["-c"] and "import sys; sys.exit(0 if sys.version_info >= (3, 11) else 1)" in args[1]:
    sys.exit(0)
'''
        for name in ("xcodebuild", "xcrun", "swift", "python-fixture"):
            path = bin_dir / name
            path.write_text(mock)
            path.chmod(0o755)
        env = dict(os.environ, PATH=str(bin_dir) + os.pathsep + os.environ.get("PATH", ""),
                   CALLS=str(calls_path))
        return tools, bin_dir, env, calls_path

    def test_check_prerequisites_succeeds_without_executing_phases_or_triggering_collision(self):
        with tempfile.TemporaryDirectory(prefix="sonar-prereq-") as directory:
            root = Path(directory)
            tools, bin_dir, env, calls_path = self.setup_fixture_tools(root)
            env["PYTHON"] = str(bin_dir / "python-fixture")
            (root / "build/swift-sonar-project").mkdir(parents=True)
            result = subprocess.run(["/bin/bash", str(tools / "sonar-project-test.sh"), "--check-prerequisites"],
                                    env=env, cwd=root, capture_output=True, text=True, timeout=10)
            self.assertEqual(result.returncode, 0, result.stderr)
            self.assertIn("Prerequisites satisfied", result.stdout)
            self.assertIn("python-fixture", result.stdout)
            self.assertFalse((root / "build/swift-sonar-project/phase-exits.tsv").exists())
            calls = [json.loads(line) for line in calls_path.read_text().splitlines()]
            executables = [Path(call[0]).name for call in calls]
            self.assertNotIn("xcodebuild", executables)
            self.assertNotIn("swift", executables)

    def test_unknown_flag_is_rejected(self):
        with tempfile.TemporaryDirectory(prefix="sonar-unknown-") as directory:
            root = Path(directory)
            tools, bin_dir, env, _ = self.setup_fixture_tools(root)
            env["PYTHON"] = str(bin_dir / "python-fixture")
            result = subprocess.run(["/bin/bash", str(tools / "sonar-project-test.sh"), "--unknown-flag"],
                                    env=env, cwd=root, capture_output=True, text=True, timeout=10)
            self.assertEqual(result.returncode, 1)
            self.assertIn("Unknown argument: --unknown-flag", result.stderr)

    def test_preferred_project_virtualenv_is_selected_when_python_unset(self):
        with tempfile.TemporaryDirectory(prefix="sonar-venv-pref-") as directory:
            root = Path(directory)
            tools, bin_dir, env, calls_path = self.setup_fixture_tools(root)
            project_python = root / ".swift-sonar/python/bin/python"
            project_python.parent.mkdir(parents=True)
            shutil.copyfile(bin_dir / "python-fixture", project_python)
            project_python.chmod(0o755)
            env.pop("PYTHON", None)
            result = subprocess.run(["/bin/bash", str(tools / "sonar-project-test.sh"), "--check-prerequisites"],
                                    env=env, cwd=root, capture_output=True, text=True, timeout=10)
            self.assertEqual(result.returncode, 0, result.stderr)
            self.assertIn(".swift-sonar/python/bin/python", result.stdout)
            calls = [json.loads(line) for line in calls_path.read_text().splitlines()]
            called_paths = [call[0] for call in calls]
            self.assertTrue(any(".swift-sonar/python/bin/python" in p for p in called_paths))

    def test_explicit_python_override_takes_precedence_over_project_virtualenv(self):
        with tempfile.TemporaryDirectory(prefix="sonar-override-") as directory:
            root = Path(directory)
            tools, bin_dir, env, calls_path = self.setup_fixture_tools(root)
            project_python = root / ".swift-sonar/python/bin/python"
            project_python.parent.mkdir(parents=True)
            shutil.copyfile(bin_dir / "python-fixture", project_python)
            project_python.chmod(0o755)
            custom_python = bin_dir / "custom-explicit-python"
            shutil.copyfile(bin_dir / "python-fixture", custom_python)
            custom_python.chmod(0o755)
            env["PYTHON"] = str(custom_python)
            result = subprocess.run(["/bin/bash", str(tools / "sonar-project-test.sh"), "--check-prerequisites"],
                                    env=env, cwd=root, capture_output=True, text=True, timeout=10)
            self.assertEqual(result.returncode, 0, result.stderr)
            self.assertIn("custom-explicit-python", result.stdout)
            calls = [json.loads(line) for line in calls_path.read_text().splitlines()]
            called_paths = [call[0] for call in calls]
            self.assertTrue(any("custom-explicit-python" in p for p in called_paths))
            self.assertFalse(any(".swift-sonar/python/bin/python" in p for p in called_paths))

    def test_missing_coverage_fails_with_friendly_setup_command_and_no_traceback_or_phases(self):
        with tempfile.TemporaryDirectory(prefix="sonar-nocov-") as directory:
            root = Path(directory)
            tools, bin_dir, env, _ = self.setup_fixture_tools(root, python_has_coverage=False)
            env["PYTHON"] = str(bin_dir / "python-fixture")
            result = subprocess.run(["/bin/bash", str(tools / "sonar-project-test.sh")],
                                    env=env, cwd=root, capture_output=True, text=True, timeout=10)
            self.assertEqual(result.returncode, 1)
            self.assertIn("python-fixture", result.stderr)
            self.assertIn("python3.12 -m venv .swift-sonar/python && .swift-sonar/python/bin/pip install 'coverage==7.17.2'", result.stderr)
            self.assertNotIn("Traceback (most recent call last)", result.stderr)
            self.assertFalse((root / "build/swift-sonar-project").exists())


if __name__ == "__main__":
    unittest.main()
