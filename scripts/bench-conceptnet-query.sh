#!/usr/bin/env bash
# Benchmark and profile the x.metta-style ConceptNet query.
#
# The mm2 case runs the converted full ConceptNet rule export directly through
# MORK with the same seed facts and compound-query adapter used by the
# PeTTaChainer x.metta probe:
#
#   Goal: (And (Own (i $a)) (Pet $a))
#   Facts: mixed Pet-side and Own-side routes for complete answer objects,
#          plus optional one-sided and unrelated distractors.
#
# Defaults:
#   MM2_CONCEPTNET_BENCH_RUNS=3
#   MM2_CONCEPTNET_BENCH_STEPS=1000
#   MM2_CONCEPTNET_BENCH_TIMEOUT=180
#   MM2_CONCEPTNET_BENCH_PETTA=1
#   MM2_CONCEPTNET_BENCH_TIMING=1
#   MM2_CONCEPTNET_BENCH_OBJECTS=8
#   MM2_CONCEPTNET_BENCH_PET_DISTRACTORS=8
#   MM2_CONCEPTNET_BENCH_OWN_DISTRACTORS=8
#   MM2_CONCEPTNET_BENCH_OTHER_DISTRACTORS=16
#
# Reports:
#   outputs/conceptnet_query_bench/runs.tsv
#   outputs/conceptnet_query_bench/summary.tsv
#   outputs/conceptnet_query_bench/profile.tsv when timing is enabled

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

runs="${MM2_CONCEPTNET_BENCH_RUNS:-3}"
steps="${MM2_CONCEPTNET_BENCH_STEPS:-1000}"
timeout_s="${MM2_CONCEPTNET_BENCH_TIMEOUT:-180}"
run_petta="${MM2_CONCEPTNET_BENCH_PETTA:-1}"
petta_steps="${MM2_CONCEPTNET_BENCH_PETTA_STEPS:-$steps}"
run_timing="${MM2_CONCEPTNET_BENCH_TIMING:-1}"
objects="${MM2_CONCEPTNET_BENCH_OBJECTS:-8}"
pet_distractors="${MM2_CONCEPTNET_BENCH_PET_DISTRACTORS:-8}"
own_distractors="${MM2_CONCEPTNET_BENCH_OWN_DISTRACTORS:-8}"
other_distractors="${MM2_CONCEPTNET_BENCH_OTHER_DISTRACTORS:-16}"
out_dir="${MM2_CONCEPTNET_BENCH_OUT_DIR:-outputs/conceptnet_query_bench}"
petta_root="${PETTACHAINER_ROOT:-$ROOT_DIR/../PeTTaChainer}"
lock_dir="outputs/.bench-conceptnet-query.lock"
petta_tmp=""

pet_routes=(Cat Bird Ferret Frog Horse Puppy Snake Turtle CompanionAnimal BestLoved Darling PairedEndTag)
own_routes=(Possess Hold Ain Beat Confess Responsible Have)

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

median_ms() {
  if [ "$#" -eq 0 ]; then
    echo 0
    return
  fi
  printf '%s\n' "$@" |
    sort -n |
    awk '
      { values[NR] = $1 }
      END {
        if (NR % 2 == 1) {
          print values[(NR + 1) / 2]
        } else {
          print int((values[NR / 2] + values[NR / 2 + 1]) / 2)
        }
      }'
}

cleanup() {
  rm -rf "$lock_dir"
  if [ -n "$petta_tmp" ]; then
    rm -f "$petta_tmp"
  fi
}

positive_object_name() {
  local idx="$1"
  case "$idx" in
    1) printf 'max' ;;
    2) printf 'ann' ;;
    *) printf 'obj%03d' "$idx" ;;
  esac
}

answer_own_route_for() {
  local idx="$1"
  local route_idx

  if [ "$idx" -le 2 ]; then
    printf 'Have'
    return
  fi

  route_idx=$(((idx - 3) % ${#own_routes[@]}))
  printf '%s' "${own_routes[$route_idx]}"
}

pet_route_for() {
  local idx="$1"
  local route_idx

  route_idx=$(((idx - 1) % ${#pet_routes[@]}))
  printf '%s' "${pet_routes[$route_idx]}"
}

own_route_for() {
  local idx="$1"
  local route_idx

  route_idx=$(((idx - 1) % ${#own_routes[@]}))
  printf '%s' "${own_routes[$route_idx]}"
}

other_distractor_term() {
  local idx="$1"
  local obj
  obj="$(printf 'other%03d' "$idx")"

  case $(((idx - 1) % 10)) in
    0) printf '(Car %s)' "$obj" ;;
    1) printf '(Toy %s)' "$obj" ;;
    2) printf '(Keep %s)' "$obj" ;;
    3) printf '(Person %s)' "$obj" ;;
    4) printf '(Have %s)' "$obj" ;;
    5) printf '(Dog (i %s))' "$obj" ;;
    6) printf '(Possess %s)' "$obj" ;;
    7) printf '(Cat (i %s))' "$obj" ;;
    8) printf '(Ball %s)' "$obj" ;;
    9) printf '(Machine %s)' "$obj" ;;
  esac
}

