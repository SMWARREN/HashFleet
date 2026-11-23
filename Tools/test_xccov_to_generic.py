import unittest
from unittest import mock
from pathlib import Path
import tempfile

from Tools.xccov_to_generic import (
    _is_admitted_source,
    _parse_file_coverage,
    _write_generic_xml,
    convert_xcresult,
)


class XccovToGenericTests(unittest.TestCase):
    def test_admitted_source_directories(self):
        with tempfile.TemporaryDirectory(prefix="xccov-test-") as tempdir:
            root = Path(tempdir)
            app_swift = root / "App" / "View.swift"
            app_swift.parent.mkdir(parents=True)
            app_swift.write_text("let a = 1\n", encoding="utf-8")

            mac_swift = root / "MacApp" / "MacView.swift"
            mac_swift.parent.mkdir(parents=True)
            mac_swift.write_text("let m = 2\n", encoding="utf-8")

            test_swift = root / "Tests" / "Test.swift"
            test_swift.parent.mkdir(parents=True)
            test_swift.write_text("let t = 3\n", encoding="utf-8")

            app_png = root / "App" / "Image.png"
            app_png.write_bytes(b"\x89PNG")

            self.assertTrue(_is_admitted_source(app_swift, root))
            self.assertTrue(_is_admitted_source(mac_swift, root))
            self.assertFalse(_is_admitted_source(test_swift, root))
            self.assertFalse(_is_admitted_source(app_png, root))

    def test_parse_file_coverage_filters_asterisk_and_bounds(self):
        output = """  1: *
  2: *
 10: 5
 11: 0
 12: *
 25: 1
 99: 3
"""
        lines = _parse_file_coverage(output, max_line=50)
        self.assertEqual(lines, {10: True, 11: False, 25: True})
        self.assertNotIn(99, lines, "Lines beyond file length must be ignored")
        self.assertNotIn(1, lines, "Non-executable lines marked with * must be ignored")

    def test_write_generic_xml(self):
        with tempfile.TemporaryDirectory(prefix="xccov-xml-") as tempdir:
            out = Path(tempdir) / "cov.xml"
            file_covs = {
                "App/View.swift": {1: True, 2: False, 5: True}
            }
            covered, total = _write_generic_xml(file_covs, out)
            self.assertEqual(covered, 2)
            self.assertEqual(total, 3)
            self.assertTrue(out.exists())
            text = out.read_text(encoding="utf-8")
            self.assertIn('<file path="App/View.swift">', text)
            self.assertIn('<lineToCover lineNumber="1" covered="true"', text)
            self.assertIn('<lineToCover lineNumber="2" covered="false"', text)

    @mock.patch("subprocess.check_output")
    def test_convert_xcresult_end_to_end(self, mock_subprocess):
        with tempfile.TemporaryDirectory(prefix="xccov-e2e-") as tempdir:
            root = Path(tempdir)
            source_file = root / "App" / "Main.swift"
            source_file.parent.mkdir(parents=True)
            source_file.write_text("line 1\nline 2\nline 3\n", encoding="utf-8")

            bundle = root / "test.xcresult"
            output = root / "coverage.xml"

            def mock_check_output(cmd, text=True):
                if "--file-list" in cmd:
                    return str(source_file)
                if "--file" in cmd:
                    return " 1: 1\n 2: 0\n 3: *\n"
                return ""

            mock_subprocess.side_effect = mock_check_output

            covered, total, files = convert_xcresult(bundle, output, root)
            self.assertEqual(covered, 1)
            self.assertEqual(total, 2)
            self.assertEqual(files, 1)
            self.assertTrue(output.exists())


if __name__ == "__main__":
    unittest.main()
