#!/bin/bash
# Run local SonarQube analysis of the native apps, CLI and repository tooling.
#
# SonarQube Community Edition has no Swift analyser, so this uses the free
# insideapp-fr/sonar-apple plugin. The plugin imports local SwiftLint findings.
# An existing server/container is never removed or reset by this script.
# Set SONAR_RESULT_BUNDLE to import a real Xcode test/coverage result bundle.
# Set SONAR_REQUIRE_TESTS=1 to reject a scan without a selected result bundle.
# SwiftLint lint is not the separate type-checked SwiftLint analyze command.
#
# Source analysis defaults to localhost. SONAR_URL can select a different server.
# New-server setup downloads the plugin from its public release repository.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

SONAR_URL="${SONAR_URL:-http://localhost:9000}"
SONAR_CONTAINER="${SONAR_CONTAINER:-hashfleet-sonar}"
PLUGIN_VERSION="${SONAR_APPLE_PLUGIN_VERSION:-0.5.1}"
PLUGIN_URL="https://github.com/insideapp-fr/sonar-apple/releases/download/${PLUGIN_VERSION}/sonar-apple-plugin-${PLUGIN_VERSION}.jar"
CACHE="${SONAR_CACHE_DIR:-$HOME/.cache/hashfleet-sonar}"
case "$PLUGIN_VERSION" in
  0.5.1)
    DEFAULT_PLUGIN_SHA256="c27432e52a6ebc698b77ad42bf3d98f5e34fb20d3f398799bda74fbc008f8612"
    ;;
  *)
    DEFAULT_PLUGIN_SHA256=""
    ;;
esac
PLUGIN_SHA256="${SONAR_APPLE_PLUGIN_SHA256:-$DEFAULT_PLUGIN_SHA256}"
PLUGIN_PATH="$CACHE/sonar-apple-plugin-${PLUGIN_VERSION}.jar"
mkdir -p "$CACHE" build/sonar

verify_plugin() {
  local plugin_path="$1"
  if [[ -z "$PLUGIN_SHA256" ]]; then
    echo "Set SONAR_APPLE_PLUGIN_SHA256 for Sonar plugin version $PLUGIN_VERSION before downloading it." >&2
    return 1
  fi
  printf '%s  %s\n' "$PLUGIN_SHA256" "$plugin_path" | shasum -a 256 -c -
}

prepare_plugin() {
  if [[ ! -f "$PLUGIN_PATH" ]]; then
    echo "Downloading the sonar-apple plugin..."
    local temporary_path="$PLUGIN_PATH.tmp.$$"
    curl -sSfL --proto '=https' --tlsv1.2 -o "$temporary_path" "$PLUGIN_URL"
    verify_plugin "$temporary_path"
    mv "$temporary_path" "$PLUGIN_PATH"
  else
    verify_plugin "$PLUGIN_PATH"
  fi
}

start_server() {
  if curl -sf "$SONAR_URL/api/system/status" | grep -q '"status":"UP"'; then
    echo "SonarQube already running at $SONAR_URL"
    return
  fi
  if docker container inspect "$SONAR_CONTAINER" >/dev/null 2>&1; then
    echo "Existing SonarQube container is not ready. Refusing to remove its analysis data." >&2
    echo "Start or repair $SONAR_CONTAINER explicitly, then retry the scan." >&2
    exit 1
  fi
  prepare_plugin
  echo "Starting a new SonarQube container in Docker..."
  docker run -d --name "$SONAR_CONTAINER" -p 9000:9000 \
    -v "${SONAR_CONTAINER}-data:/opt/sonarqube/data" \
    -e SONAR_ES_BOOTSTRAP_CHECKS_DISABLE=true sonarqube:community >/dev/null

  # The container needs a moment to create its plugin directory before the copy.
  sleep 10
  docker cp "$PLUGIN_PATH" \
    "$SONAR_CONTAINER:/opt/sonarqube/extensions/plugins/sonar-apple-plugin-${PLUGIN_VERSION}.jar"
  docker restart "$SONAR_CONTAINER" >/dev/null

  echo -n "Waiting for SonarQube"
  for _ in $(seq 1 120); do
    if curl -sf "$SONAR_URL/api/system/status" | grep -q '"status":"UP"'; then echo " ready"; return; fi
    echo -n "."
    sleep 5
  done
  echo
  echo "SonarQube did not become ready in time." >&2
  exit 1
}

start_server

if [ -z "${SONAR_TOKEN:-}" ]; then
  echo "Set SONAR_TOKEN to a SonarQube user token before publishing." >&2
  echo "Generate one at $SONAR_URL/account/security." >&2
  exit 1
fi

# The scanner runs on the host rather than in a container because the plugin shells out to
# the local swiftlint binary while it analyses.
if ! command -v sonar-scanner >/dev/null; then
  echo "sonar-scanner is not installed. Run: brew install sonar-scanner" >&2
  exit 1
fi

if ! command -v swiftlint >/dev/null; then
  echo "swiftlint is required for the native source issue analysis." >&2
  exit 1
fi

SCANNER_ARGS=("-Dsonar.qualitygate.wait=true" "$@")
if [[ "${SONAR_REQUIRE_TESTS:-0}" == "1" && -z "${SONAR_RESULT_BUNDLE:-}" ]]; then
  echo "SONAR_REQUIRE_TESTS=1 requires SONAR_RESULT_BUNDLE. No scan was published." >&2
  exit 1
fi
if [ -n "${SONAR_RESULT_BUNDLE:-}" ]; then
  if [ ! -d "$SONAR_RESULT_BUNDLE" ]; then
    echo "Xcode result bundle does not exist: $SONAR_RESULT_BUNDLE" >&2
    exit 1
  fi
  # sonar-apple resolves this property against the project directory even when
  # given an absolute path. Convert it to a real project-relative path first.
  RESULT_BUNDLE_RELATIVE="$(python3 -c 'import os, sys; print(os.path.relpath(sys.argv[1], sys.argv[2]))' "$SONAR_RESULT_BUNDLE" "$ROOT")"
  SCANNER_ARGS+=("-Dsonar.apple.resultBundlePath=$RESULT_BUNDLE_RELATIVE")
else
  echo "No Xcode result bundle selected. Tests/coverage are not verified by this invocation." >&2
fi

SONAR_URL="$SONAR_URL" SONAR_APPLE_PLUGIN_VERSION="$PLUGIN_VERSION" \
  python3 Tools/sonar_swift_preflight.py

# Independently enforce the repository config. The plugin bundles a separate rule
# catalog, which can lag behind the installed SwiftLint. Do not treat scanner
# upload success or plugin-only analysis as a substitute for a strict local pass.
echo "Running strict SwiftLint (lint rules only)..."
if ! swiftlint lint --quiet --strict --reporter json > build/sonar/swiftlint-current.json; then
  echo "SwiftLint failed. See build/sonar/swiftlint-current.json. No scan was published." >&2
  exit 1
fi

echo "Publishing analysis and waiting for its quality gate..."
# Bash 3.2 treats an empty array as unset under nounset. Preserve each argument
# without expanding the array when no arguments or result bundle were provided.
SONAR_HOST_URL="$SONAR_URL" SONAR_TOKEN="$SONAR_TOKEN" sonar-scanner ${SCANNER_ARGS[@]+"${SCANNER_ARGS[@]}"}

echo "Done. Open $SONAR_URL/dashboard?id=hashfleet"
