#!/usr/bin/env bash
# Run the converted PeTTaChainer test corpus (tests/harness/generated/*)
# against the mm2 runtime via petta + mork_ffi, one petta process per file,
# and write a per-file verdict report to outputs/harness_report.txt.
#
# Verdict lines come from compiler/mm2_chainer.metta:
#   mm2-test-pass / mm2-test-close / mm2-test-FAIL
# plus:
#   unsupported = test forms the converter or harness cannot express yet
#   error       = petta aborted the file

set -uo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

mkdir -p outputs/harness_logs
bash scripts/build-runtime.sh outputs/harness_runtime.mm2

report="outputs/harness_report.txt"
: > "$report"

total_pass=0 total_close=0 total_fail=0 total_unsup=0 total_err=0

for f in tests/harness/generated/*.metta; do
  name="$(basename "$f" .metta)"
  log="outputs/harness_logs/$name.log"
  timeout 180 petta "$f" > "$log" 2>&1
  status=$?
  pass="$(grep -c 'mm2-test-pass' "$log" || true)"
  close="$(grep -c 'mm2-test-close' "$log" || true)"
  fail="$(grep -c 'mm2-test-FAIL' "$log" || true)"
  unsup="$(grep -c 'mm2-test-unsupported' "$log" || true)"
  err=0
  if [ $status -ne 0 ] || grep -q 'ERROR' "$log"; then
    err=1
  fi
  total_pass=$((total_pass + pass))
  total_close=$((total_close + close))
  total_fail=$((total_fail + fail))
  total_unsup=$((total_unsup + unsup))
  total_err=$((total_err + err))
  printf '%-45s pass=%-3s close=%-3s fail=%-3s unsupported=%-3s %s\n' \
    "$name" "$pass" "$close" "$fail" "$unsup" "$([ $err -ne 0 ] && echo ERROR || true)" \
    >> "$report"
done

{
  echo "---"
  echo "totals: pass=$total_pass close=$total_close fail=$total_fail unsupported=$total_unsup errored-files=$total_err"
} >> "$report"

cat "$report"
