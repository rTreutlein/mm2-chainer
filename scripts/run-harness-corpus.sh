#!/usr/bin/env bash
# Run the converted PeTTaChainer test corpus (tests/harness/generated/*)
# against the mm2 runtime via petta + mork_ffi, one petta process per file,
# and write per-file verdict/timing reports under outputs/.
#
# petta only prints bang results at exit, so the harness also appends every
# verdict / notsupported marker durably to a side log as it happens (see
# mm2-log-line in compiler/mm2_chainer.metta). Successful files are counted
# from their own stdout log; timeout/error files fall back to the side log so a
# runaway query keeps the verdicts produced before it. Each petta process gets a
# distinct MM2_HARNESS_VERDICT_LOG path so corpus files can run in parallel.
#
# Optional arguments restrict the run to generated file names, stems, or paths:
#
#   bash scripts/run-harness-corpus.sh test_forward_chainer
#   bash scripts/run-harness-corpus.sh tests/harness/generated/test_math.metta
#
# Focused runs use outputs/harness_report.focus.txt and
# outputs/harness_perf.focus.tsv so full-corpus report artifacts stay intact.
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
. scripts/harness-common.sh
validate_harness_floor_table || exit 2

mkdir -p outputs/harness_logs
bash scripts/build-runtime.sh outputs/harness_runtime.mm2

if [ "$#" -eq 0 ]; then
  report="outputs/harness_report.txt"
  perf_report="outputs/harness_perf.tsv"
else
  report="outputs/harness_report.focus.txt"
  perf_report="outputs/harness_perf.focus.tsv"
fi
: > "$report"
: > "$perf_report"

total_pass=0 total_close=0 total_fail=0 total_unsup_ir=0 total_skipped=0 total_omitted=0 total_adapted=0 total_err=0 total_coverage_err=0 total_adapted_err=0 total_ms=0
min_total_pass="$(harness_floor_table | awk -F '\t' '{ total += $2 } END { print total }')"
max_total_adapted=0
jobs="${MM2_HARNESS_JOBS:-4}"
case "$jobs" in
  ''|*[!0-9]*)
    echo "MM2_HARNESS_JOBS must be a positive integer, got: $jobs" >&2
    exit 2
    ;;
esac
if [ "$jobs" -lt 1 ]; then
  echo "MM2_HARNESS_JOBS must be a positive integer, got: $jobs" >&2
  exit 2
fi

now_ns() {
  date +%s%N
}

format_ms() {
  local ms="$1"
  printf '%d.%03d' "$((ms / 1000))" "$((ms % 1000))"
}

run_one_file() {
  local f="$1"
  local name log vlog metrics count_log status start_ns end_ns duration_ms
  local pass close fail unsup_ir skipped omitted adapted

  name="$(basename "$f" .metta)"
  log="outputs/harness_logs/$name.log"
  vlog="outputs/harness_logs/$name.verdicts.log"
  metrics="outputs/harness_logs/$name.metrics"
  rm -f "$metrics"
  : > "$vlog"
  start_ns="$(now_ns)"
  MM2_HARNESS_VERDICT_LOG="$ROOT_DIR/$vlog" timeout 300 petta "$f" > "$log" 2>&1
  status=$?
  end_ns="$(now_ns)"
  duration_ms=$(((end_ns - start_ns) / 1000000))
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
  printf '%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\n' \
    "$name" "$status" "$duration_ms" "$pass" "$close" "$fail" "$unsup_ir" "$skipped" "$omitted" "$adapted" \
    > "$metrics"
}

mapfile -t all_files < <(find tests/harness/generated -maxdepth 1 -type f -name 'test_*.metta' | sort)

full_corpus=0
if [ "$#" -eq 0 ]; then
  full_corpus=1
  files=("${all_files[@]}")
else
  files=()
  for requested in "$@"; do
    case "$requested" in
      *.metta)
        candidate="$requested"
        ;;
      *)
        candidate="tests/harness/generated/$requested.metta"
        ;;
    esac
    if [ ! -f "$candidate" ]; then
      echo "generated test not found: $requested" >&2
      exit 2
    fi
    files+=("$candidate")
  done
fi

for f in "${files[@]}"; do
  name="$(basename "$f" .metta)"
  min_pass="$(min_pass_for_file "$name")"
  if requires_harness_floor "$f" && [ "$min_pass" -le 0 ]; then
    echo "missing corpus pass floor for generated fixture: $name" >&2
    exit 2
  fi
done

active_jobs=0
suite_start_ns="$(now_ns)"
for f in "${files[@]}"; do
  run_one_file "$f" &
  active_jobs=$((active_jobs + 1))
  if [ "$active_jobs" -ge "$jobs" ]; then
    wait -n
    active_jobs=$((active_jobs - 1))
  fi