emit_mm2_fact() {
  local term="$1"
  local proof_id="$2"

  printf '(fact %s (1.0 1.0))\n' "$term"
  printf '(fact-evidence %s (1.0 1.0) (pcons (fact-ev %s) pnil))\n' "$term" "$term"
  printf '(proved %s (1.0 1.0) %s (pcons (fact-ev %s) pnil))\n' "$term" "$proof_id" "$term"
}

emit_petta_fact() {
  local term="$1"
  local proof_id="$2"

  printf '!(compileadd (kb) (: %s %s (STV 1.0 1.0)))\n' "$proof_id" "$term"
}

emit_seed_facts() {
  local format="$1"
  local i obj pet_pred extra_pet_pred own_pred term
  local emit_fact

  case "$format" in
    mm2) emit_fact=emit_mm2_fact ;;
    petta) emit_fact=emit_petta_fact ;;
    *)
      echo "unknown seed format: $format" >&2
      exit 2
      ;;
  esac

  for i in $(seq 1 "$objects"); do
    obj="$(positive_object_name "$i")"
    own_pred="$(answer_own_route_for "$i")"
    "$emit_fact" "(Dog $obj)" "seed_complete_${i}_dog"
    if [ "$i" -gt 2 ]; then
      extra_pet_pred="$(pet_route_for "$((i - 2))")"
      "$emit_fact" "($extra_pet_pred $obj)" "seed_complete_${i}_pet_extra"
    fi
    "$emit_fact" "($own_pred (i $obj))" "seed_complete_${i}_own"
  done

  for i in $(seq 1 "$pet_distractors"); do
    obj="$(printf 'petonly%03d' "$i")"
    pet_pred="$(pet_route_for "$i")"
    "$emit_fact" "($pet_pred $obj)" "seed_pet_only_$i"
  done

  for i in $(seq 1 "$own_distractors"); do
    obj="$(printf 'ownonly%03d' "$i")"
    own_pred="$(own_route_for "$i")"
    "$emit_fact" "($own_pred (i $obj))" "seed_own_only_$i"
  done

  for i in $(seq 1 "$other_distractors"); do
    term="$(other_distractor_term "$i")"
    "$emit_fact" "$term" "seed_other_$i"
  done
}

write_seed() {
  local seed="$1"
  cat > "$seed" <<EOF
; generated ConceptNet query seed
; complete answer objects: $objects
; pet-only distractors: $pet_distractors
; own-only distractors: $own_distractors
; unrelated distractors: $other_distractors
(, (Goal (And (Own (i \$a)) (Pet \$a))))
(adapterN (And (Own (i \$a)) (Pet \$a)) (pcons (Own (i \$a)) (pcons (Pet \$a) pnil)))
EOF
  emit_seed_facts mm2 >> "$seed"
}

parse_mork_counters() {
  local log="$1"
  sed -n \
    's/.*executing .* took \([0-9][0-9]*\) ms (unifications \([0-9][0-9]*\), writes \([0-9][0-9]*\), transitions \([0-9][0-9]*\)).*/\1\t\2\t\3\t\4/p' \
    "$log" |
    tail -n 1
}

count_mm2_answers() {
  local out="$1"
  LC_ALL=C awk 'index($0, "(fact (And (Own (i ") == 1 { c++ } END { print c + 0 }' "$out"
}

first_mm2_answer() {
  local out="$1"
  LC_ALL=C awk 'index($0, "(fact (And (Own (i ") == 1 { print; exit }' "$out"
}

