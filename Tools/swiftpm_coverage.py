#!/usr/bin/env python3
"""Convert real llvm-cov LCOV package output to Sonar generic line coverage.

Run SwiftPM tests with --enable-code-coverage, then export their profdata with
llvm-cov export --format=lcov. Only repository Sources/*.swift records are
imported here. Test and dependency records are not production coverage.
Only physical-line DA observations are converted. Aggregate LF/LH summaries
are not expanded into estimated or duplicated source-line observations.
This never estimates executable lines or turns absent data into a pass.
"""

from __future__ import annotations

import argparse
from pathlib import Path
import xml.etree.ElementTree as ET


def _production_source(raw_source: str, root: Path) -> tuple[str, int] | None:
    """Resolve an admitted real Swift source and its current physical line limit."""
    raw_path = Path(raw_source)
    path = (root / raw_path).resolve() if not raw_path.is_absolute() else raw_path.resolve()
    if not path.is_relative_to(root / "Sources") or path.suffix != ".swift":
        return None
    relative_path = path.relative_to(root).as_posix()
    if not path.is_file():
        raise ValueError(f"Coverage source no longer exists: {relative_path}")
    return relative_path, len(path.read_text(encoding="utf-8").splitlines())


def _parse_line_observation(entry: str) -> tuple[int, int]:
    """Validate DA fields even when their source record is not production code."""
    fields = entry.split(",")
    if len(fields) not in (2, 3):
        raise ValueError("Invalid LCOV DA entry")
    try:
        number, count = int(fields[0]), int(fields[1])
    except ValueError as error:
        raise ValueError("LCOV line and count must be integers") from error
    if number <= 0 or count < 0:
        raise ValueError("LCOV line must be positive and count non-negative")
    return number, count


def _record_line(entry: str, source: tuple[str, int] | None,
                 files: dict[str, dict[int, bool]]) -> None:
    number, count = _parse_line_observation(entry)
    if source is None:
        return
    path, line_limit = source
    if number > line_limit:
        raise ValueError(f"Coverage exceeds current source bounds: {path}:{number}")
    lines = files.setdefault(path, {})
    lines[number] = lines.get(number, False) or count > 0


def _coverage_xml(files: dict[str, dict[int, bool]]) -> ET.Element:
    coverage = ET.Element("coverage", version="1")
    for path, lines in sorted(files.items()):
        file_element = ET.SubElement(coverage, "file", path=path)
        for number, covered in sorted(lines.items()):
            ET.SubElement(file_element, "lineToCover", lineNumber=str(number),
                          covered="true" if covered else "false")
    return coverage


def convert_lcov(text: str, root: Path) -> ET.Element:
    """Preserve every reported production DA line and its observed hit status."""
    root = root.resolve()
    files: dict[str, dict[int, bool]] = {}
    current = None
    in_record = False
    for entry in text.splitlines():
        if entry.startswith("SF:"):
            if in_record:
                raise ValueError("LCOV source record has no end_of_record")
            in_record = True
            current = _production_source(entry[3:], root)
        elif entry.startswith("DA:"):
            if not in_record:
                raise ValueError("LCOV DA entry has no source record")
            _record_line(entry[3:], current, files)
        elif entry == "end_of_record":
            current = None
            in_record = False
    if in_record:
        raise ValueError("LCOV source record has no end_of_record")
    if not files:
        raise ValueError("No repository production Swift line coverage was found")
    return _coverage_xml(files)


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("lcov", type=Path)
    parser.add_argument("output", type=Path)
    parser.add_argument("--root", type=Path, default=Path(__file__).resolve().parent.parent)
    args = parser.parse_args()
    coverage = convert_lcov(args.lcov.read_text(encoding="utf-8"), args.root)
    args.output.parent.mkdir(parents=True, exist_ok=True)
    ET.indent(coverage)
    ET.ElementTree(coverage).write(args.output, encoding="utf-8", xml_declaration=True)
    lines = coverage.findall("./file/lineToCover")
    covered = sum(line.attrib["covered"] == "true" for line in lines)
    print(f"Imported actual package coverage: {covered}/{len(lines)} lines in {len(coverage)} files")


if __name__ == "__main__":
    main()
