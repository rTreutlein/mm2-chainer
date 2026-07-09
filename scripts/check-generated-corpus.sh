#!/usr/bin/env bash
# Verify generated PeTTaChainer corpus fixtures are in sync with the converter.

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

python3 scripts/convert_petta_tests.py >/dev/null

if ! git diff --quiet -- tests/harness/generated; then
  git diff -- tests/harness/generated >&2
  echo "generated corpus is stale; run python3 scripts/convert_petta_tests.py" >&2
  exit 1
fi
