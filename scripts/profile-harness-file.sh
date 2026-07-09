#!/usr/bin/env bash
# Time cumulative prefixes of one generated harness fixture.
#
# This is a coarse profiler: each selected line is run in a fresh petta process
# with the fixture truncated after that line. The reported delta is the
# difference from the previous selected prefix, so startup noise is mostly
# cancelled but still not eliminated.

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

timeout_s="${MM2_PROFILE_TIMEOUT:-300}"
pattern="${MM2_PROFILE_PATTERN:-^!\(mm2-test}"

case "$timeout_s" in
  ''|*[!0-9]*)
    echo "MM2_PROFILE_TIMEOUT must be a positive integer, got: $timeout_s" >&2
    exit 2
    ;;
esac
if [ "$timeout_s" -lt 1 ]; then
  echo "MM2_PROFILE_TIMEOUT must be a positive integer, got: $timeout_s" >&2
  exit 2
fi

if [ "$#" -ne 1 ]; then
  echo "usage: bash scripts/profile-harness-file.sh <generated-fixture-or-stem>" >&2
  exit 2
fi

requested="$1"
case "$requested" in
  *.metta)
    fixture="$requested"
    ;;
  *)
    fixture="tests/harness/generated/$requested.metta"
    ;;
esac

if [ ! -f "$fixture" ]; then
  echo "generated test not found: $requested" >&2
  exit 2
fi

bash scripts/build-runtime.sh outputs/harness_runtime.mm2

tmp_dir="$(mktemp -d)"
trap 'rm -rf "$tmp_dir"' EXIT

now_ns() {
  date +%s%N
}

run_prefix() {
  local label="$1"
  local line="$2"
  local prefix_file="$tmp_dir/$label.metta"
  local log="$tmp_dir/$label.log"
  local vlog="$tmp_dir/$label.verdicts.log"
  local start_ns end_ns duration_ms status count_log
  local pass close fail unsup_ir skipped

  sed -n "1,${line}p" "$fixture" > "$prefix_file"
  : > "$vlog"
  start_ns="$(now_ns)"
  set +e
  MM2_HARNESS_VERDICT_LOG="$vlog" timeout "$timeout_s" petta "$prefix_file" > "$log" 2>&1
  status=$?
  set -e
  end_ns="$(now_ns)"
  duration_ms=$(((end_ns - start_ns) / 1000000))

  count_log="$log"
  if [ "$status" -ne 0 ]; then
    count_log="$vlog"
  fi
  pass="$(grep -c 'mm2-test-pass' "$count_log" || true)"
  close="$(grep -c 'mm2-test-close' "$count_log" || true)"
  fail="$(grep -c 'mm2-test-FAIL' "$count_log" || true)"
  unsup_ir="$(grep -c 'notsupported-ir' "$count_log" || true)"
  skipped="$(grep -c 'mm2-test-unsupported' "$count_log" || true)"

  printf '%s\t%s\t%s\t%s\t%s\t%s\t%s\n' \
    "$duration_ms" "$pass" "$close" "$fail" "$unsup_ir" "$skipped" "$status"
}

mapfile -t selected_lines < <(grep -nE "$pattern" "$fixture" | cut -d: -f1)
if [ "${#selected_lines[@]}" -eq 0 ]; then
  echo "no fixture lines matched MM2_PROFILE_PATTERN=$pattern" >&2
  exit 2
fi

baseline_line="$(grep -nE '^!\(mm2-init\)' "$fixture" | head -1 | cut -d: -f1 || true)"
previous_ms=0
if [ -n "$baseline_line" ]; then
  baseline_row="$(run_prefix baseline "$baseline_line")"
  IFS=$'\t' read -r previous_ms _pass _close _fail _unsup_ir _skipped _status <<< "$baseline_row"
fi

printf 'line\tgross_ms\tdelta_ms\tpass\tclose\tfail\tunsupported_ir\tskipped\tstatus\ttext\n'
for line in "${selected_lines[@]}"; do
  row="$(run_prefix "line_$line" "$line")"
  IFS=$'\t' read -r gross_ms pass close fail unsup_ir skipped status <<< "$row"
  delta_ms=$((gross_ms - previous_ms))
  text="$(sed -n "${line}p" "$fixture")"
  text="${text//$'\t'/ }"
  printf '%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\n' \
    "$line" "$gross_ms" "$delta_ms" "$pass" "$close" "$fail" "$unsup_ir" "$skipped" "$status" "$text"
  previous_ms="$gross_ms"
done
