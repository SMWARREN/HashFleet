#!/usr/bin/env python3
"""Offline tests for Scripts/ci/sonar-scan-ci.py. Network, Docker and the scanner are mocked."""
import contextlib
import importlib.util
import io
import json
import os
from pathlib import Path
import sys
import tempfile
import types
import unittest
from unittest.mock import MagicMock, patch

SOURCE = Path(__file__).resolve().parents[1] / 'ci/sonar-scan-ci.py'


def load():
    stubs = {}
    for name in ('swift_sonar_kit', 'swift_sonar_kit.bootstrap', 'swift_sonar_kit.local_server', 'swift_sonar_kit.reports'):
        if name not in sys.modules:
            stubs[name] = types.ModuleType(name)
    stubs_attrs = {
        'swift_sonar_kit.bootstrap': {'ensure_environment': lambda *a, **k: {}},
        'swift_sonar_kit.local_server': {'ensure_local_server': lambda *a, **k: {}},
        'swift_sonar_kit.reports': {'swiftlint_report': lambda findings, root: {'issues': list(findings)}},
    }
    for name, attrs in stubs_attrs.items():
        if name in stubs:
            for key, value in attrs.items():
                setattr(stubs[name], key, value)
    with patch.dict(sys.modules, stubs):
        spec = importlib.util.spec_from_file_location('sonar_scan_ci', SOURCE)
        module = importlib.util.module_from_spec(spec)
        spec.loader.exec_module(module)
    return module


S = load()


class FakeResponse:
    def __init__(self, payload):
        self.payload = payload

    def __enter__(self):
        return self

    def __exit__(self, *args):
        return False

    def read(self):
        return json.dumps(self.payload).encode()


class GateDisplayTests(unittest.TestCase):
    def test_labels(self):
        self.assertEqual(S._gate_display('OK')[1], 'PASSED')
        self.assertEqual(S._gate_display('ERROR')[1], 'FAILED')
        self.assertEqual(S._gate_display('NONE')[1], 'NONE')


class FetchTests(unittest.TestCase):
    def test_measures_success_and_failure(self):
        payload = {'component': {'measures': [{'metric': 'coverage', 'value': '80.1'}, {'metric': 'bugs'}]}}
        with patch.object(S.urllib.request, 'urlopen', return_value=FakeResponse(payload)):
            self.assertEqual(S.fetch_measures('http://x', 't', 'k'), {'coverage': '80.1', 'bugs': '0'})
        with patch.object(S.urllib.request, 'urlopen', side_effect=OSError('down')), patch.object(S.time, 'sleep') as sleep:
            self.assertEqual(S.fetch_measures('http://x', 't', 'k'), {})
            self.assertEqual(sleep.call_count, 5)

    def test_gate_and_issues(self):
        with patch.object(S.urllib.request, 'urlopen', return_value=FakeResponse({'projectStatus': {'status': 'OK', 'conditions': [{'a': 1}]}})):
            self.assertEqual(S.fetch_gate_status('http://x', 't', 'k'), ('OK', [{'a': 1}]))
        with patch.object(S.urllib.request, 'urlopen', return_value=FakeResponse({'issues': [{'rule': 'r'}]})):
            self.assertEqual(S.fetch_issues('http://x', 't', 'k'), [{'rule': 'r'}])
        with patch.object(S.urllib.request, 'urlopen', side_effect=OSError('down')), contextlib.redirect_stderr(io.StringIO()):
            self.assertEqual(S.fetch_gate_status('http://x', 't', 'k'), ('UNKNOWN', []))
            self.assertEqual(S.fetch_issues('http://x', 't', 'k'), [])


