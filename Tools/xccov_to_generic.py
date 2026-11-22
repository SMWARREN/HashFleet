#!/usr/bin/env python3
"""Convert Xcode xcresult coverage archive to Sonar generic test coverage XML.
"""
from __future__ import annotations

import argparse
import concurrent.futures
from pathlib import Path
import re
import subprocess
import sys
import xml.etree.ElementTree as ET

ADMITTED_DIRS = (
    "App",
    "MacApp",
    "MacMenuBar",
    "NotificationService",
    "Shared",
    "Sources",
    "WatchApp",
    "WatchWidgets",
    "Widgets",
)

LINE_PATTERN = re.compile(r"^\s*(\d+):\s*(\*|\d+)\s*$")


def _is_admitted_source(file_path: Path, root: Path) -> bool:
    try:
        rel = file_path.relative_to(root)
    except ValueError:
        return False
    parts = rel.parts
    if not parts or parts[0] not in ADMITTED_DIRS or file_path.suffix != ".swift":
        return False
    return file_path.is_file()


def _parse_file_coverage(lines_output: str, max_line: int) -> dict[int, bool]:
    lines: dict[int, bool] = {}
    for entry in lines_output.splitlines():
        match = LINE_PATTERN.match(entry)
        if not match:
            continue
        line_num = int(match.group(1))
        val = match.group(2)
        if val == "*" or line_num > max_line or line_num <= 0:
            continue
        lines[line_num] = int(val) > 0
    return lines


def convert_xcresult(bundle: Path, output: Path, root: Path) -> tuple[int, int, int]:
    root = root.resolve()
    bundle = bundle.resolve()

    raw_files = subprocess.check_output(
        ["xcrun", "xccov", "view", "--archive", "--file-list", str(bundle)],
        text=True,
    ).splitlines()

    admitted_files: list[Path] = []
    for raw in raw_files:
        p = Path(raw).resolve()
        if _is_admitted_source(p, root):
            admitted_files.append(p)

    def extract_one(p: Path) -> tuple[str, dict[int, bool]]:
        out = subprocess.check_output(
            ["xcrun", "xccov", "view", "--archive", "--file", str(p), str(bundle)],
            text=True,
        )
        line_limit = len(p.read_text(encoding="utf-8").splitlines())
        lines = _parse_file_coverage(out, line_limit)
        return p.relative_to(root).as_posix(), lines

    file_coverages: dict[str, dict[int, bool]] = {}
    with concurrent.futures.ThreadPoolExecutor(max_workers=8) as executor:
        for rel_path, lines in executor.map(extract_one, admitted_files):
            if lines:
                file_coverages[rel_path] = lines

    root_elem = ET.Element("coverage", version="1")
    total_lines = 0
    total_covered = 0

    for path_str in sorted(file_coverages):
        lines = file_coverages[path_str]
        file_elem = ET.SubElement(root_elem, "file", path=path_str)
        for num in sorted(lines):
            cov = lines[num]
            total_lines += 1
            if cov:
                total_covered += 1
            ET.SubElement(
                file_elem,
                "lineToCover",
                lineNumber=str(num),
                covered="true" if cov else "false",
            )

    output.parent.mkdir(parents=True, exist_ok=True)
    ET.indent(root_elem)
    ET.ElementTree(root_elem).write(output, encoding="utf-8", xml_declaration=True)

    return total_covered, total_lines, len(file_coverages)


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("bundle", type=Path, help="Path to .xcresult bundle")
    parser.add_argument("output", type=Path, help="Path to output generic XML")
    parser.add_argument("--root", type=Path, default=Path(__file__).resolve().parent.parent)
    args = parser.parse_args()

    if not args.bundle.exists():
        print(f"Error: xcresult bundle does not exist: {args.bundle}", file=sys.stderr)
        return 1

    covered, total, files_count = convert_xcresult(args.bundle, args.output, args.root)
    pct = (covered / total * 100) if total > 0 else 0.0
    print(f"Exported Xcode coverage: {covered}/{total} lines ({pct:.1f}%) in {files_count} files to {args.output}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