write_petta_probe() {
  local file="$1"
  cat > "$file" <<EOF
!(import! &self petta_chainer)
!(import! &self (library lib_import))
!(static-import! &self ../../../cnet/rules_dump)
(= (kb) kb5b10000f8f9f4f0dbd120f99aa0f43ce)
; generated ConceptNet query seed
; complete answer objects: $objects
; pet-only distractors: $pet_distractors
; own-only distractors: $own_distractors
; unrelated distractors: $other_distractors
$(emit_seed_facts petta)
!(let*
   ((\$t0 (current-time))
    (\$res (collapse (query $petta_steps (kb) (: \$prf (And (Own (i \$a)) (Pet \$a)) \$tv))))
    (\$t1 (current-time)))
   (pettachainer-query-seconds (- \$t1 \$t0) \$res))
EOF
}

run_petta_case() {
  local run_id="$1"
  local log="$out_dir/petta.$run_id.log"
  local start_ns end_ns status wall_ms seconds query_ms answers first_answer

  start_ns="$(now_ns)"
  set +e
  (
    cd "$petta_root"
    timeout "$timeout_s" petta "pettachainer/metta/$(basename "$petta_tmp")"
  ) > "$log" 2>&1
  status=$?
  set -e
  end_ns="$(now_ns)"
  wall_ms=$(((end_ns - start_ns) / 1000000))
  seconds="$(sed -n 's/.*pettachainer-query-seconds \([^ ]*\).*/\1/p' "$log" | head -n 1)"
  if [ -n "$seconds" ]; then
    query_ms="$(awk -v seconds="$seconds" 'BEGIN { printf "%d", (seconds * 1000) + 0.5 }')"
  else
    query_ms=0
  fi
  answers="$(LC_ALL=C grep -o '(: (conjunction' "$log" 2>/dev/null | wc -l | tr -d ' ')"
  first_answer="$(LC_ALL=C grep -o '(: (conjunction.*' "$log" 2>/dev/null | head -n 1 || true)"

  printf 'pettachainer\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\n' \
    "$run_id" "$petta_steps" "$status" "$wall_ms" "$query_ms" 0 0 0 "$answers" "$log" "$first_answer" \
    >> "$out_dir/runs.tsv"
}

run_mm2_case() {
  local run_id="$1"
  local runtime="$2"
  local out="$out_dir/mm2.$run_id.mm2"
  local log="$out_dir/mm2.$run_id.log"
  local start_ns end_ns status wall_ms counters exec_ms unifications writes transitions answers first_answer

  start_ns="$(now_ns)"
  set +e
  timeout "$timeout_s" mork run rules/full_rules.mm2 --steps "$steps" --aux-path "$runtime" "$out" > "$log" 2>&1
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
  answers="$(count_mm2_answers "$out")"
  first_answer="$(first_mm2_answer "$out")"

  printf 'mm2\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\n' \
    "$run_id" "$steps" "$status" "$wall_ms" "$exec_ms" "$unifications" "$writes" "$transitions" \
    "$answers" "$log" "$first_answer" >> "$out_dir/runs.tsv"
}

