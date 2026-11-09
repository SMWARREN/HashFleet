"""Keep real website tests separate from production analysis, without omitting tools."""
import fnmatch
from pathlib import Path
import unittest

ROOT = Path(__file__).resolve().parents[1]
PAYLOADS = {
    "browser-acceptance.js", "native-parity-acceptance.js", "navigation-regression.js",
    "privacy-permalink-acceptance.js", "public-contact-acceptance.js",
    "route-acceptance.js", "support-acceptance.js", "watch-acceptance.js",
}


def properties():
    return dict(line.split("=", 1) for line in (ROOT / "sonar-project.properties").read_text().splitlines()
                if line and not line.startswith("#") and "=" in line)


def matches(path, patterns):
    return any(fnmatch.fnmatchcase(path, pattern) for pattern in patterns.split(","))


class SonarScopeTests(unittest.TestCase):
    def test_mixed_website_roots_are_available_to_both_classifiers(self):
        config = properties()
        for root in ("website/src", "website/Tools"):
            self.assertIn(root, config["sonar.sources"].split(","))
            self.assertIn(root, config["sonar.tests"].split(","))

    def test_actual_website_tests_are_classified_as_tests(self):
        expected = {p.relative_to(ROOT).as_posix() for pattern in ("*.test.ts", "*.test.tsx", "*.test.js")
                    for p in (ROOT / "website/src").rglob(pattern)}
        expected.update(p.relative_to(ROOT).as_posix() for p in (ROOT / "website/Tools").glob("*.node-test.mjs"))
        expected.update("website/Tools/" + name for name in PAYLOADS)
        self.assertGreaterEqual(len(expected), 18)
        config = properties()
        for name in sorted(expected):
            with self.subTest(path=name):
                self.assertTrue(matches(name, config["sonar.test.inclusions"]))
                self.assertFalse(matches(name, config["sonar.exclusions"]))

    def test_production_components_and_runner_helpers_stay_source(self):
        config = properties()
        production = ["website/src/App.tsx", "website/src/components/DashboardPreview.tsx",
                      "website/src/lib/ansi.ts", "website/Tools/playwright-result.mjs",
                      "website/Tools/capture-cli-dashboard.py", "website/Tools/public-parity-assets.mjs"]
        production.extend(p.relative_to(ROOT).as_posix() for p in (ROOT / "website/Tools").glob("run-*.mjs"))
        for name in production:
            with self.subTest(path=name):
                self.assertFalse(matches(name, config["sonar.test.inclusions"]))
                self.assertFalse(matches(name, config["sonar.exclusions"]))

    def test_no_blanket_website_or_coverage_exclusions(self):
        config = properties()
        self.assertNotIn("sonar.coverage.exclusions", config)
        self.assertNotIn("sonar.issue.ignore.multicriteria", config)
        for pattern in config["sonar.exclusions"].split(","):
            self.assertNotIn("website", pattern)

    def test_release_and_capture_unittests_are_tests_not_their_tools(self):
        config = properties()
        self.assertIn("Scripts/release", config["sonar.tests"].split(","))
        for path in ("Scripts/release/test_release.py", "website/Tools/test_capture_dashboard.py"):
            self.assertTrue(matches(path, config["sonar.test.inclusions"]), path)
        for path in ("Scripts/release/release.py", "website/Tools/capture-cli-dashboard.py"):
            self.assertFalse(matches(path, config["sonar.test.inclusions"]), path)


if __name__ == "__main__":
    unittest.main()
