#!/usr/bin/env python3
"""Run SonarQube analysis with Docker, sonar-apple, and collected CI coverage artifacts.
"""
from __future__ import annotations

import json
import os
from pathlib import Path
import subprocess
import sys
import time
import urllib.parse
import urllib.request

from swift_sonar_kit.bootstrap import ensure_environment
from swift_sonar_kit.local_server import ensure_local_server
from swift_sonar_kit.reports import swiftlint_report

ROOT = Path(__file__).resolve().parent.parent.parent


TABLE_DIVIDER = "| :--- | :--- |"
JSON_MIME = "application/json"


def _gate_display(status: str) -> tuple[str, str]:
    if status == "OK":
        return "🟢", "PASSED"
    if status == "ERROR":
        return "🔴", "FAILED"
    return "⚪", status


def fetch_measures(url: str, token: str, project_key: str) -> dict[str, str]:
    headers = {"Authorization": f"Bearer {token}", "Accept": JSON_MIME}
    metric_keys = [
        "alert_status", "bugs", "vulnerabilities", "code_smells", "security_hotspots",
        "coverage", "lines_to_cover", "uncovered_lines", "line_coverage", "branch_coverage",
        "duplicated_lines", "duplicated_blocks", "duplicated_lines_density", "duplicated_files",
        "ncloc", "complexity", "cognitive_complexity",
        "reliability_rating", "security_rating", "sqale_rating",
    ]
    query = urllib.parse.urlencode({"component": project_key, "metricKeys": ",".join(metric_keys)})
    measures_url = f"{url}/api/measures/component?{query}"
    for _ in range(5):
        try:
            req = urllib.request.Request(measures_url, headers=headers)
            with urllib.request.urlopen(req, timeout=15) as resp:
                data = json.loads(resp.read().decode("utf-8"))
                measures = {m["metric"]: m.get("value", "0") for m in data.get("component", {}).get("measures", [])}
                if measures:
                    return measures
        except Exception:
            time.sleep(2)
    return {}


def fetch_gate_status(url: str, token: str, project_key: str) -> tuple[str, list[dict]]:
    headers = {"Authorization": f"Bearer {token}", "Accept": JSON_MIME}
    gate_url = f"{url}/api/qualitygates/project_status?{urllib.parse.urlencode({'projectKey': project_key})}"
    try:
        req = urllib.request.Request(gate_url, headers=headers)
        with urllib.request.urlopen(req, timeout=15) as resp:
            data = json.loads(resp.read().decode("utf-8"))
            status = data.get("projectStatus", {}).get("status", "UNKNOWN")
            conditions = data.get("projectStatus", {}).get("conditions", [])
            return status, conditions
    except Exception as e:
        print(f"Warning: could not fetch Quality Gate status: {e}", file=sys.stderr)
        return "UNKNOWN", []


def fetch_issues(url: str, token: str, project_key: str) -> list[dict]:
    headers = {"Authorization": f"Bearer {token}", "Accept": JSON_MIME}
    issues_url = f"{url}/api/issues/search?{urllib.parse.urlencode({'componentKeys': project_key, 'resolved': 'false', 'ps': 100})}"
    try:
        req = urllib.request.Request(issues_url, headers=headers)
        with urllib.request.urlopen(req, timeout=15) as resp:
            data = json.loads(resp.read().decode("utf-8"))
            return data.get("issues", [])
    except Exception as e:
        print(f"Warning: could not fetch SonarQube issues: {e}", file=sys.stderr)
        return []


def write_step_summary(measures: dict[str, str], gate_status: str, conditions: list[dict]) -> None:
    summary_path = os.environ.get("GITHUB_STEP_SUMMARY")
    if not summary_path:
        return
    status_icon, qg_label = _gate_display(gate_status)

    def fmt(key: str, suffix: str = "", default: str = "N/A") -> str:
        val = measures.get(key)
        return f"{val}{suffix}" if val is not None else default

    md = [
        f"## {status_icon} SonarQube Analysis Results",
        "",
        f"**Quality Gate Status:** **{qg_label}**",
        "",
        "### 📊 Code Coverage",
        "| Metric | Value |",
        TABLE_DIVIDER,
        f"| **Overall Coverage** | **{fmt('coverage', '%')}** |",
        f"| **Line Coverage** | {fmt('line_coverage', '%')} |",
        f"| **Branch Coverage** | {fmt('branch_coverage', '%')} |",
        f"| **Lines to Cover** | {fmt('lines_to_cover')} |",
        f"| **Uncovered Lines** | {fmt('uncovered_lines')} |",
        "",
        "### 🧬 Duplications",
        "| Metric | Value |",
        TABLE_DIVIDER,
        f"| **Duplicated Lines** | **{fmt('duplicated_lines')}** ({fmt('duplicated_lines_density', '%')}) |",
        f"| **Duplicated Blocks** | {fmt('duplicated_blocks')} |",
        f"| **Duplicated Files** | {fmt('duplicated_files')} |",
        "",
        "### 🛡️ Issues & Maintainability",
        "| Metric | Count |",
        TABLE_DIVIDER,
        f"| **Bugs** | {fmt('bugs', default='0')} |",
        f"| **Vulnerabilities** | {fmt('vulnerabilities', default='0')} |",
        f"| **Code Smells** | {fmt('code_smells', default='0')} |",
        f"| **Security Hotspots** | {fmt('security_hotspots', default='0')} |",
        f"| **Lines of Code (NCLOC)** | {fmt('ncloc')} |",
        f"| **Complexity** | {fmt('complexity')} |",
        "",
    ]
    if conditions:
        md.extend([
            "### 📋 Quality Gate Conditions",
            "| Metric | Status | Operator | Value | Threshold |",
            "| :--- | :--- | :--- | :--- | :--- |",
        ])
        for c in conditions:
            c_status = "🟢" if c.get("status") == "OK" else "🔴"
            md.append(f"| `{c.get('metricKey')}` | {c_status} {c.get('status')} | `{c.get('comparator')}` | `{c.get('actualValue', 'N/A')}` | `{c.get('errorThreshold', 'N/A')}` |")
        md.append("")
    try:
        with open(summary_path, "a", encoding="utf-8") as f:
            f.write("\n".join(md) + "\n")
    except Exception as e:
        print(f"Warning: could not write GITHUB_STEP_SUMMARY: {e}", file=sys.stderr)


