import unittest
from pathlib import Path
import tempfile

from Tools.xccov_to_generic import (
    _is_admitted_source,
    _parse_file_coverage,
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


if __name__ == "__main__":
    unittest.main()
