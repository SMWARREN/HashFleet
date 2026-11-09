#!/usr/bin/env python3
"""Fail closed when the configured free Swift analyzer is absent or mismatched.

This checks capability, not semantic-analysis equivalence with SonarSource's paid
Swift analyzer. Authentication stays in the environment, never command arguments.
"""
from __future__ import annotations

import json
import os
import sys
import urllib.error
import urllib.request


def get_metadata(base_url: str, endpoint: str, token: str) -> dict:
    request = urllib.request.Request(
        base_url.rstrip("/") + "/api/" + endpoint,
        headers={"Authorization": "Bearer " + token},
    )
    with urllib.request.urlopen(request, timeout=15) as response:
        return json.load(response)


def verify_swift(plugins: dict, languages: dict, expected_version: str) -> str:
    installed = next((item for item in plugins.get("plugins", [])
                      if item.get("key") == "sonarapple"), None)
    if installed is None:
        raise ValueError("Required sonar-apple plugin is not installed on the selected server")
    if installed.get("version") != expected_version:
        raise ValueError("Installed sonar-apple version does not match SONAR_APPLE_PLUGIN_VERSION")
    if not any(item.get("key") == "swift" for item in languages.get("languages", [])):
        raise ValueError("Selected server does not register the Swift language")
    return "Verified sonar-apple " + expected_version + " and registered Swift language"


def main() -> int:
    token = os.environ.get("SONAR_TOKEN", "")
    if not token:
        print("Swift preflight requires SONAR_TOKEN", file=sys.stderr)
        return 1
    base_url = os.environ.get("SONAR_URL", "http://localhost:9000")
    version = os.environ.get("SONAR_APPLE_PLUGIN_VERSION", "0.5.1")
    try:
        plugins = get_metadata(base_url, "plugins/installed", token)
        languages = get_metadata(base_url, "languages/list", token)
        print(verify_swift(plugins, languages, version))
    except (urllib.error.URLError, ValueError, TypeError, AttributeError, KeyError):
        # Avoid echoing response bodies, credentials, or URLs with query parameters.
        print("Swift capability preflight failed. Check server access, installed sonar-apple "
              "version and Swift language registration. No scan was published.", file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main())
