#!/usr/bin/env bash
# Benchmark the pendingN scheduler batch size with a directly seeded queue.
#
# Every pending goal has one distinct, already-proved premise. The run uses the
# real scheduler, premise traversal, proof production, and merge stages, while
# avoiding the unrelated cost and scheduling variability of loading ConceptNet.
# Cases rotate between rounds to balance cache warmth.
#
# Defaults:
#   MM2_SCHEDULER_BENCH_BATCH_SIZES="1 4 8 16 32 64 128 256 512 1024"
#   MM2_SCHEDULER_BENCH_RUNS=5
#   MM2_SCHEDULER_BENCH_WARMUP_ROUNDS=1
#   MM2_SCHEDULER_BENCH_PENDING_GOALS=4096
#   MM2_SCHEDULER_BENCH_VALUABLE_GOALS=256
#   MM2_SCHEDULER_BENCH_STEPS=1000

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

batch_sizes="${MM2_SCHEDULER_BENCH_BATCH_SIZES:-1 4 8 16 32 64 128 256 512 1024}"
runs="${MM2_SCHEDULER_BENCH_RUNS:-5}"
warmup_rounds="${MM2_SCHEDULER_BENCH_WARMUP_ROUNDS:-1}"
pending_goals="${MM2_SCHEDULER_BENCH_PENDING_GOALS:-4096}"
valuable_goals="${MM2_SCHEDULER_BENCH_VALUABLE_GOALS:-256}"
steps="${MM2_SCHEDULER_BENCH_STEPS:-1000}"
timeout_s="${MM2_SCHEDULER_BENCH_TIMEOUT:-180}"
out_dir="${MM2_SCHEDULER_BENCH_OUT_DIR:-outputs/scheduler_batch_bench}"
runs_report="$out_dir/runs.tsv"
summary_report="$out_dir/summary.tsv"
lock_dir="outputs/.bench-scheduler-batch.lock"

require_nonnegative_int() {
  local name="$1"
  local value="$2"
  case "$value" in
    ''|*[!0-9]*)
      echo "$name must be a non-negative integer, got: $value" >&2
      exit 2
      ;;
  esac
}

require_positive_int() {
  local name="$1"
  local value="$2"
  require_nonnegative_int "$name" "$value"
  if [ "$value" -lt 1 ]; then
    echo "$name must be a positive integer, got: $value" >&2
    exit 2
  fi
}

now_ns() {
  date +%s%N
}

parse_mork_counters() {
  local log="$1"
  sed -n \
    's/.*executing .* took \([0-9][0-9]*\) ms (unifications \([0-9][0-9]*\), writes \([0-9][0-9]*\), transitions \([0-9][0-9]*\)).*/\1\t\2\t\3\t\4/p' \
    "$log" | tail -n 1
}

cleanup() {
  rm -rf "$lock_dir"
}

require_positive_int MM2_SCHEDULER_BENCH_RUNS "$runs"
require_nonnegative_int MM2_SCHEDULER_BENCH_WARMUP_ROUNDS "$warmup_rounds"
require_positive_int MM2_SCHEDULER_BENCH_PENDING_GOALS "$pending_goals"
require_positive_int MM2_SCHEDULER_BENCH_VALUABLE_GOALS "$valuable_goals"
require_nonnegative_int MM2_SCHEDULER_BENCH_STEPS "$steps"
require_positive_int MM2_SCHEDULER_BENCH_TIMEOUT "$timeout_s"
if [ "$valuable_goals" -gt "$pending_goals" ]; then
  echo "MM2_SCHEDULER_BENCH_VALUABLE_GOALS cannot exceed MM2_SCHEDULER_BENCH_PENDING_GOALS" >&2
  exit 2
fi

sizes=()
for batch_size in $batch_sizes; do
  require_positive_int MM2_SCHEDULER_BENCH_BATCH_SIZES "$batch_size"
  sizes+=("$batch_size")
done
if [ "${#sizes[@]}" -eq 0 ]; then
  echo "MM2_SCHEDULER_BENCH_BATCH_SIZES must contain at least one positive integer" >&2
  exit 2
fi

mkdir -p outputs
if ! mkdir "$lock_dir" 2>/dev/null; then
  echo "another scheduler batch benchmark appears to be running; remove $lock_dir if this is stale" >&2
  exit 2
