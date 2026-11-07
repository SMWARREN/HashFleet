import contextlib
import io
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest
import xml.etree.ElementTree as ET

from unittest.mock import patch

from Tools.swiftpm_coverage import convert_lcov, main


class SwiftPMCoverageTests(unittest.TestCase):
    def setUp(self):
        self.directory = tempfile.TemporaryDirectory(prefix="swiftpm-coverage-tests-")
        self.addCleanup(self.directory.cleanup)
        self.root = Path(self.directory.name)
        self.source = self.root / "Sources" / "Core" / "Example.swift"
        self.source.parent.mkdir(parents=True)
        self.source.write_text("let first = 1\nlet second = 2\nlet third = 3\n", encoding="utf-8")

    def record(self, path=None, entries="DA:1,2\nDA:2,0"):
        return f"SF:{path or self.source}\n{entries}\nend_of_record\n"

    def lines(self, text):
        report = convert_lcov(text, self.root)
        return report, {int(line.attrib["lineNumber"]): line.attrib["covered"]
                        for line in report.findall("./file/lineToCover")}

    def test_preserves_hits_and_real_uncovered_lines_without_estimates(self):
        report, lines = self.lines(self.record())
        self.assertEqual(report.attrib, {"version": "1"})
        self.assertEqual(report[0].attrib["path"], "Sources/Core/Example.swift")
        self.assertEqual(lines, {1: "true", 2: "false"})
        self.assertNotIn(3, lines, "An unreported line must not be invented")

    def test_relative_paths_resolve_against_explicit_repository_root(self):
        _, lines = self.lines(self.record("Sources/Core/Example.swift"))
        self.assertEqual(lines, {1: "true", 2: "false"})

    def test_duplicate_records_union_observed_hits_without_double_counting(self):
        _, lines = self.lines(self.record(entries="DA:1,0\nDA:2,0") +
                              self.record(entries="DA:1,3\nDA:2,0") +
                              self.record(entries="DA:1,0"))
        self.assertEqual(lines, {1: "true", 2: "false"})

    def test_checksum_and_lcov_summary_fields_do_not_change_hit_status(self):
        _, lines = self.lines(self.record(entries="DA:2,0,checksum\nDA:1,4\nLF:2\nLH:1\nFNF:10"))
        self.assertEqual(lines, {1: "true", 2: "false"})

    def test_external_dependency_and_test_files_do_not_become_production_coverage(self):
        text = self.record(self.root / "Tests" / "ExampleTests.swift")
        text += self.record(self.root / ".build" / "checkouts" / "Dependency.swift")
        text += self.record()
        report, _ = self.lines(text)
        self.assertEqual(len(report), 1)
        self.assertEqual(report[0].attrib["path"], "Sources/Core/Example.swift")

    def test_path_traversal_and_similar_prefixes_cannot_admit_other_sources(self):
        text = self.record("SourcesElsewhere/Other.swift")
        text += self.record("Sources/../../Outside.swift")
        text += self.record()
        report, _ = self.lines(text)
        self.assertEqual(len(report), 1)

    def test_symlink_to_external_source_is_not_imported(self):
        outside = self.root / "Outside.swift"
        outside.write_text("let external = 1\n", encoding="utf-8")
        link = self.source.parent / "Link.swift"
        link.symlink_to(outside)
        report, _ = self.lines(self.record(link) + self.record())
        self.assertEqual(len(report), 1)

    def test_missing_current_source_is_rejected(self):
        text = self.record(self.source.parent / "Gone.swift")
        with self.assertRaisesRegex(ValueError, "source no longer exists"):
            convert_lcov(text, self.root)

    def test_stale_out_of_range_coverage_is_rejected(self):
        text = self.record(entries="DA:4,100")
        with self.assertRaisesRegex(ValueError, "exceeds current source bounds"):
            convert_lcov(text, self.root)

    def test_empty_or_test_only_reports_fail_instead_of_claiming_coverage(self):
        for text in ("", "TN:Empty\n", self.record(self.root / "Tests" / "Test.swift")):
            with self.subTest(text=text), self.assertRaisesRegex(ValueError, "No repository production"):
                convert_lcov(text, self.root)

    def test_invalid_da_records_are_rejected(self):
        for entry in ("DA:1", "DA:1,2,3,4", "DA:not-a-line,0", "DA:1,not-a-count", "DA:0,1", "DA:1,-1"):
            text = self.record(entries=entry)
            with self.subTest(entry=entry), self.assertRaises(ValueError):
                convert_lcov(text, self.root)

    def test_lines_before_source_and_truncated_source_records_are_rejected(self):
        for text in ("DA:1,2\n", f"SF:{self.source}\nDA:1,2\n",
                     f"SF:{self.source}\nSF:{self.source}\nDA:1,2\nend_of_record\n"):
            with self.subTest(text=text), self.assertRaises(ValueError):
                convert_lcov(text, self.root)

    def test_xml_paths_are_escaped_and_lines_are_sorted(self):
        source = self.source.parent / "A&Z.swift"
        source.write_text("a\nb\nc\n", encoding="utf-8")
        report = convert_lcov(self.record(source, entries="DA:3,0\nDA:1,1"), self.root)
        encoded = ET.tostring(report, encoding="unicode")
        self.assertIn("A&amp;Z.swift", encoded)
        parsed = ET.fromstring(encoded)
        self.assertEqual([line.attrib["lineNumber"] for line in parsed[0]], ["1", "3"])

    def test_entrypoint_replaces_old_report_with_current_observed_counts(self):
        lcov = self.root / "current-profile.lcov"
        lcov.write_text(self.record(entries="DA:1,0\nDA:3,4"), encoding="utf-8")
        output = self.root / "existing.xml"
        output.write_text("stale report", encoding="utf-8")
        stdout = io.StringIO()
        arguments = ["swiftpm_coverage.py", str(lcov), str(output), "--root", str(self.root)]
        with patch.object(sys, "argv", arguments), contextlib.redirect_stdout(stdout):
            main()
        report = ET.parse(output).getroot()
        self.assertEqual([line.attrib for line in report[0]], [
            {"lineNumber": "1", "covered": "false"},
            {"lineNumber": "3", "covered": "true"},
        ])
        self.assertIn("1/2 lines in 1 files", stdout.getvalue())

    def test_cli_writes_parseable_xml_and_reports_observed_totals(self):
        lcov = self.root / "real-profile.lcov"
        lcov.write_text(self.record(), encoding="utf-8")
        output = self.root / "output" / "coverage.xml"
        command = [sys.executable, str(Path(__file__).with_name("swiftpm_coverage.py")),
                   str(lcov), str(output), "--root", str(self.root)]
        result = subprocess.run(command, capture_output=True, text=True, check=False)
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn("1/2 lines in 1 files", result.stdout)
        self.assertEqual(ET.parse(output).getroot().tag, "coverage")


if __name__ == "__main__":
    unittest.main()
