#!/usr/bin/env python3
"""Match the expansion matrix to actual full Swift/XCTest results, never test totals alone.

Usage: python3 Tools/verify_expansion_acceptance.py MATRIX CORE_LOG NATIVE_TESTS_JSON NATIVE_SUMMARY_JSON
The device-install row is deliberately reported as a separate observed release gate.
"""
from __future__ import annotations

import json
import re
import sys
from pathlib import Path


def walk(value):
    if isinstance(value, dict):
        yield value
        for child in value.values():
            yield from walk(child)
    elif isinstance(value, list):
        for child in value:
            yield from walk(child)


def parse_core_results(core: str, results: dict[str, list[str]]) -> None:
    for match in re.finditer(r"✔ Test (\w+)\([^\n]*\)(?: with \d+ test cases)? passed", core):
        results.setdefault(match[1], []).append("Passed")


def parse_native_results(native_data: object, results: dict[str, list[str]]) -> None:
    for node in walk(native_data):
        if node.get("nodeType") == "Test Case":
            name = node.get("name", "").split("(")[0]
            results.setdefault(name, []).append(node.get("result", "Unknown"))


def check_run_failures(core: str, summary: dict[str, object]) -> list[str]:
    failures: list[str] = []
    if not re.search(r"✔ Test run with \d+ tests in \d+ suites passed", core):
        failures.append("Core full-run completion missing")
    if (
        summary.get("result") != "Passed"
        or summary.get("failedTests") != 0
        or summary.get("skippedTests") != 0
    ):
        failures.append("Native full run is not entirely passed without skips")
    return failures


def evaluate_requirement_row(
    row: str,
    results: dict[str, list[str]],
    unique: set[str],
    failures: list[str],
) -> None:
    if not re.match(r"\| P\d\d \|", row):
        return
    requirement = row.split("|")[1].strip()
    names = re.findall(r"`([A-Za-z]\w+)`", row)
    if not names:
        print(requirement + ": Direct release observation required, see matrix")
        return
    observations: list[str] = []
    for name in names:
        unique.add(name)
        states = results.get(name, ["MISSING"])
        state = "Passed" if all(s == "Passed" for s in states) else "/".join(states)
        observations.append(name + "=" + state)
        if state != "Passed":
            failures.append(requirement + ": " + name + "=" + state)
    print(requirement + ": " + ", ".join(observations))


def main() -> int:
    matrix, core_path, native_path, summary_path = map(Path, sys.argv[1:])
    core = core_path.read_text()
    summary = json.loads(summary_path.read_text())
    native_data = json.loads(native_path.read_text())

    results: dict[str, list[str]] = {}
    parse_core_results(core, results)
    parse_native_results(native_data, results)

    failures = check_run_failures(core, summary)

    unique: set[str] = set()
    requirement_table = matrix.read_text().split("## Current observations", 1)[0]
    for row in requirement_table.splitlines():
        evaluate_requirement_row(row, results, unique, failures)

    print(f"Matched {len(unique)} unique named checks. Device delivery is not inferred from tests.")
    if failures:
        print("\n".join(failures), file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
