#!/usr/bin/env bash

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

tmp_dir="$(mktemp -d /tmp/mm2-examples.XXXXXX)"
trap 'rm -rf -- "$tmp_dir"' EXIT

run_example() {
  local name="$1"
  local expected_passes="$2"
  local out="$tmp_dir/$name.out"
  local verdicts="$tmp_dir/$name.verdicts"

  if ! MM2_HARNESS_VERDICT_LOG="$verdicts" timeout 30s petta "examples/$name.metta" >"$out" 2>&1; then
    cat "$out" >&2
    echo "FAIL: examples/$name.metta did not finish within 30 seconds" >&2
    exit 1
  fi

  if grep -Eq 'mm2-test-(close|FAIL)' "$verdicts"; then
    cat "$verdicts" >&2
    echo "FAIL: examples/$name.metta produced a non-pass verdict" >&2
    exit 1
  fi

  local pass_count
  pass_count="$(grep -c '^[(]mm2-test-pass ' "$verdicts" || true)"
  if [[ "$pass_count" != "$expected_passes" ]]; then
    cat "$verdicts" >&2
    echo "FAIL: examples/$name.metta expected $expected_passes passes, got $pass_count" >&2
    exit 1
  fi
}

run_example smokes 1
run_example flyingraven 3

echo "PASS: runnable examples"
