#!/usr/bin/env bash
# Run PeTTaChainer-style tests in-process against the mm2 runtime via
# petta + mork_ffi. Verdict lines: mm2-test-pass / mm2-test-close /
# mm2-test-FAIL (see compiler/mm2_chainer.metta).

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

mkdir -p outputs
bash scripts/build-runtime.sh outputs/harness_runtime.mm2

out="outputs/harness_tests.log"
petta tests/harness/converted_tests.metta 2>&1 | tee "$out"

if grep -q "ERROR" "$out"; then
  echo "HARNESS: petta error" >&2
  exit 1
fi
if grep -q "mm2-test-FAIL" "$out"; then
  echo "HARNESS: failures found" >&2
  exit 1
fi
pass="$(grep -c 'mm2-test-pass' "$out" || true)"
close="$(grep -c 'mm2-test-close' "$out" || true)"
echo "HARNESS: $pass pass, $close close, 0 fail"