profile_mm2_timing() {
  local runtime="$1"
  local out="$out_dir/mm2.timing.mm2"
  local log="$out_dir/mm2.timing.log"

  timeout "$timeout_s" mork run rules/full_rules.mm2 --steps "$steps" --timing --aux-path "$runtime" "$out" > "$log" 2>&1

  LC_ALL=C awk '
    index($0, "(timing ") == 1 {
      line = $0
      sub(/^\(timing /, "", line)
      sub(/\)$/, "", line)
      n = split(line, fields, " ")
      ns = fields[n] + 0
      step = fields[n - 1]
      expr = line
      suffix = " " step " " fields[n]
      sub(suffix "$", "", expr)
      count[expr] += 1
      total[expr] += ns
      if (ns > max[expr]) max[expr] = ns
    }
    END {
      for (expr in total) {
        printf "%d\t%d\t%d\t%s\n", total[expr], count[expr], max[expr], expr
      }
    }' "$out" |
    sort -nr |
    awk 'BEGIN { print "total_ms\tcount\tavg_us\tmax_us\texec" }
      {
        total_ns = $1
        count = $2
        max_ns = $3
        $1 = ""; $2 = ""; $3 = ""
        sub(/^[ \t]+/, "")
        printf "%.3f\t%d\t%.1f\t%.1f\t%s\n", total_ns / 1000000, count, total_ns / count / 1000, max_ns / 1000, $0
      }' > "$out_dir/profile.tsv"

  LC_ALL=C awk '
    index($0, "(timing (exec ") == 1 {
      line = $0
      sub(/^\(timing \(exec /, "", line)
      n = split(line, fields, " ")
      prio = fields[1]
      ns = fields[n] + 0
      count[prio] += 1
      total[prio] += ns
    }
    END {
      for (prio in total) printf "%s\t%d\t%.3f\n", prio, count[prio], total[prio] / 1000000
    }' "$out" |
    sort -k3,3nr > "$out_dir/profile_by_priority.tsv"
}

write_summary() {
  local engine walls execs count wall_median exec_median answers statuses
  printf 'engine\truns\tmedian_wall_ms\tmedian_exec_or_query_ms\tanswers\tstatuses\n' > "$out_dir/summary.tsv"
  while IFS= read -r engine; do
    [ -n "$engine" ] || continue
    mapfile -t walls < <(awk -F '\t' -v engine="$engine" 'NR > 1 && $1 == engine { print $5 }' "$out_dir/runs.tsv")
    mapfile -t execs < <(awk -F '\t' -v engine="$engine" 'NR > 1 && $1 == engine { print $6 }' "$out_dir/runs.tsv")
    count="${#walls[@]}"
    wall_median="$(median_ms "${walls[@]}")"
    exec_median="$(median_ms "${execs[@]}")"
    answers="$(awk -F '\t' -v engine="$engine" 'NR > 1 && $1 == engine { value = $10 } END { print value }' "$out_dir/runs.tsv")"
    statuses="$(awk -F '\t' -v engine="$engine" 'NR > 1 && $1 == engine { printf "%s%s", sep, $4; sep = "," }' "$out_dir/runs.tsv")"
    printf '%s\t%s\t%s\t%s\t%s\t%s\n' "$engine" "$count" "$wall_median" "$exec_median" "$answers" "$statuses" >> "$out_dir/summary.tsv"
  done < <(awk -F '\t' 'NR > 1 { print $1 }' "$out_dir/runs.tsv" | sort -u)
}

require_positive_int MM2_CONCEPTNET_BENCH_RUNS "$runs"
require_nonnegative_int MM2_CONCEPTNET_BENCH_STEPS "$steps"
require_nonnegative_int MM2_CONCEPTNET_BENCH_PETTA_STEPS "$petta_steps"
require_positive_int MM2_CONCEPTNET_BENCH_TIMEOUT "$timeout_s"
require_positive_int MM2_CONCEPTNET_BENCH_OBJECTS "$objects"
require_nonnegative_int MM2_CONCEPTNET_BENCH_PET_DISTRACTORS "$pet_distractors"
require_nonnegative_int MM2_CONCEPTNET_BENCH_OWN_DISTRACTORS "$own_distractors"
require_nonnegative_int MM2_CONCEPTNET_BENCH_OTHER_DISTRACTORS "$other_distractors"

mkdir -p outputs
if ! mkdir "$lock_dir" 2>/dev/null; then
  echo "another ConceptNet query benchmark appears to be running; remove $lock_dir if this is stale" >&2
  exit 2
fi
trap cleanup EXIT

mkdir -p "$out_dir"
seed="$out_dir/seed.mm2"
runtime="$out_dir/runtime.mm2"
write_seed "$seed"
bash scripts/build-runtime.sh "$runtime" "$seed"

printf 'engine\trun\tsteps\tstatus\twall_ms\texec_or_query_ms\tunifications\twrites\ttransitions\tanswers\tlog\tfirst_answer\n' > "$out_dir/runs.tsv"

for run_id in $(seq 1 "$runs"); do
  run_mm2_case "$run_id" "$runtime"
done

if [ "$run_petta" = "1" ]; then
  if [ -d "$petta_root/pettachainer/metta" ]; then
    petta_tmp="$petta_root/pettachainer/metta/.mm2_conceptnet_query_bench_tmp.metta"
    write_petta_probe "$petta_tmp"
    for run_id in $(seq 1 "$runs"); do
      run_petta_case "$run_id"
    done
  else
    echo "PeTTaChainer checkout not found at $petta_root; skipping PeTTaChainer comparison" >&2
  fi
fi

write_summary

if [ "$run_timing" = "1" ]; then
  profile_mm2_timing "$runtime"
fi

cat "$out_dir/summary.tsv"
echo
echo "runs: $out_dir/runs.tsv"
if [ "$run_timing" = "1" ]; then
  echo "top mm2 timing entries: $out_dir/profile.tsv"
  sed -n '1,12p' "$out_dir/profile.tsv"
fi
