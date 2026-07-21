#!/usr/bin/env bash

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

bash scripts/build-runtime.sh outputs/harness_runtime.mm2

tmp_dir="$(mktemp -d /tmp/mm2-batching.XXXXXX)"
trap 'rm -rf -- "$tmp_dir"' EXIT

MM2_HARNESS_VERDICT_LOG="$tmp_dir/verdicts" \
  timeout 60s petta tests/harness/batching.metta \
  >"$tmp_dir/output" 2>&1

cat "$tmp_dir/output"

if grep -Eq 'notsupported-ir|mm2-test-(close|FAIL)|ERROR' \
    "$tmp_dir/output" "$tmp_dir/verdicts"; then
  cat "$tmp_dir/verdicts" >&2
  exit 1
fi

pass_count="$(grep -c '^[(]mm2-test-pass ' "$tmp_dir/verdicts" || true)"
if [[ "$pass_count" != 12 ]]; then
  cat "$tmp_dir/verdicts" >&2
  echo "expected 12 batching passes, got $pass_count" >&2
  exit 1
fi

echo "PASS: native insertion and tagged query batching"