fi
trap cleanup EXIT

mkdir -p "$out_dir"
seed="$out_dir/seed.mm2"
{
  printf '; generated scheduler benchmark with %s pending goals; first %s are valuable\n' "$pending_goals" "$valuable_goals"
  for i in $(seq 1 "$pending_goals"); do
    goal_kind=Speculative
    if [ "$i" -le "$valuable_goals" ]; then
      goal_kind=Valuable
    fi
    printf '(pendingN %09d (%sSchedulerBenchGoal g%06d) identity (pcons (SchedulerBenchPremise p%06d) pnil) pnil)\n' "$i" "$goal_kind" "$i" "$i"
    printf '(fact (SchedulerBenchPremise p%06d) (1.0 1.0))\n' "$i"
    printf '(fact-evidence (SchedulerBenchPremise p%06d) (1.0 1.0) (pcons (fact-ev (SchedulerBenchPremise p%06d)) pnil))\n' "$i" "$i"
  done
} > "$seed"

for batch_size in "${sizes[@]}"; do
  MM2_SCHEDULER_BATCH_SIZE="$batch_size" \
    bash scripts/build-runtime.sh "$out_dir/runtime_b${batch_size}.mm2" "$seed"
done

printf 'batch_size\tround\torder\tstatus\twall_ms\texec_ms\tunifications\twrites\ttransitions\tcompleted_goals\tvaluable_completed\tspeculative_completed\tpending_goals\tlog\n' > "$runs_report"

run_sample() {
  local batch_size="$1"
  local round="$2"
  local order="$3"
  local measured="$4"
  local runtime="$out_dir/runtime_b${batch_size}.mm2"
  local stem="sample_b${batch_size}_r${round}"
  local out log start_ns end_ns status wall_ms counters
  local exec_ms unifications writes transitions completed valuable speculative remaining

  if [ "$measured" = "0" ]; then
    stem="warmup_b${batch_size}_r${round}"
  fi
  out="$out_dir/$stem.mm2"
  log="$out_dir/$stem.log"

  echo "scheduler batch=$batch_size round=$round order=$order measured=$measured"
  start_ns="$(now_ns)"
  set +e
  timeout "$timeout_s" mork run "$runtime" --steps "$steps" "$out" > "$log" 2>&1
  status=$?
  set -e
  end_ns="$(now_ns)"
  wall_ms=$(((end_ns - start_ns) / 1000000))

  counters="$(parse_mork_counters "$log")"
  if [ -n "$counters" ]; then
    IFS=$'\t' read -r exec_ms unifications writes transitions <<< "$counters"
  else
    exec_ms=0
    unifications=0
    writes=0
    transitions=0
  fi
  valuable="$(LC_ALL=C grep -c '^(fact (ValuableSchedulerBenchGoal ' "$out" || true)"
  speculative="$(LC_ALL=C grep -c '^(fact (SpeculativeSchedulerBenchGoal ' "$out" || true)"
  completed=$((valuable + speculative))
  remaining="$(LC_ALL=C grep -c '^(pendingN ' "$out" || true)"

  if [ "$measured" = "1" ]; then
    printf '%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\n' \
      "$batch_size" "$round" "$order" "$status" "$wall_ms" "$exec_ms" \
      "$unifications" "$writes" "$transitions" "$completed" "$valuable" \
      "$speculative" "$remaining" "$log" \
      >> "$runs_report"
  else
    rm -f "$log"
  fi
  rm -f "$out"
}

