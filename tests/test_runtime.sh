#!/usr/bin/env bash

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

fail() {
  echo "FAIL: $*" >&2
  exit 1
}

assert_contains() {
  local file="$1"
  local needle="$2"
  if ! grep -Fqx "$needle" "$file"; then
    fail "expected line in $file: $needle"
  fi
}

assert_not_contains() {
  local file="$1"
  local needle="$2"
  if grep -Fq "$needle" "$file"; then
    fail "unexpected content in $file: $needle"
  fi
}

assert_no_line_regex() {
  local file="$1"
  local pattern="$2"
  if grep -Eq "$pattern" "$file"; then
    fail "unexpected matching line in $file: $pattern"
  fi
}

assert_eq() {
  local got="$1"
  local want="$2"
  local label="$3"
  if [[ "$got" != "$want" ]]; then
    fail "$label: expected $want, got $got"
  fi
}

assert_ge() {
  local got="$1"
  local want="$2"
  local label="$3"
  if (( got < want )); then
    fail "$label: expected >= $want, got $got"
  fi
}

run_reduced_test() {
  local out="outputs/test_reduced.mm2"
  mork run rules/reduced_rules.mm2 --steps 140 --aux-path runtime/reduced_runtime.mm2 "$out" >/dev/null

  assert_contains "$out" "(fact (Animal x) 0.6867605633802818 0.584)"
  assert_contains "$out" "(fact (Mammal x) 0.9 0.6)"
  assert_contains "$out" "(fact (Pet x) 0.8 0.7)"

  local animal_proofs
  animal_proofs="$(grep -c '^(proved (Animal x) ' "$out")"
  assert_eq "$animal_proofs" "2" "reduced Animal proof count"

  local merged_proofs
  merged_proofs="$(grep -c '^(proof-merged ' "$out")"
  assert_eq "$merged_proofs" "4" "reduced merged proof count"

  local runtime_templates
  runtime_templates="$(grep -c '^(exec-template' runtime/reduced_runtime.mm2)"
  local out_templates
  out_templates="$(grep -c '^(exec-template' "$out")"
  assert_eq "$out_templates" "$runtime_templates" "reduced exec-template count"

  assert_no_line_regex "$out" '^\(proof-open '
  assert_no_line_regex "$out" '^\(selected-merge '
  assert_no_line_regex "$out" '^\(merge-input '
  assert_no_line_regex "$out" '^\(completed '
}

run_full_test() {
  local out="outputs/test_full.mm2"
  mork run rules/full_rules.mm2 --steps 1000 --aux-path runtime/full_runtime.mm2 "$out" >/dev/null

  assert_contains "$out" "(fact (Animal x) 1.0 1.0)"
  assert_contains "$out" "(fact (Pet x) 1.0 1.0)"

  local animal_proofs
  animal_proofs="$(grep -c '^(proved (Animal x) ' "$out")"
  assert_ge "$animal_proofs" "2" "full Animal proof count"

  local runtime_templates
  runtime_templates="$(grep -c '^(exec-template' runtime/full_runtime.mm2)"
  local out_templates
  out_templates="$(grep -c '^(exec-template' "$out")"
  assert_eq "$out_templates" "$runtime_templates" "full exec-template count"

  assert_no_line_regex "$out" '^\(proof-open '
  assert_no_line_regex "$out" '^\(selected-merge '
  assert_no_line_regex "$out" '^\(merge-input '
  assert_no_line_regex "$out" '^\(completed '
}

run_priority_test() {
  local out="outputs/test_priority.mm2"
  mork run demos/priority_scheduler_demo.mm2 --steps 1 "$out" >/dev/null

  assert_contains "$out" "(selected 0000100 rule-mammal)"
  assert_contains "$out" "(selected 0000200 rule-pet)"
}

run_reduced_test
run_full_test
run_priority_test

echo "PASS: runtime regression suite"