def fetch_and_report_metrics(url: str, token: str, project_key: str) -> None:
    measures = fetch_measures(url, token, project_key)
    gate_status, conditions = fetch_gate_status(url, token, project_key)
    issues_list = fetch_issues(url, token, project_key)

    status_icon, qg_label = _gate_display(gate_status)

    def _fmt(key: str, suffix: str = "", default: str = "N/A") -> str:
        val = measures.get(key)
        return f"{val}{suffix}" if val is not None else default

    # 1. Print formatted breakdown directly to GitHub Actions console log
    lines = [
        "",
        "=" * 72,
        f"               SONARQUBE ANALYSIS RESULTS ({project_key})",
        "=" * 72,
        f"Quality Gate Status:     {status_icon} {qg_label}",
        f"Lines of Code (NCLOC):   {_fmt('ncloc')}",
        f"Complexity:              {_fmt('complexity')}",
        "-" * 72,
        "CODE COVERAGE:",
        f"  Overall Coverage:      {_fmt('coverage', '%')}",
        f"  Line Coverage:         {_fmt('line_coverage', '%')}",
        f"  Branch Coverage:       {_fmt('branch_coverage', '%')}",
        f"  Lines to Cover:        {_fmt('lines_to_cover')}",
        f"  Uncovered Lines:       {_fmt('uncovered_lines')}",
        "-" * 72,
        "DUPLICATIONS:",
        f"  Duplicated Lines:      {_fmt('duplicated_lines')} ({_fmt('duplicated_lines_density', '%')})",
        f"  Duplicated Blocks:     {_fmt('duplicated_blocks')}",
        f"  Duplicated Files:      {_fmt('duplicated_files')}",
        "-" * 72,
        "ISSUES & SECURITY:",
        f"  Bugs:                  {_fmt('bugs', default='0')}",
        f"  Vulnerabilities:       {_fmt('vulnerabilities', default='0')}",
        f"  Code Smells:           {_fmt('code_smells', default='0')}",
        f"  Security Hotspots:     {_fmt('security_hotspots', default='0')}",
        "=" * 72,
    ]
    if issues_list:
        lines.append("\nDETECTED ISSUES:")
        for iss in issues_list:
            comp = iss.get("component", "").replace(f"{project_key}:", "")
            rule = iss.get("rule", "")
            lines.append(f"  [{iss.get('type')}] {iss.get('severity')} - {comp}:{iss.get('line', '?')} ({rule}) - {iss.get('message')}")
        lines.append("=" * 72)
    lines.append("")
    print("\n".join(lines))

    # 2. Append markdown summary to GitHub Step Summary if running in Actions
    write_step_summary(measures, gate_status, conditions)


def _convert_swiftlint(coverage_dir: Path, root: Path) -> Path | None:
    lint_json = coverage_dir / "swiftlint.json"
    external_issues = coverage_dir / "sonar-issues.json"
    if lint_json.exists():
        try:
            findings = json.loads(lint_json.read_text(encoding="utf-8"))
            if isinstance(findings, list):
                converted = swiftlint_report(findings, root)
                external_issues.write_text(json.dumps(converted, indent=2), encoding="utf-8")
                print(f"Imported {len(converted.get('issues', []))} SwiftLint issues.")
                return external_issues
        except Exception as e:
            print(f"Warning: could not convert SwiftLint findings: {e}", file=sys.stderr)
    return None


def _start_server(root: Path) -> dict:
    for attempt in range(1, 6):
        try:
            print(f"Ensuring SonarQube container with sonar-apple is ready (attempt {attempt}/5)...")
            return ensure_local_server(root, "hashfleet")
        except Exception as exc:
            if attempt == 5:
                raise
            print(f"Sonar server setup attempt {attempt} failed ({exc}). Retrying in 10s...")
            time.sleep(10)
    raise RuntimeError("Could not connect to SonarQube container")


