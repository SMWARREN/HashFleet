import contextlib
import io
import json
import unittest
import urllib.error
from unittest.mock import patch

import sonar_swift_preflight as preflight


class SonarSwiftPreflightTests(unittest.TestCase):
    def setUp(self):
        self.plugins = {"plugins": [{"key": "sonarapple", "version": "0.5.1"}]}
        self.languages = {"languages": [{"key": "swift"}]}

    def test_exact_plugin_and_language_are_required(self):
        self.assertIn("0.5.1", preflight.verify_swift(self.plugins, self.languages, "0.5.1"))
        for plugins, languages, version in [
            ({"plugins": []}, self.languages, "0.5.1"),
            (self.plugins, {"languages": []}, "0.5.1"),
            (self.plugins, self.languages, "0.5.2"),
            ({}, self.languages, "0.5.1"),
            (self.plugins, {}, "0.5.1"),
        ]:
            with self.subTest(plugins=plugins, languages=languages, version=version):
                with self.assertRaises(ValueError):
                    preflight.verify_swift(plugins, languages, version)

    def test_request_uses_header_authentication_and_bounded_timeout(self):
        response = io.BytesIO(json.dumps(self.plugins).encode())
        with patch.object(preflight.urllib.request, "urlopen", return_value=response) as open_url:
            self.assertEqual(preflight.get_metadata("http://localhost:9000/", "plugins/installed", "fixture"),
                             self.plugins)
        request = open_url.call_args.args[0]
        self.assertEqual(request.full_url, "http://localhost:9000/api/plugins/installed")
        self.assertEqual(request.get_header("Authorization"), "Bearer fixture")
        self.assertNotIn("fixture", request.full_url)
        self.assertEqual(open_url.call_args.kwargs["timeout"], 15)

    def run_main(self, environment, responses=None, error=None):
        output, errors = io.StringIO(), io.StringIO()
        with patch.dict(preflight.os.environ, environment, clear=True), \
                patch.object(preflight, "get_metadata", side_effect=error or responses) as fetch, \
                contextlib.redirect_stdout(output), contextlib.redirect_stderr(errors):
            status = preflight.main()
        return status, output.getvalue(), errors.getvalue(), fetch

    def test_main_requires_token_before_any_network_request(self):
        status, _, errors, fetch = self.run_main({})
        self.assertEqual(status, 1)
        self.assertIn("requires SONAR_TOKEN", errors)
        fetch.assert_not_called()

    def test_main_verifies_both_endpoints_without_printing_token(self):
        status, output, errors, fetch = self.run_main(
            {"SONAR_TOKEN": "secret-fixture"}, [self.plugins, self.languages])
        self.assertEqual(status, 0)
        self.assertIn("registered Swift", output)
        self.assertEqual(fetch.call_count, 2)
        self.assertNotIn("secret-fixture", output + errors)

    def test_configuration_is_passed_to_metadata_fetch(self):
        plugins = {"plugins": [{"key": "sonarapple", "version": "custom"}]}
        status, _, _, fetch = self.run_main(
            {"SONAR_TOKEN": "fixture", "SONAR_URL": "https://sonar.example", "SONAR_APPLE_PLUGIN_VERSION": "custom"},
            [plugins, self.languages])
        self.assertEqual(status, 0)
        self.assertEqual(fetch.call_args_list[0].args, ("https://sonar.example", "plugins/installed", "fixture"))

    def test_network_schema_and_decode_failures_never_report_success_or_echo_secrets(self):
        for error in [urllib.error.URLError("secret-fixture"), ValueError("secret-fixture"),
                      TypeError("secret-fixture"), AttributeError("secret-fixture"), KeyError("secret-fixture")]:
            with self.subTest(error=type(error).__name__):
                status, output, errors, _ = self.run_main({"SONAR_TOKEN": "secret-fixture"}, error=error)
                self.assertEqual(status, 1)
                self.assertIn("No scan was published", errors)
                self.assertNotIn("secret-fixture", output + errors)

    def test_successful_http_response_with_wrong_plugin_still_fails(self):
        status, _, errors, _ = self.run_main({"SONAR_TOKEN": "fixture"}, [{"plugins": []}, self.languages])
        self.assertEqual(status, 1)
        self.assertIn("No scan was published", errors)


if __name__ == "__main__":
    unittest.main()
