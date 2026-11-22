#!/usr/bin/env python3
"""Run SonarQube analysis with Docker, sonar-apple, and collected CI coverage artifacts.
"""
from __future__ import annotations

import json
import os
from pathlib import Path
import subprocess
import sys

from swift_sonar_kit.bootstrap import ensure_environment
from swift_sonar_kit.local_server import ensure_local_server
from swift_sonar_kit.reports import swiftlint_report

ROOT = Path(__file__).resolve().parent.parent.parent


def main() -> int:
    coverage_dir = ROOT / "build" / "coverage"
    coverage_dir.mkdir(parents=True, exist_ok=True)

    # 1. Convert SwiftLint findings to Sonar external issues format if present
    lint_json = coverage_dir / "swiftlint.json"
    external_issues = coverage_dir / "sonar-issues.json"
    if lint_json.exists():
        try:
            findings = json.loads(lint_json.read_text(encoding="utf-8"))
            if isinstance(findings, list):
                converted = swiftlint_report(findings, ROOT)
                external_issues.write_text(json.dumps(converted, indent=2), encoding="utf-8")
                print(f"Imported {len(converted.get('issues', []))} SwiftLint issues.")
        except Exception as e:
            print(f"Warning: could not convert SwiftLint findings: {e}", file=sys.stderr)

    # 2. Bootstrap pinned SonarScanner (cross-platform Linux/macOS)
    print("Preparing SonarScanner...")
    setup = ensure_environment(ROOT, tools={"sonarScanner": "8.3.1"})
    scanner_bin = setup["tools"]["sonarScanner"]["path"]

    # 3. Ensure local Docker SonarQube container with sonar-apple is running
    print("Ensuring SonarQube container with sonar-apple is ready...")
    server = ensure_local_server(ROOT, "hashfleet")
    url = server["url"]
    token = server["token"]

    # 4. Assemble scanner arguments with coverage reports
    args = [
        scanner_bin,
        f"-Dsonar.host.url={url}",
        f"-Dsonar.token={token}",
        "-Dsonar.qualitygate.wait=true",
        "-Dsonar.qualitygate.timeout=300",
    ]

    xcresult = coverage_dir / "mac.xcresult"
    if xcresult.exists():
        args.append(f"-Dsonar.apple.resultBundlePath={xcresult.relative_to(ROOT)}")
        print(f"Adding native result bundle: {xcresult.relative_to(ROOT)}")

    swift_cov = coverage_dir / "swift-package-coverage.xml"
    if swift_cov.exists():
        args.append(f"-Dsonar.coverageReportPaths={swift_cov.relative_to(ROOT)}")
        print(f"Adding Swift package coverage: {swift_cov.relative_to(ROOT)}")

    python_cov = coverage_dir / "python-coverage.xml"
    if python_cov.exists():
        args.append(f"-Dsonar.python.coverage.reportPaths={python_cov.relative_to(ROOT)}")
        print(f"Adding Python coverage: {python_cov.relative_to(ROOT)}")

    website_lcov = coverage_dir / "lcov.info"
    if website_lcov.exists():
        args.append(f"-Dsonar.javascript.lcov.reportPaths={website_lcov.relative_to(ROOT)}")
        print(f"Adding Website LCOV coverage: {website_lcov.relative_to(ROOT)}")

    if external_issues.exists():
        args.append(f"-Dsonar.externalIssuesReportPaths={external_issues.relative_to(ROOT)}")

    # 5. Run scanner
    print("Starting SonarScanner analysis...")
    process = subprocess.run(args, cwd=ROOT)
    return process.returncode


if __name__ == "__main__":
    sys.exit(main())
