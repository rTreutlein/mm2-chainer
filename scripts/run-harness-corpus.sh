#!/usr/bin/env bash
# Run the converted PeTTaChainer test corpus (tests/harness/generated/*)
# against the mm2 runtime via petta + mork_ffi, one petta process per file,
# and write a per-file verdict report to outputs/harness_report.txt.
#
# petta only prints bang results at exit, so the harness also appends every
# verdict / notsupported marker durably to outputs/harness_verdicts.log as it
# happens (see mm2-log-line in compiler/mm2_chainer.metta). Successful files
# are counted from their own stdout log; timeout/error files fall back to the
# side log so a runaway query keeps the verdicts produced before it.
# Do not run another mm2 harness petta process in parallel with this script:
# the side log path is shared by compiler/mm2_chainer.metta.
#
# Verdicts: mm2-test-pass / mm2-test-close / mm2-test-FAIL, plus
#   unsupported-ir = IR shapes the translator/runtime cannot express yet
#   skipped        = converter-level PeTTa test forms not ported to MM2
#   omitted        = explicit generated comments for intentionally omitted forms
#   adapted        = explicit generated comments for MM2-specific adaptations
#   TIMEOUT/ERROR  = the petta process was killed or aborted

set -uo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

mkdir -p outputs/harness_logs
bash scripts/build-runtime.sh outputs/harness_runtime.mm2

report="outputs/harness_report.txt"
vlog="outputs/harness_verdicts.log"
: > "$report"

total_pass=0 total_close=0 total_fail=0 total_unsup_ir=0 total_skipped=0 total_omitted=0 total_adapted=0 total_err=0

for f in tests/harness/generated/*.metta; do
  name="$(basename "$f" .metta)"
  log="outputs/harness_logs/$name.log"
  : > "$vlog"
  timeout 300 petta "$f" > "$log" 2>&1
  status=$?
  count_log="$log"
  if [ $status -ne 0 ]; then
    count_log="$vlog"
  fi
  pass="$(grep -c 'mm2-test-pass' "$count_log" || true)"
  close="$(grep -c 'mm2-test-close' "$count_log" || true)"
  fail="$(grep -c 'mm2-test-FAIL' "$count_log" || true)"
  unsup_ir="$(grep -c 'notsupported-ir' "$count_log" || true)"
  skipped="$(grep -c 'mm2-test-unsupported' "$count_log" || true)"
  omitted="$(grep -c '^; OMITTED' "$f" || true)"
  adapted="$(grep -c '^; ADAPTED' "$f" || true)"
  cat "$vlog" >> "$log"
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
  total_unsup_ir=$((total_unsup_ir + unsup_ir))
  total_skipped=$((total_skipped + skipped))
  total_omitted=$((total_omitted + omitted))
  total_adapted=$((total_adapted + adapted))
  printf '%-45s pass=%-3s close=%-3s fail=%-3s unsupported-ir=%-3s skipped=%-3s omitted=%-3s adapted=%-3s %s\n' \
    "$name" "$pass" "$close" "$fail" "$unsup_ir" "$skipped" "$omitted" "$adapted" "$flag" \
    >> "$report"
done

{
  echo "---"
  echo "totals: pass=$total_pass close=$total_close fail=$total_fail unsupported-ir=$total_unsup_ir skipped=$total_skipped omitted=$total_omitted adapted=$total_adapted flagged-files=$total_err"
} >> "$report"

cat "$report"

if [ "$total_fail" -ne 0 ] ||
   [ "$total_close" -ne 0 ] ||
   [ "$total_unsup_ir" -ne 0 ] ||
   [ "$total_skipped" -ne 0 ] ||
   [ "$total_omitted" -ne 0 ] ||
   [ "$total_err" -ne 0 ]; then
  exit 1
fi