done
wait
suite_end_ns="$(now_ns)"
suite_ms=$(((suite_end_ns - suite_start_ns) / 1000000))

for f in "${files[@]}"; do
  name="$(basename "$f" .metta)"
  log="outputs/harness_logs/$name.log"
  metrics="outputs/harness_logs/$name.metrics"
  if [ ! -s "$metrics" ]; then
    printf '%-45s pass=%-3s close=%-3s fail=%-3s unsupported-ir=%-3s skipped=%-3s omitted=%-3s adapted=%-3s time=%ss %s\n' \
      "$name" 0 0 0 0 0 0 0 "0.000" "ERROR" \
      >> "$report"
    total_err=$((total_err + 1))
    continue
  fi
  IFS=$'\t' read -r name status duration_ms pass close fail unsup_ir skipped omitted adapted < "$metrics"
  duration_s="$(format_ms "$duration_ms")"
  flag=""
  if [ $status -eq 124 ]; then
    flag="TIMEOUT"
    total_err=$((total_err + 1))
  elif [ $status -ne 0 ] || grep -q 'ERROR' "$log"; then
    flag="ERROR"
    total_err=$((total_err + 1))
  fi
  min_pass="$(min_pass_for_file "$name")"
  if [ "$pass" -lt "$min_pass" ]; then
    flag="${flag:+$flag,}COVERAGE"
    total_coverage_err=$((total_coverage_err + 1))
    echo "corpus pass count regressed for $name: got $pass, expected at least $min_pass" >&2
  fi
  max_adapted="$(max_adapted_for_file "$name")"
  if [ "$adapted" -gt "$max_adapted" ]; then
    flag="${flag:+$flag,}ADAPTED"
    total_adapted_err=$((total_adapted_err + 1))
    echo "corpus adapted count regressed for $name: got $adapted, expected at most $max_adapted" >&2
  fi
  total_pass=$((total_pass + pass))
  total_close=$((total_close + close))
  total_fail=$((total_fail + fail))
  total_unsup_ir=$((total_unsup_ir + unsup_ir))
  total_skipped=$((total_skipped + skipped))
  total_omitted=$((total_omitted + omitted))
  total_adapted=$((total_adapted + adapted))
  total_ms=$((total_ms + duration_ms))
  printf '%-45s pass=%-3s close=%-3s fail=%-3s unsupported-ir=%-3s skipped=%-3s omitted=%-3s adapted=%-3s time=%ss %s\n' \
    "$name" "$pass" "$close" "$fail" "$unsup_ir" "$skipped" "$omitted" "$adapted" "$duration_s" "$flag" \
    >> "$report"
done

{
  echo "---"
  echo "totals: pass=$total_pass close=$total_close fail=$total_fail unsupported-ir=$total_unsup_ir skipped=$total_skipped omitted=$total_omitted adapted=$total_adapted time=$(format_ms "$suite_ms")s file-time=$(format_ms "$total_ms")s flagged-files=$((total_err + total_coverage_err + total_adapted_err))"
} >> "$report"

{
  printf 'file\tduration_ms\tpass\tclose\tfail\tunsupported_ir\tskipped\tomitted\tadapted\tstatus\n'
  for f in "${files[@]}"; do
    metrics="outputs/harness_logs/$(basename "$f" .metta).metrics"
    if [ ! -s "$metrics" ]; then
      continue
    fi
    IFS=$'\t' read -r name status duration_ms pass close fail unsup_ir skipped omitted adapted < "$metrics"
    printf '%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\n' \
      "$name" "$duration_ms" "$pass" "$close" "$fail" "$unsup_ir" "$skipped" "$omitted" "$adapted" "$status"
  done | sort -t $'\t' -k2,2nr
} > "$perf_report"

cat "$report"

if [ "$total_fail" -ne 0 ] ||
   [ "$total_close" -ne 0 ] ||
   [ "$total_unsup_ir" -ne 0 ] ||
   [ "$total_skipped" -ne 0 ] ||
   [ "$total_omitted" -ne 0 ] ||
   [ "$total_err" -ne 0 ] ||
   [ "$total_coverage_err" -ne 0 ] ||
   [ "$total_adapted_err" -ne 0 ] ||
   [ "$total_adapted" -gt "$max_total_adapted" ] ||
   { [ "$full_corpus" -eq 1 ] && [ "$total_pass" -lt "$min_total_pass" ]; }; then
  if [ "$full_corpus" -eq 1 ] && [ "$total_pass" -lt "$min_total_pass" ]; then
    echo "corpus pass count regressed: got $total_pass, expected at least $min_total_pass" >&2
  fi
  if [ "$total_adapted" -gt "$max_total_adapted" ]; then
    echo "corpus adapted count regressed: got $total_adapted, expected at most $max_total_adapted" >&2
  fi
  exit 1
fi
