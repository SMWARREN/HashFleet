import os
import subprocess
import shlex
import sys
import tempfile
import unittest
from pathlib import Path


class SonarScanTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.root = Path(__file__).resolve().parents[1]
        self.directory = Path(self.temp.name)
        self.bin = self.directory / "bin"
        self.bin.mkdir()
        self.bundle = self.directory / "fixture.xcresult"
        self.bundle.mkdir()
        self.docker_log = self.directory / "docker.log"
        self.write_command(
            "curl",
            'if [ "$MOCK_SONAR_UP" = 1 ]; then printf \'{"status":"UP"}\'; else exit 22; fi',
        )
        self.write_command(
            "docker",
            'printf "%s\\n" "$*" >> "$MOCK_DOCKER_LOG"; exit 0',
        )
        self.write_command("swiftlint", 'printf "%s\\n" "$*" >> "$MOCK_LINT_LOG"; printf "[]\\n"; exit "${MOCK_LINT_EXIT:-0}"')
        self.write_command("python3",
                           'if [[ "$1" == Tools/sonar_swift_preflight.py ]]; then '
                           'exit "${MOCK_PREFLIGHT_EXIT:-0}"; fi\n'
                           + "exec " + shlex.quote(sys.executable) + ' "$@"')
        self.write_command("sonar-scanner", 'printf "SCANNER_CALLED\\n"; printf "%s\\n" "$@"')
        self.environment = dict(os.environ)
        self.environment.update(
            PATH=str(self.bin) + os.pathsep + self.environment.get("PATH", ""),
            SONAR_TOKEN="test-fixture",
            SONAR_CONTAINER="test-fixture-container",
            SONAR_CACHE_DIR=str(self.directory / "cache"),
            SONAR_RESULT_BUNDLE=str(self.bundle),
            MOCK_SONAR_UP="1",
            MOCK_DOCKER_LOG=str(self.docker_log),
            MOCK_LINT_LOG=str(self.directory / "lint.log"),
            SONAR_REQUIRE_TESTS="0",
        )

    def write_command(self, name, body):
        command = self.bin / name
        command.write_text("#!/bin/bash\n" + body + "\n")
        command.chmod(0o755)

    def run_scan(self, *arguments):
        return subprocess.run(
            ["/bin/bash", str(self.root / "Tools/sonar-scan.sh"), *arguments],
            env=self.environment,
            capture_output=True,
            text=True,
            check=False,
        )

    def test_absolute_result_bundle_is_passed_project_relative(self):
        result = self.run_scan("-Dsonar.projectVersion=test-fixture")
        expected = os.path.relpath(self.bundle, self.root)
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn("-Dsonar.apple.resultBundlePath=" + expected, result.stdout)
        self.assertIn("-Dsonar.projectVersion=test-fixture", result.stdout)
        self.assertFalse(self.docker_log.exists())
        self.assertIn("-Dsonar.qualitygate.wait=true", result.stdout)
        self.assertEqual((self.directory / "lint.log").read_text().strip(),
                         "lint --quiet --strict --reporter json")

    def test_missing_result_bundle_fails_before_publishing(self):
        self.environment["SONAR_RESULT_BUNDLE"] = str(self.directory / "missing.xcresult")
        result = self.run_scan()
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("Xcode result bundle does not exist", result.stderr)
        self.assertNotIn("SCANNER_CALLED", result.stdout)

    def test_no_bundle_is_explicitly_unverified_but_still_scanned(self):
        self.environment.pop("SONAR_RESULT_BUNDLE")
        result = self.run_scan()
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn("Tests/coverage are not verified", result.stderr)
        self.assertIn("SCANNER_CALLED", result.stdout)

    def test_required_bundle_cannot_be_omitted(self):
        self.environment.pop("SONAR_RESULT_BUNDLE")
        self.environment["SONAR_REQUIRE_TESTS"] = "1"
        result = self.run_scan()
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("requires SONAR_RESULT_BUNDLE", result.stderr)
        self.assertNotIn("SCANNER_CALLED", result.stdout)

    def test_failed_swift_capability_prevents_publication(self):
        self.environment["MOCK_PREFLIGHT_EXIT"] = "1"
        result = self.run_scan()
        self.assertNotEqual(result.returncode, 0)
        self.assertNotIn("SCANNER_CALLED", result.stdout)
        self.assertFalse((self.directory / "lint.log").exists())

    def test_lint_warning_or_failure_prevents_publication(self):
        self.environment["MOCK_LINT_EXIT"] = "2"
        result = self.run_scan()
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("SwiftLint failed", result.stderr)
        self.assertNotIn("SCANNER_CALLED", result.stdout)

    def test_scanner_or_quality_gate_failure_is_propagated(self):
        self.write_command("sonar-scanner", "exit 3")
        result = self.run_scan()
        self.assertEqual(result.returncode, 3)
        self.assertNotIn("Done. Open", result.stdout)

    def test_unready_existing_container_is_not_removed_or_restarted(self):
        self.environment["MOCK_SONAR_UP"] = "0"
        result = self.run_scan()
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("Refusing to remove its analysis data", result.stderr)
        self.assertEqual(
            self.docker_log.read_text().splitlines(),
            ["container inspect test-fixture-container"],
        )
        self.assertNotIn("SCANNER_CALLED", result.stdout)


if __name__ == "__main__":
    unittest.main()