# Rotate the first case deterministically each round.
total_rounds=$((warmup_rounds + runs))
for round in $(seq 1 "$total_rounds"); do
  measured=0
  measured_round=$round
  if [ "$round" -gt "$warmup_rounds" ]; then
    measured=1
    measured_round=$((round - warmup_rounds))
  fi
  offset=$(((round - 1) % ${#sizes[@]}))
  for order in $(seq 0 $((${#sizes[@]} - 1))); do
    index=$(((offset + order) % ${#sizes[@]}))
    run_sample "${sizes[$index]}" "$measured_round" "$((order + 1))" "$measured"
  done
done

median_for() {
  local batch_size="$1"
  local column="$2"
  awk -F '\t' -v batch="$batch_size" -v column="$column" '
    $1 == batch { values[++n] = $column }
    END {
      if (n == 0) { print 0; exit }
      for (i = 1; i <= n; i++)
        for (j = i + 1; j <= n; j++)
          if (values[j] < values[i]) {
            tmp = values[i]; values[i] = values[j]; values[j] = tmp
          }
      if (n % 2) print values[(n + 1) / 2]
      else print int((values[n / 2] + values[n / 2 + 1]) / 2)
    }' "$runs_report"
}

printf 'batch_size\truns\tmedian_wall_ms\tmedian_exec_ms\tmedian_unifications\tmedian_writes\tmedian_transitions\tmin_completed\tmax_completed\tmin_valuable\tmax_valuable\tmin_speculative\tmax_speculative\tmin_pending\tmax_pending\tvaluable_per_exec_ms\tcompleted_per_exec_ms\tvaluable_fraction\ttransitions_per_exec_ms\tstatuses\n' > "$summary_report"
for batch_size in "${sizes[@]}"; do
  median_wall="$(median_for "$batch_size" 5)"
  median_exec="$(median_for "$batch_size" 6)"
  median_unifications="$(median_for "$batch_size" 7)"
  median_writes="$(median_for "$batch_size" 8)"
  median_transitions="$(median_for "$batch_size" 9)"
  min_completed="$(awk -F '\t' -v batch="$batch_size" '$1 == batch && (!seen || $10 < value) { value=$10; seen=1 } END { print value + 0 }' "$runs_report")"
  max_completed="$(awk -F '\t' -v batch="$batch_size" '$1 == batch && (!seen || $10 > value) { value=$10; seen=1 } END { print value + 0 }' "$runs_report")"
  min_valuable="$(awk -F '\t' -v batch="$batch_size" '$1 == batch && (!seen || $11 < value) { value=$11; seen=1 } END { print value + 0 }' "$runs_report")"
  max_valuable="$(awk -F '\t' -v batch="$batch_size" '$1 == batch && (!seen || $11 > value) { value=$11; seen=1 } END { print value + 0 }' "$runs_report")"
  min_speculative="$(awk -F '\t' -v batch="$batch_size" '$1 == batch && (!seen || $12 < value) { value=$12; seen=1 } END { print value + 0 }' "$runs_report")"
  max_speculative="$(awk -F '\t' -v batch="$batch_size" '$1 == batch && (!seen || $12 > value) { value=$12; seen=1 } END { print value + 0 }' "$runs_report")"
  min_pending="$(awk -F '\t' -v batch="$batch_size" '$1 == batch && (!seen || $13 < value) { value=$13; seen=1 } END { print value + 0 }' "$runs_report")"
  max_pending="$(awk -F '\t' -v batch="$batch_size" '$1 == batch && (!seen || $13 > value) { value=$13; seen=1 } END { print value + 0 }' "$runs_report")"
  statuses="$(awk -F '\t' -v batch="$batch_size" '$1 == batch { printf "%s%s", sep, $4; sep="," }' "$runs_report")"
  valuable_throughput="$(awk -v completed="$min_valuable" -v ms="$median_exec" 'BEGIN { if (ms == 0) print 0; else printf "%.3f", completed / ms }')"
  completed_throughput="$(awk -v completed="$min_completed" -v ms="$median_exec" 'BEGIN { if (ms == 0) print 0; else printf "%.3f", completed / ms }')"
  valuable_fraction="$(awk -v valuable="$min_valuable" -v completed="$min_completed" 'BEGIN { if (completed == 0) print 0; else printf "%.3f", valuable / completed }')"
  throughput="$(awk -v transitions="$median_transitions" -v ms="$median_exec" 'BEGIN { if (ms == 0) print 0; else printf "%.1f", transitions / ms }')"
  printf '%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\n' \
    "$batch_size" "$runs" "$median_wall" "$median_exec" "$median_unifications" \
    "$median_writes" "$median_transitions" "$min_completed" "$max_completed" \
    "$min_valuable" "$max_valuable" "$min_speculative" "$max_speculative" \
    "$min_pending" "$max_pending" "$valuable_throughput" "$completed_throughput" \
    "$valuable_fraction" "$throughput" "$statuses" >> "$summary_report"
done

echo
cat "$summary_report"
echo
echo "scheduler batch runs: $runs_report"
echo "scheduler batch summary: $summary_report"
