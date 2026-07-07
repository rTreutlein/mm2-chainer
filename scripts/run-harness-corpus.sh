#!/usr/bin/env bash
# Run the converted PeTTaChainer test corpus (tests/harness/generated/*)
# against the mm2 runtime via petta + mork_ffi, one petta process per file,
# and write a per-file verdict report to outputs/harness_report.txt.
#
# petta only prints bang results at exit, so the harness also appends every
# verdict / notsupported marker durably to outputs/harness_verdicts.log as it
# happens (see mm2-log-line in compiler/mm2_chainer.metta); this runner
# counts from that side log so a timeout on a runaway query keeps the
# verdicts produced before it.
#
# Verdicts: mm2-test-pass / mm2-test-close / mm2-test-FAIL, plus
#   notsupported = IR shapes or test forms the pipeline cannot express yet
#   TIMEOUT/ERROR = the petta process was killed or aborted

set -uo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

mkdir -p outputs/harness_logs
bash scripts/build-runtime.sh outputs/harness_runtime.mm2

report="outputs/harness_report.txt"
vlog="outputs/harness_verdicts.log"
: > "$report"

total_pass=0 total_close=0 total_fail=0 total_unsup=0 total_err=0

for f in tests/harness/generated/*.metta; do
  name="$(basename "$f" .metta)"
  log="outputs/harness_logs/$name.log"
  : > "$vlog"
  timeout 300 petta "$f" > "$log" 2>&1
  status=$?
  cat "$vlog" >> "$log"
  pass="$(grep -c 'mm2-test-pass' "$vlog" || true)"
  close="$(grep -c 'mm2-test-close' "$vlog" || true)"
  fail="$(grep -c 'mm2-test-FAIL' "$vlog" || true)"
  unsup="$(( $(grep -c 'notsupported-ir' "$vlog" || true) + $(grep -c 'mm2-test-unsupported' "$log" || true) ))"
  flag=""
  if [ $status -eq 124 ]; then
    flag="TIMEOUT"
    total_err=$((total_err + 1))
  elif [ $status -ne 0 ] || grep -q 'ERROR' "$log"; then
    flag="ERROR"
    total_err=$((total_err + 1))
  fi
  total_pass=$((total_pass + pass))
  total_close=$((total_close + close))
  total_fail=$((total_fail + fail))
  total_unsup=$((total_unsup + unsup))
  printf '%-45s pass=%-3s close=%-3s fail=%-3s unsupported=%-3s %s\n' \
    "$name" "$pass" "$close" "$fail" "$unsup" "$flag" \
    >> "$report"
done

{
  echo "---"
  echo "totals: pass=$total_pass close=$total_close fail=$total_fail unsupported=$total_unsup flagged-files=$total_err"
} >> "$report"

cat "$report"
