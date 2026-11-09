#!/bin/bash
# Offline repository checks for CI. Tests write isolated scratch fixtures: no network, simulator, app launch,
# miner, signing, or secret access. Safe to run from a fork pull request.
set -euo pipefail
shopt -s nullglob
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "$ROOT"
export JCODE_SCRATCH_DIR="${JCODE_SCRATCH_DIR:-${RUNNER_TEMP:-$HOME/.jcode/scratch}}"
mkdir -p "$JCODE_SCRATCH_DIR"

echo "== Shell syntax"
for script in Scripts/*.sh Scripts/ci/*.sh Scripts/release/*.sh Scripts/tests/*.sh; do
    bash -n "$script"
    echo "ok $script"
done

echo "== Homebrew package Ruby syntax"
ruby -c Formula/hashfleet-cli.rb
ruby -c Casks/hashfleet.rb

echo "== Python syntax"
python3 -B - <<'PY'
from pathlib import Path
for root in ('Scripts', 'Server', 'website/Tools'):
    for path in sorted(Path(root).rglob('*.py')):
        compile(path.read_bytes(), str(path), 'exec')
        print(f'ok {path}')
PY

echo "== Offline backend contracts"
php -r 'if (PHP_VERSION_ID < 80300 || !extension_loaded("pdo_sqlite")) { fwrite(STDERR, "PHP 8.3+ with pdo_sqlite is required\n"); exit(1); }'
for script in Server/private/*.php Server/public/api/*.php Server/tools/*.php Server/tests/*.php; do
    php -l "$script"
done
php Server/tests/run.php
php Server/tests/apns_response_test.php
python3 -B Server/tests/build_bundle_test.py

echo "== Offline browser-tool interfaces"
node --test website/Tools/playwright-result.node-test.mjs website/Tools/acceptance-expression.node-test.mjs
python3 -B website/Tools/test_capture_dashboard.py

echo "== Sonar source/test classification contracts"
python3 -B -m unittest Tools.test_sonar_scope -v

echo "== Source contract checks"
python3 -B Scripts/check-native-navigation.py
python3 -B Scripts/check-shared-page-shells.py
python3 -B Scripts/tests/test_crypto_support.py
python3 -B Scripts/tests/test_native_add_miner_completion.py
python3 -B Scripts/release/test_release.py
echo "Repository checks passed."
