#!/usr/bin/env bash
# Run a small ConceptNet query scaling matrix.
#
# Each matrix entry is "objects:pet-only:own-only:other-distractors". The
# underlying benchmark records mm2/MORK exec time and PeTTaChainer query-only
# time, while this wrapper keeps the per-case output directories separate and
# collects one summary table.
#
# Defaults:
#   MM2_CONCEPTNET_SCALE_RUNS=1
#   MM2_CONCEPTNET_SCALE_STEPS=1000
#   MM2_CONCEPTNET_SCALE_PETTA_STEPS=$MM2_CONCEPTNET_SCALE_STEPS
#   MM2_CONCEPTNET_SCALE_CASES="2:0:0:0 8:8:8:16 16:16:16:32"
#   MM2_CONCEPTNET_SCALE_PETTA=1
#   MM2_CONCEPTNET_SCALE_TIMING=1
#
# Example:
#   bash scripts/bench-conceptnet-scale.sh
#   MM2_CONCEPTNET_SCALE_CASES="8:8:8:16 32:32:32:64" bash scripts/bench-conceptnet-scale.sh

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

runs="${MM2_CONCEPTNET_SCALE_RUNS:-1}"
steps="${MM2_CONCEPTNET_SCALE_STEPS:-${MM2_CONCEPTNET_BENCH_STEPS:-1000}}"
petta_steps="${MM2_CONCEPTNET_SCALE_PETTA_STEPS:-${MM2_CONCEPTNET_BENCH_PETTA_STEPS:-$steps}}"
timeout_s="${MM2_CONCEPTNET_SCALE_TIMEOUT:-${MM2_CONCEPTNET_BENCH_TIMEOUT:-180}}"
run_petta="${MM2_CONCEPTNET_SCALE_PETTA:-1}"
run_timing="${MM2_CONCEPTNET_SCALE_TIMING:-1}"
cases="${MM2_CONCEPTNET_SCALE_CASES:-2:0:0:0 8:8:8:16 16:16:16:32}"
out_dir="${MM2_CONCEPTNET_SCALE_OUT_DIR:-outputs/conceptnet_query_scale}"
summary="$out_dir/summary.tsv"

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

parse_case() {
  local spec="$1"
  local objects pet own other extra

  IFS=: read -r objects pet own other extra <<< "$spec"
  if [ -n "${extra:-}" ] || [ -z "${objects:-}" ] || [ -z "${pet:-}" ] || [ -z "${own:-}" ] || [ -z "${other:-}" ]; then
    echo "case must have the form objects:pet-only:own-only:other-distractors, got: $spec" >&2
    exit 2
  fi

  require_positive_int MM2_CONCEPTNET_SCALE_CASE_OBJECTS "$objects"
  require_nonnegative_int MM2_CONCEPTNET_SCALE_CASE_PET_DISTRACTORS "$pet"
  require_nonnegative_int MM2_CONCEPTNET_SCALE_CASE_OWN_DISTRACTORS "$own"
  require_nonnegative_int MM2_CONCEPTNET_SCALE_CASE_OTHER_DISTRACTORS "$other"

  printf '%s\t%s\t%s\t%s\n' "$objects" "$pet" "$own" "$other"
}

case_name() {
  local objects="$1"
  local pet="$2"
  local own="$3"
  local other="$4"

  printf 'o%s_p%s_w%s_x%s' "$objects" "$pet" "$own" "$other"
}

require_positive_int MM2_CONCEPTNET_SCALE_RUNS "$runs"
require_nonnegative_int MM2_CONCEPTNET_SCALE_STEPS "$steps"
require_nonnegative_int MM2_CONCEPTNET_SCALE_PETTA_STEPS "$petta_steps"
require_positive_int MM2_CONCEPTNET_SCALE_TIMEOUT "$timeout_s"

mkdir -p "$out_dir"
printf 'case\tobjects\tpet_distractors\town_distractors\tother_distractors\tmm2_steps\tpetta_steps\tengine\truns\tmedian_wall_ms\tmedian_exec_or_query_ms\tanswers\tstatuses\tout_dir\n' > "$summary"

for spec in $cases; do
  IFS=$'\t' read -r objects pet own other < <(parse_case "$spec")
  name="$(case_name "$objects" "$pet" "$own" "$other")"
  case_dir="$out_dir/$name"

  echo "running ConceptNet scale case $name"
  MM2_CONCEPTNET_BENCH_RUNS="$runs" \
    MM2_CONCEPTNET_BENCH_STEPS="$steps" \
    MM2_CONCEPTNET_BENCH_PETTA_STEPS="$petta_steps" \
    MM2_CONCEPTNET_BENCH_TIMEOUT="$timeout_s" \
    MM2_CONCEPTNET_BENCH_PETTA="$run_petta" \
    MM2_CONCEPTNET_BENCH_TIMING="$run_timing" \
    MM2_CONCEPTNET_BENCH_OBJECTS="$objects" \
    MM2_CONCEPTNET_BENCH_PET_DISTRACTORS="$pet" \
    MM2_CONCEPTNET_BENCH_OWN_DISTRACTORS="$own" \
    MM2_CONCEPTNET_BENCH_OTHER_DISTRACTORS="$other" \
    MM2_CONCEPTNET_BENCH_OUT_DIR="$case_dir" \
    bash scripts/bench-conceptnet-query.sh

  awk -F '\t' -v case_name="$name" -v objects="$objects" -v pet="$pet" -v own="$own" -v other="$other" -v steps="$steps" -v petta_steps="$petta_steps" -v case_dir="$case_dir" '
    NR > 1 {
      printf "%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\n",
        case_name, objects, pet, own, other, steps, petta_steps, $1, $2, $3, $4, $5, $6, case_dir
    }' "$case_dir/summary.tsv" >> "$summary"
done

echo
cat "$summary"
echo
echo "scale summary: $summary"