def _collect_coverage_flags(coverage_dir: Path, root: Path) -> list[str]:
    flags: list[str] = []
    xcresult = coverage_dir / "mac.xcresult"
    if xcresult.exists():
        flags.append(f"-Dsonar.apple.resultBundlePath={xcresult.relative_to(root)}")
        print(f"Adding native result bundle: {xcresult.relative_to(root)}")

    cov_reports: list[str] = []
    swift_cov = coverage_dir / "swift-package-coverage.xml"
    if swift_cov.exists():
        cov_reports.append(str(swift_cov.relative_to(root)))
        print(f"Adding Swift package coverage: {swift_cov.relative_to(root)}")

    mac_cov = coverage_dir / "mac-coverage.xml"
    if mac_cov.exists():
        cov_reports.append(str(mac_cov.relative_to(root)))
        print(f"Adding Mac app coverage: {mac_cov.relative_to(root)}")

    if cov_reports:
        flags.append(f"-Dsonar.coverageReportPaths={','.join(cov_reports)}")

    python_cov = coverage_dir / "python-coverage.xml"
    if python_cov.exists():
        flags.append(f"-Dsonar.python.coverage.reportPaths={python_cov.relative_to(root)}")
        print(f"Adding Python coverage: {python_cov.relative_to(root)}")

    website_lcov = coverage_dir / "lcov.info"
    if website_lcov.exists():
        flags.append(f"-Dsonar.javascript.lcov.reportPaths={website_lcov.relative_to(root)}")
        print(f"Adding Website LCOV coverage: {website_lcov.relative_to(root)}")

    return flags


def main() -> int:
    coverage_dir = ROOT / "build" / "coverage"
    coverage_dir.mkdir(parents=True, exist_ok=True)

    external_issues = _convert_swiftlint(coverage_dir, ROOT)

    print("Preparing SonarScanner...")
    setup = ensure_environment(ROOT, tools={"sonarScanner": "8.3.1"})
    scanner_bin = setup["tools"]["sonarScanner"]["path"]

    server = _start_server(ROOT)
    url = server["url"]
    token = server["token"]

    args = [
        scanner_bin,
        f"-Dsonar.host.url={url}",
        f"-Dsonar.token={token}",
        "-Dsonar.qualitygate.wait=true",
        "-Dsonar.qualitygate.timeout=300",
    ]
    args.extend([
        "-Dsonar.issue.ignore.multicriteria=a11y1,a11y2,a11y3,a11y4,a11y5,a11y6,a11y7,a11y8,a11y9,a11y10",
        "-Dsonar.issue.ignore.multicriteria.a11y1.ruleKey=typescript:S6847",
        "-Dsonar.issue.ignore.multicriteria.a11y1.resourceKey=**/components/**",
        "-Dsonar.issue.ignore.multicriteria.a11y2.ruleKey=typescript:S6848",
        "-Dsonar.issue.ignore.multicriteria.a11y2.resourceKey=**/components/**",
        "-Dsonar.issue.ignore.multicriteria.a11y3.ruleKey=typescript:S6853",
        "-Dsonar.issue.ignore.multicriteria.a11y3.resourceKey=**/components/**",
        "-Dsonar.issue.ignore.multicriteria.a11y4.ruleKey=css:S4667",
        "-Dsonar.issue.ignore.multicriteria.a11y4.resourceKey=**/components/**",
        "-Dsonar.issue.ignore.multicriteria.a11y5.ruleKey=css:S6847",
        "-Dsonar.issue.ignore.multicriteria.a11y5.resourceKey=**/components/**",
        "-Dsonar.issue.ignore.multicriteria.a11y6.ruleKey=css:S5257",
        "-Dsonar.issue.ignore.multicriteria.a11y6.resourceKey=**/components/**",
        "-Dsonar.issue.ignore.multicriteria.a11y7.ruleKey=css:S6848",
        "-Dsonar.issue.ignore.multicriteria.a11y7.resourceKey=**/components/**",
        "-Dsonar.issue.ignore.multicriteria.a11y8.ruleKey=typescript:S6845",
        "-Dsonar.issue.ignore.multicriteria.a11y8.resourceKey=**/components/**",
        "-Dsonar.issue.ignore.multicriteria.a11y9.ruleKey=typescript:S6819",
        "-Dsonar.issue.ignore.multicriteria.a11y9.resourceKey=**/components/**",
        "-Dsonar.issue.ignore.multicriteria.a11y10.ruleKey=css:S7924",
        "-Dsonar.issue.ignore.multicriteria.a11y10.resourceKey=**/components/**",
    ])
    args.extend(_collect_coverage_flags(coverage_dir, ROOT))

    if external_issues is not None and external_issues.exists():
        args.append(f"-Dsonar.externalIssuesReportPaths={external_issues.relative_to(ROOT)}")

    print("Starting SonarScanner analysis...")
    process = subprocess.run(args, cwd=ROOT)

    fetch_and_report_metrics(url, token, "hashfleet")
    return process.returncode


if __name__ == "__main__":
    sys.exit(main())
