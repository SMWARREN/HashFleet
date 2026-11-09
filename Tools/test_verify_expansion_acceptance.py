import io
import json
import sys
import tempfile
import unittest
from contextlib import redirect_stderr, redirect_stdout
from pathlib import Path

if __package__:
    from .verify_expansion_acceptance import (
        check_run_failures,
        evaluate_requirement_row,
        main,
        parse_core_results,
        parse_native_results,
        walk,
    )
else:
    from verify_expansion_acceptance import (
        check_run_failures,
        evaluate_requirement_row,
        main,
        parse_core_results,
        parse_native_results,
        walk,
    )


class VerifyExpansionAcceptanceTests(unittest.TestCase):
    def test_walk_extracts_nested_dictionaries(self):
        nested = {
            "a": 1,
            "b": [{"c": 2}, {"d": [{"e": 3}]}],
            "f": {"g": 4},
        }
        dicts = list(walk(nested))
        self.assertEqual(len(dicts), 5)

    def test_parse_core_results_extracts_passed_tests(self):
        log = (
            "✔ Test TestAlpha() passed\n"
            "✔ Test TestBeta() with 3 test cases passed\n"
            "✔ Test run with 2 tests in 2 suites passed\n"
        )
        results: dict[str, list[str]] = {}
        parse_core_results(log, results)
        self.assertEqual(results, {"TestAlpha": ["Passed"], "TestBeta": ["Passed"]})

    def test_parse_native_results_extracts_test_cases(self):
        tree = {
            "children": [
                {
                    "nodeType": "Test Suite",
                    "children": [
                        {"nodeType": "Test Case", "name": "testGamma()", "result": "Passed"},
                        {"nodeType": "Test Case", "name": "testDelta()", "result": "Failed"},
                    ],
                }
            ]
        }
        results: dict[str, list[str]] = {}
        parse_native_results(tree, results)
        self.assertEqual(results, {"testGamma": ["Passed"], "testDelta": ["Failed"]})

    def test_check_run_failures_validates_core_and_summary(self):
        valid_core = "✔ Test run with 10 tests in 2 suites passed"
        valid_summary = {"result": "Passed", "failedTests": 0, "skippedTests": 0}

        self.assertEqual(check_run_failures(valid_core, valid_summary), [])

        missing_core_failures = check_run_failures("running...", valid_summary)
        self.assertIn("Core full-run completion missing", missing_core_failures)

        failed_summary = {"result": "Failed", "failedTests": 1, "skippedTests": 0}
        summary_failures = check_run_failures(valid_core, failed_summary)
        self.assertIn("Native full run is not entirely passed without skips", summary_failures)

    def test_evaluate_requirement_row(self):
        results = {"TestAlpha": ["Passed"], "TestBeta": ["Failed"]}
        unique: set[str] = set()
        failures: list[str] = []

        out = io.StringIO()
        with redirect_stdout(out):
            evaluate_requirement_row("| irrelevant | text |", results, unique, failures)
        self.assertEqual(out.getvalue(), "")

        with redirect_stdout(out):
            evaluate_requirement_row("| P01 | Manual test only |", results, unique, failures)
        self.assertIn("Direct release observation required", out.getvalue())

        out = io.StringIO()
        with redirect_stdout(out):
            evaluate_requirement_row(
                "| P02 | Covers `TestAlpha` and `TestBeta` |",
                results,
                unique,
                failures,
            )
        self.assertEqual(unique, {"TestAlpha", "TestBeta"})
        self.assertIn("P02: TestBeta=Failed", failures)

    def test_main_end_to_end_success_and_failure(self):
        with tempfile.TemporaryDirectory() as temp_dir:
            temp_path = Path(temp_dir)
            matrix = temp_path / "matrix.md"
            core_log = temp_path / "core.log"
            native_json = temp_path / "native.json"
            summary_json = temp_path / "summary.json"

            matrix.write_text(
                "| P01 | Requirement `TestOne` and `TestTwo` |\n"
                "## Current observations\n"
                "Notes here\n"
            )
            core_log.write_text(
                "✔ Test TestOne() passed\n"
                "✔ Test run with 1 tests in 1 suites passed\n"
            )
            native_json.write_text(
                json.dumps({
                    "children": [
                        {"nodeType": "Test Case", "name": "TestTwo()", "result": "Passed"}
                    ]
                })
            )
            summary_json.write_text(
                json.dumps({"result": "Passed", "failedTests": 0, "skippedTests": 0})
            )

            original_argv = sys.argv
            try:
                sys.argv = [
                    "verify_expansion_acceptance.py",
                    str(matrix),
                    str(core_log),
                    str(native_json),
                    str(summary_json),
                ]
                stdout = io.StringIO()
                stderr = io.StringIO()
                with redirect_stdout(stdout), redirect_stderr(stderr):
                    exit_code = main()
                self.assertEqual(exit_code, 0)
                self.assertIn("Matched 2 unique named checks", stdout.getvalue())

                # Cause a failure
                summary_json.write_text(
                    json.dumps({"result": "Failed", "failedTests": 1, "skippedTests": 0})
                )
                stdout = io.StringIO()
                stderr = io.StringIO()
                with redirect_stdout(stdout), redirect_stderr(stderr):
                    exit_code = main()
                self.assertEqual(exit_code, 1)
                self.assertIn("Native full run is not entirely passed without skips", stderr.getvalue())
            finally:
                sys.argv = original_argv


if __name__ == "__main__":
    unittest.main()
