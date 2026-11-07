#!/usr/bin/env bash
# Optional reusable toolkit adapter. Existing sonar-scan.sh remains unchanged.
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
KIT="${SWIFT_SONAR_KIT_ROOT:-$ROOT/../swift-sonar-kit}"
PYTHON="${PYTHON:-python3}"
if [[ ! -f "$KIT/src/swift_sonar_kit/cli.py" ]]; then
  echo "Set SWIFT_SONAR_KIT_ROOT to your separate swift-sonar-kit checkout." >&2
  exit 2
fi
"$PYTHON" -c "import sys; sys.exit(0 if sys.version_info >= (3, 11) else 2)" || {
  echo "Swift Sonar Kit requires Python 3.11 or newer." >&2
  exit 2
}
action="${1:---help}"
if [[ $# -gt 0 ]]; then shift; fi
export PYTHONPATH="$KIT/src${PYTHONPATH:+:$PYTHONPATH}"
case "$action" in
  project-test|project-scan|project-run)
    exec "$PYTHON" -m swift_sonar_kit "$action" --root "$ROOT" --config Tools/swift-sonar-project.json "$@"
    ;;
  *) exec "$PYTHON" -m swift_sonar_kit "$action" --root "$ROOT" "$@" ;;
esac
