#!/usr/bin/env bash
# Benchmark synthetic backward query workloads by running MORK directly.
#
# The timed section is only:
#
#   mork run RULES --steps N --aux-path RUNTIME OUT
#
# Workload generation and runtime construction happen before the timer.  This
# isolates the compiled MM2 runtime path from PeTTa import and compiler costs.
#
# Defaults:
#   - run each case MM2_DIRECT_QUERY_BENCH_RUNS=5 times
#   - benchmark implication query depths 4, 8, and 12
#   - benchmark n-ary And adapter widths 4 and 8
#   - scale query rounds by the current runtime template count
#   - subtract an empty direct-MORK baseline median from each case median
#   - report both fixed-budget and first-answer latency rows
#
# Example:
#   bash scripts/bench-query-direct-mork.sh
#   MM2_DIRECT_QUERY_BENCH_RUNS=7 MM2_DIRECT_QUERY_CHAIN_DEPTHS="4 8 12 16" bash scripts/bench-query-direct-mork.sh

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

runs="${MM2_DIRECT_QUERY_BENCH_RUNS:-5}"
timeout_s="${MM2_DIRECT_QUERY_BENCH_TIMEOUT:-120}"
chain_depths="${MM2_DIRECT_QUERY_CHAIN_DEPTHS:-4 8 12}"
and_widths="${MM2_DIRECT_QUERY_AND_WIDTHS:-4 8}"
runtime_template_count() {
  grep -h '^(exec-template' runtime/parts/*.mm2 | wc -l | tr -d ' '
}

default_steps_per_round="$(runtime_template_count)"
steps_per_round="${MM2_DIRECT_QUERY_STEPS_PER_ROUND:-$default_steps_per_round}"
summary_report="${MM2_DIRECT_QUERY_BENCH_OUT:-outputs/query_direct_mork_bench.tsv}"
runs_report="${MM2_DIRECT_QUERY_BENCH_RUNS_OUT:-outputs/query_direct_mork_bench_runs.tsv}"
prepared_dir="${MM2_DIRECT_QUERY_BENCH_PREPARED_DIR:-outputs/query_direct_mork_bench_prepared}"
logs_dir="${MM2_DIRECT_QUERY_BENCH_LOGS_DIR:-outputs/query_direct_mork_bench_logs}"
lock_dir="outputs/.bench-query-direct-mork.lock"
tmp_dir=""

require_positive_int() {
  local name="$1"
  local value="$2"
  case "$value" in
    ''|*[!0-9]*)
      echo "$name must be a positive integer, got: $value" >&2
      exit 2
      ;;
  esac
  if [ "$value" -lt 1 ]; then
    echo "$name must be a positive integer, got: $value" >&2
    exit 2
  fi
}

require_positive_int_list() {
  local name="$1"
  local values="$2"
  local found=0
  local value
  for value in $values; do
    require_positive_int "$name" "$value"
    found=1
  done
  if [ "$found" -ne 1 ]; then
    echo "$name must contain at least one positive integer" >&2
    exit 2
  fi
}

now_ns() {
  date +%s%N
}

median_ms() {
  printf '%s\n' "$@" |
    sort -n |
    awk '
      { values[NR] = $1 }
      END {
        if (NR == 0) {
          print 0
        } else if (NR % 2 == 1) {
          print values[(NR + 1) / 2]
        } else {
          print int((values[NR / 2] + values[NR / 2 + 1]) / 2)
        }
      }'
}

min_ms() {
  printf '%s\n' "$@" | sort -n | awk 'NR == 1 { print $1 }'
}

max_ms() {
  printf '%s\n' "$@" | sort -n | awk 'END { print $1 }'
}

cleanup() {
  if [ -n "$tmp_dir" ]; then
    rm -rf "$tmp_dir"
  fi
  rm -rf "$lock_dir"
}

and_expr() {
  local width="$1"
  local i
  printf '(And'
  for i in $(seq 1 "$width"); do
    printf ' (QueryDirectPart%s item)' "$i"
  done
  printf ')'
}

and_premises() {
  local width="$1"
  local result="pnil"
  local i
  for ((i = width; i >= 1; i--)); do
    result="(pcons (QueryDirectPart${i} item) $result)"
  done
  printf '%s' "$result"
}

emit_seed_fact() {
  local term="$1"
  local stv="$2"
  local proof_id="$3"

  printf '(fact %s %s)\n' "$term" "$stv"
  printf '(fact-evidence %s %s (pcons (fact-ev (fact-key %s) %s) pnil))\n' "$term" "$stv" "$term" "$term"
  printf '(proved %s %s %s (pcons (fact-ev (fact-key %s) %s) pnil))\n' "$term" "$stv" "$proof_id" "$term" "$term"
}

generate_baseline_case() {
  local case_dir="$1"
  local seed="$case_dir/seed.mm2"
  local rules="$case_dir/rules.mm2"
  local runtime="$case_dir/runtime.mm2"

  printf '; empty direct-MORK benchmark baseline\n' > "$seed"
  printf '; empty direct-MORK benchmark baseline\n' > "$rules"
  bash scripts/build-runtime.sh "$runtime" "$seed"
}

generate_chain_case() {
  local depth="$1"
  local case_dir="$2"
  local seed="$case_dir/seed.mm2"
  local rules="$case_dir/rules.mm2"
  local runtime="$case_dir/runtime.mm2"
  local i prev

  {
    printf '; generated query-chain-depth=%s by scripts/bench-query-direct-mork.sh\n' "$depth"
    printf '(, (Goal (QueryDirectNode%s item)))\n' "$depth"
    emit_seed_fact "(QueryDirectNode0 item)" "(1.0 1.0)" "query-direct-node0"
  } > "$seed"

  {
    printf '; generated query-chain-depth=%s by scripts/bench-query-direct-mork.sh\n' "$depth"
    for i in $(seq 1 "$depth"); do
      prev=$((i - 1))
      printf '(ruleN (QueryDirectNode%s $x) query-direct-rule-%s (ctv (1.0 1.0) (0.0 1.0)) (pcons (QueryDirectNode%s $x) pnil))\n' \
        "$i" "$i" "$prev"
    done
  } > "$rules"

  bash scripts/build-runtime.sh "$runtime" "$seed"
}

generate_and_adapter_case() {
  local width="$1"
  local case_dir="$2"
  local seed="$case_dir/seed.mm2"
  local rules="$case_dir/rules.mm2"
  local runtime="$case_dir/runtime.mm2"
  local goal premises i

  goal="$(and_expr "$width")"
  premises="$(and_premises "$width")"

  {
    printf '; generated and-adapter-width=%s by scripts/bench-query-direct-mork.sh\n' "$width"
    printf '(, (Goal %s))\n' "$goal"
    for i in $(seq 1 "$width"); do
      emit_seed_fact "(QueryDirectPart${i} item)" "(1.0 1.0)" "query-direct-part${i}"
    done
  } > "$seed"

  {
    printf '; generated and-adapter-width=%s by scripts/bench-query-direct-mork.sh\n' "$width"
    printf '(adapterN %s %s)\n' "$goal" "$premises"
  } > "$rules"

  bash scripts/build-runtime.sh "$runtime" "$seed"
}

case_steps() {
  local shape="$1"
  local size="$2"
  echo $(($(case_rounds "$shape" "$size") * steps_per_round))
}

case_rounds() {
  local shape="$1"
  local size="$2"
  case "$shape" in
    chain)
      echo $((size * 10))
      ;;
    and_adapter)
      echo 100
      ;;
    baseline)
      echo 1
      ;;
    *)
      echo "unknown shape: $shape" >&2
      exit 2
      ;;
  esac
}

expected_fact_prefix() {
  local shape="$1"
  local size="$2"
  case "$shape" in
    chain)
      printf '(fact (QueryDirectNode%s item) ' "$size"
      ;;
    and_adapter)
      printf '(fact %s ' "$(and_expr "$size")"
      ;;
    *)
      echo "unknown shape: $shape" >&2
      exit 2
      ;;
  esac
}

run_mork_case() {
  local name="$1"
  local shape="$2"
  local size="$3"
  local rules="$4"
  local runtime="$5"
  local steps="$6"
  local run_id="$7"
  local out="$8"
  local log="$9"
  local start_ns end_ns duration_ms status valid expected

  start_ns="$(now_ns)"
  set +e
  timeout "$timeout_s" mork run "$rules" --steps "$steps" --aux-path "$runtime" "$out" > "$log" 2>&1
  status=$?
  set -e
  end_ns="$(now_ns)"
  duration_ms=$(((end_ns - start_ns) / 1000000))

  if [ "$shape" = "baseline" ]; then
    valid=1
  elif [ "$status" -eq 0 ]; then
    expected="$(expected_fact_prefix "$shape" "$size")"
    if grep -Fq "$expected" "$out"; then
      valid=1
    else
      valid=0
    fi
  else
    valid=0
  fi

  printf '%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\n' \
    "$name" "$shape" "$size" "$run_id" "$steps" "$duration_ms" "$valid" "$status"
}

run_case() {
  local name="$1"
  local mode="$2"
  local shape="$3"
  local size="$4"
  local rules="$5"
  local runtime="$6"
  local rounds="$7"
  local baseline_median="$8"
  local steps=$((rounds * steps_per_round))
  local durations=()
  local valid_count=0
  local worst_status=0
  local run_id row duration_ms valid status out log
  local gross_median gross_min gross_max net_median

  for run_id in $(seq 1 "$runs"); do
    out="$logs_dir/$name.$mode.$run_id.mm2"
    log="$logs_dir/$name.$mode.$run_id.log"
    row="$(run_mork_case "$name" "$shape" "$size" "$rules" "$runtime" "$steps" "$run_id" "$out" "$log")"
    printf '%s\t%s\n' "$mode" "$row" >> "$runs_report"
    IFS=$'\t' read -r _name _shape _size _run _steps duration_ms valid status <<< "$row"
    durations+=("$duration_ms")
    if [ "$valid" -eq 1 ]; then
      valid_count=$((valid_count + 1))
    fi
    if [ "$status" -ne 0 ]; then
      worst_status="$status"
    fi
  done

  gross_median="$(median_ms "${durations[@]}")"
  gross_min="$(min_ms "${durations[@]}")"
  gross_max="$(max_ms "${durations[@]}")"
  net_median=$((gross_median - baseline_median))
  if [ "$net_median" -lt 0 ]; then
    net_median=0
  fi

  if [ "$valid_count" -ne "$runs" ]; then
    printf 'direct MORK benchmark validation failed for %s: valid %s/%s; see %s/%s.*\n' \
      "$name" "$valid_count" "$runs" "$logs_dir" "$name" >&2
  fi
  if [ "$worst_status" -ne 0 ]; then
    printf 'direct MORK benchmark non-zero status for %s: worst status %s; see %s/%s.*.log\n' \
      "$name" "$worst_status" "$logs_dir" "$name" >&2
  fi

  printf '%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\n' \
    "$name" "$mode" "$shape" "$size" "$rounds" "$steps" "$gross_median" "$gross_min" "$gross_max" \
    "$baseline_median" "$net_median" "$valid_count"

  if [ "$valid_count" -ne "$runs" ] || [ "$worst_status" -ne 0 ]; then
    return 1
  fi
}

probe_case_valid() {
  local name="$1"
  local shape="$2"
  local size="$3"
  local rules="$4"
  local runtime="$5"
  local rounds="$6"
  local steps=$((rounds * steps_per_round))
  local out="$tmp_dir/probes/$name.$rounds.mm2"
  local log="$tmp_dir/probes/$name.$rounds.log"
  local row valid status

  row="$(run_mork_case "$name" "$shape" "$size" "$rules" "$runtime" "$steps" "probe-$rounds" "$out" "$log")"
  IFS=$'\t' read -r _name _shape _size _run _steps _duration_ms valid status <<< "$row"
  [ "$valid" -eq 1 ] && [ "$status" -eq 0 ]
}

find_answer_rounds() {
  local name="$1"
  local shape="$2"
  local size="$3"
  local rules="$4"
  local runtime="$5"
  local max_rounds="$6"
  local lo=0
  local hi=1
  local mid

  while [ "$hi" -lt "$max_rounds" ]; do
    if probe_case_valid "$name" "$shape" "$size" "$rules" "$runtime" "$hi"; then
      break
    fi
    lo="$hi"
    hi=$((hi * 2))
    if [ "$hi" -gt "$max_rounds" ]; then
      hi="$max_rounds"
    fi
  done

  if ! probe_case_valid "$name" "$shape" "$size" "$rules" "$runtime" "$hi"; then
    return 1
  fi

  while [ $((hi - lo)) -gt 1 ]; do
    mid=$(((lo + hi) / 2))
    if probe_case_valid "$name" "$shape" "$size" "$rules" "$runtime" "$mid"; then
      hi="$mid"
    else
      lo="$mid"
    fi
  done

  echo "$hi"
}

require_positive_int MM2_DIRECT_QUERY_BENCH_RUNS "$runs"
require_positive_int MM2_DIRECT_QUERY_BENCH_TIMEOUT "$timeout_s"
require_positive_int MM2_DIRECT_QUERY_STEPS_PER_ROUND "$steps_per_round"
require_positive_int_list MM2_DIRECT_QUERY_CHAIN_DEPTHS "$chain_depths"
require_positive_int_list MM2_DIRECT_QUERY_AND_WIDTHS "$and_widths"

mkdir -p outputs
if ! mkdir "$lock_dir" 2>/dev/null; then
  echo "another direct MORK query benchmark appears to be running; remove $lock_dir if this is stale" >&2
  exit 2
fi
trap cleanup EXIT

mkdir -p "$prepared_dir" "$logs_dir" "$(dirname "$summary_report")" "$(dirname "$runs_report")"
tmp_dir="$(mktemp -d)"
mkdir -p "$tmp_dir/probes"

printf 'mode\tcase\tshape\tsize\trun\tsteps\tduration_ms\tvalid\tstatus\n' > "$runs_report"

baseline_dir="$prepared_dir/__baseline"
mkdir -p "$baseline_dir"
generate_baseline_case "$baseline_dir"

baseline_steps="$(case_steps baseline 0)"
baseline_times=()
for run_id in $(seq 1 "$runs"); do
  out="$logs_dir/__baseline.$run_id.mm2"
  log="$logs_dir/__baseline.$run_id.log"
  row="$(run_mork_case __baseline baseline 0 "$baseline_dir/rules.mm2" "$baseline_dir/runtime.mm2" "$baseline_steps" "$run_id" "$out" "$log")"
  printf 'baseline\t%s\n' "$row" >> "$runs_report"
  IFS=$'\t' read -r _name _shape _size _run _steps duration_ms valid status <<< "$row"
  if [ "$valid" -ne 1 ] || [ "$status" -ne 0 ]; then
    echo "baseline direct MORK run $run_id failed with status $status; see $log" >&2
    exit 1
  fi
  baseline_times+=("$duration_ms")
done
baseline_median="$(median_ms "${baseline_times[@]}")"

summary_body="$tmp_dir/summary_body.tsv"
: > "$summary_body"
bench_errors=0

for depth in $chain_depths; do
  name="chain_$depth"
  case_dir="$prepared_dir/$name"
  fixed_rounds="$(case_rounds chain "$depth")"
  mkdir -p "$case_dir"
  generate_chain_case "$depth" "$case_dir"
  if ! run_case "$name" fixed_budget chain "$depth" "$case_dir/rules.mm2" "$case_dir/runtime.mm2" \
      "$fixed_rounds" "$baseline_median" >> "$summary_body"; then
    bench_errors=1
  fi
  if answer_rounds="$(find_answer_rounds "$name" chain "$depth" "$case_dir/rules.mm2" "$case_dir/runtime.mm2" "$fixed_rounds")"; then
    if ! run_case "$name" first_answer chain "$depth" "$case_dir/rules.mm2" "$case_dir/runtime.mm2" \
        "$answer_rounds" "$baseline_median" >> "$summary_body"; then
      bench_errors=1
    fi
  else
    printf 'direct MORK benchmark could not find first-answer round for %s within %s rounds\n' "$name" "$fixed_rounds" >&2
    bench_errors=1
  fi
done

for width in $and_widths; do
  name="and_adapter_$width"
  case_dir="$prepared_dir/$name"
  fixed_rounds="$(case_rounds and_adapter "$width")"
  mkdir -p "$case_dir"
  generate_and_adapter_case "$width" "$case_dir"
  if ! run_case "$name" fixed_budget and_adapter "$width" "$case_dir/rules.mm2" "$case_dir/runtime.mm2" \
      "$fixed_rounds" "$baseline_median" >> "$summary_body"; then
    bench_errors=1
  fi
  if answer_rounds="$(find_answer_rounds "$name" and_adapter "$width" "$case_dir/rules.mm2" "$case_dir/runtime.mm2" "$fixed_rounds")"; then
    if ! run_case "$name" first_answer and_adapter "$width" "$case_dir/rules.mm2" "$case_dir/runtime.mm2" \
        "$answer_rounds" "$baseline_median" >> "$summary_body"; then
      bench_errors=1
    fi
  else
    printf 'direct MORK benchmark could not find first-answer round for %s within %s rounds\n' "$name" "$fixed_rounds" >&2
    bench_errors=1
  fi
done

{
  printf 'case\tmode\tshape\tsize\trounds\tsteps\tgross_median_ms\tgross_min_ms\tgross_max_ms\tbaseline_median_ms\tnet_median_ms\tvalid_runs\n'
  printf '%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\n' \
    __baseline baseline baseline 0 "$(case_rounds baseline 0)" "$baseline_steps" "$baseline_median" \
    "$(min_ms "${baseline_times[@]}")" "$(max_ms "${baseline_times[@]}")" \
    "$baseline_median" 0 "$runs"
  cat "$summary_body"
} > "$summary_report"

cat "$summary_report"

if [ "$bench_errors" -ne 0 ]; then
  exit 1
fi
