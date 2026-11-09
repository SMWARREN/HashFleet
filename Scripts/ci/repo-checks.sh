#!/bin/bash
# Offline repository checks for CI. Reads files only: no network, simulator, app launch,
# miner, signing, or secret access. Safe to run from a fork pull request.
set -euo pipefail
shopt -s nullglob
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "$ROOT"

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
for path in sorted(Path('Scripts').rglob('*.py')):
    compile(path.read_bytes(), str(path), 'exec')
    print(f'ok {path}')
PY

echo "== Source contract checks"
python3 -B Scripts/check-native-navigation.py
python3 -B Scripts/check-shared-page-shells.py
python3 -B Scripts/tests/test_crypto_support.py
python3 -B Scripts/tests/test_native_add_miner_completion.py
python3 -B Scripts/release/test_release.py
echo "Repository checks passed."