class SummaryTests(unittest.TestCase):
    def test_step_summary_written_only_when_configured(self):
        with patch.dict(os.environ, {}, clear=True):
            self.assertIsNone(S.write_step_summary({}, 'OK', []))
        with tempfile.TemporaryDirectory() as tmp:
            path = Path(tmp) / 'summary.md'
            conditions = [{'metricKey': 'coverage', 'status': 'OK', 'comparator': 'LT', 'actualValue': '81', 'errorThreshold': '80'},
                          {'metricKey': 'bugs', 'status': 'ERROR', 'comparator': 'GT'}]
            with patch.dict(os.environ, {'GITHUB_STEP_SUMMARY': str(path)}):
                S.write_step_summary({'coverage': '81'}, 'OK', conditions)
            text = path.read_text()
            self.assertIn('Quality Gate Conditions', text)
            self.assertIn('81%', text)
            with patch.dict(os.environ, {'GITHUB_STEP_SUMMARY': str(Path(tmp) / 'missing/dir/x.md')}), \
                 contextlib.redirect_stderr(io.StringIO()):
                S.write_step_summary({}, 'ERROR', [])

    def test_fetch_and_report_prints_everything(self):
        issues = [{'component': 'k:a.swift', 'rule': 'r1', 'type': 'BUG', 'severity': 'MAJOR', 'line': 3, 'message': 'm'}]
        out = io.StringIO()
        with patch.object(S, 'fetch_measures', return_value={'coverage': '80.0'}), \
             patch.object(S, 'fetch_gate_status', return_value=('OK', [])), \
             patch.object(S, 'fetch_issues', return_value=issues), \
             patch.object(S, 'write_step_summary') as summary, contextlib.redirect_stdout(out):
            S.fetch_and_report_metrics('http://x', 't', 'k')
        self.assertIn('80.0%', out.getvalue())
        self.assertIn('DETECTED ISSUES', out.getvalue())
        summary.assert_called_once()
        out = io.StringIO()
        with patch.object(S, 'fetch_measures', return_value={}), patch.object(S, 'fetch_gate_status', return_value=('ERROR', [])), \
             patch.object(S, 'fetch_issues', return_value=[]), patch.object(S, 'write_step_summary'), contextlib.redirect_stdout(out):
            S.fetch_and_report_metrics('http://x', 't', 'k')
        self.assertNotIn('DETECTED ISSUES', out.getvalue())


class SetupTests(unittest.TestCase):
    def test_convert_swiftlint(self):
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            self.assertIsNone(S._convert_swiftlint(root, root))
            (root / 'swiftlint.json').write_text(json.dumps([{'rule_id': 'x'}]))
            result = S._convert_swiftlint(root, root)
            self.assertEqual(result, root / 'sonar-issues.json')
            self.assertTrue(result.exists())
            (root / 'swiftlint.json').write_text('{"not": "a list"}')
            self.assertIsNone(S._convert_swiftlint(root, root))
            (root / 'swiftlint.json').write_text('broken')
            with contextlib.redirect_stderr(io.StringIO()):
                self.assertIsNone(S._convert_swiftlint(root, root))

    def test_collect_coverage_flags(self):
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            cov = root / 'build/coverage'
            cov.mkdir(parents=True)
            with contextlib.redirect_stdout(io.StringIO()):
                self.assertEqual(S._collect_coverage_flags(cov, root), [])
                for name in ('mac.xcresult', 'swift-package-coverage.xml', 'mac-coverage.xml', 'python-coverage.xml', 'lcov.info'):
                    (cov / name).write_text('x')
                flags = S._collect_coverage_flags(cov, root)
            joined = ' '.join(flags)
            self.assertIn('sonar.apple.resultBundlePath', joined)
            self.assertIn('sonar.coverageReportPaths=build/coverage/swift-package-coverage.xml,build/coverage/mac-coverage.xml', joined)
            self.assertIn('sonar.python.coverage.reportPaths', joined)
            self.assertIn('sonar.javascript.lcov.reportPaths', joined)

    def test_start_server_retries(self):
        with patch.object(S, 'ensure_local_server', side_effect=[RuntimeError('a'), {'url': 'u'}]), \
             patch.object(S.time, 'sleep'), contextlib.redirect_stdout(io.StringIO()):
            self.assertEqual(S._start_server(Path('.')), {'url': 'u'})
        with patch.object(S, 'ensure_local_server', side_effect=RuntimeError('x')), \
             patch.object(S.time, 'sleep'), contextlib.redirect_stdout(io.StringIO()):
            with self.assertRaises(RuntimeError):
                S._start_server(Path('.'))


class MainTests(unittest.TestCase):
    def test_main_builds_scanner_command(self):
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            completed = MagicMock(returncode=3)
            with patch.object(S, 'ROOT', root), \
                 patch.object(S, 'ensure_environment', return_value={'tools': {'sonarScanner': {'path': '/bin/scanner'}}}), \
                 patch.object(S, '_start_server', return_value={'url': 'http://sonar', 'token': 'tok'}), \
                 patch.object(S.subprocess, 'run', return_value=completed) as run, \
                 patch.object(S, 'fetch_and_report_metrics') as report, contextlib.redirect_stdout(io.StringIO()):
                (root / 'build/coverage').mkdir(parents=True)
                (root / 'build/coverage/swiftlint.json').write_text('[]')
                code = S.main()
            self.assertEqual(code, 3)
            args = run.call_args.args[0]
            self.assertEqual(args[0], '/bin/scanner')
            self.assertIn('-Dsonar.qualitygate.wait=true', args)
            self.assertTrue(any(a.startswith('-Dsonar.externalIssuesReportPaths=') for a in args))
            report.assert_called_once_with('http://sonar', 'tok', 'hashfleet')


if __name__ == '__main__':
    unittest.main()
