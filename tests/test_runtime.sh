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

build_runtime_from_core() {
  local target="$1"
  shift
  {
    printf '; generated test runtime\n'
    for expr in "$@"; do
      printf '%s\n' "$expr"
    done
    printf '\n'
    cat runtime/core_runtime.mm2
  } > "$target"
}

build_runtime_from_seed() {
  local target="$1"
  local seed="$2"
  {
    printf '; generated test runtime\n'
    cat "$seed"
    printf '\n'
    cat runtime/core_runtime.mm2
  } > "$target"
}

run_reduced_test() {
  local runtime="outputs/test_reduced_runtime.mm2"
  local out="outputs/test_reduced.mm2"
  build_runtime_from_seed "$runtime" runtime/reduced_seed.mm2
  mork run rules/reduced_rules.mm2 --steps 140 --aux-path "$runtime" "$out" >/dev/null

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
  runtime_templates="$(grep -c '^(exec-template' runtime/core_runtime.mm2)"
  local out_templates
  out_templates="$(grep -c '^(exec-template' "$out")"
  assert_eq "$out_templates" "$runtime_templates" "reduced exec-template count"

  assert_no_line_regex "$out" '^\(proof-open '
  assert_no_line_regex "$out" '^\(selected-merge '
  assert_no_line_regex "$out" '^\(merge-input '
  assert_no_line_regex "$out" '^\(completed '
}

run_full_test() {
  local runtime="outputs/test_full_runtime.mm2"
  local out="outputs/test_full.mm2"
  build_runtime_from_seed "$runtime" runtime/full_seed.mm2
  mork run rules/full_rules.mm2 --steps 1000 --aux-path "$runtime" "$out" >/dev/null

  assert_contains "$out" "(fact (Animal x) 1.0 1.0)"
  assert_contains "$out" "(fact (Pet x) 1.0 1.0)"

  local animal_proofs
  animal_proofs="$(grep -c '^(proved (Animal x) ' "$out")"
  assert_ge "$animal_proofs" "2" "full Animal proof count"

  local runtime_templates
  runtime_templates="$(grep -c '^(exec-template' runtime/core_runtime.mm2)"
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

# Port of the single-premise composition behavior from
# PeTTaChainer/pettachainer/metta/tests/test_forward_backward_compose.metta.
run_reference_compose_test() {
  local runtime="outputs/test_reference_compose_runtime.mm2"
  local rules="outputs/test_reference_compose_rules.mm2"
  local out_short="outputs/test_reference_compose_short.mm2"
  local out_long="outputs/test_reference_compose_long.mm2"

  cat > "$rules" <<'EOF'
(rule (B)
      0000100
      1.0
      1.0
      (A)
      (, (Goal (A))))

(rule (Goal)
      0000100
      1.0
      1.0
      (B)
      (, (Goal (B))))
EOF

  build_runtime_from_core "$runtime" \
    '(, (Goal (Goal)))' \
    '(fact (A) 1.0 1.0)'

  mork run "$rules" --steps 40 --aux-path "$runtime" "$out_short" >/dev/null
  mork run "$rules" --steps 75 --aux-path "$runtime" "$out_long" >/dev/null

  assert_no_line_regex "$out_short" '^\(fact \(Goal\) '
  assert_contains "$out_long" "(fact (Goal) 1.0 1.0)"
  assert_contains "$out_long" "(proved (Goal) 1.0 1.0 (scheduledN 0000100 (Goal) (pcons (B) pnil)))"
}

# Port of the first open-query result case from
# PeTTaChainer/pettachainer/metta/tests/test_backward_open_query_results.metta.
run_reference_open_query_test() {
  local runtime="outputs/test_reference_open_runtime.mm2"
  local rules="outputs/test_reference_open_rules.mm2"
  local out="outputs/test_reference_open.mm2"

  cat > "$rules" <<'EOF'
(rule (Animal $x)
      0000100
      1.0
      0.9
      (Dog $x)
      (, (Goal (Dog $x))))
EOF

  build_runtime_from_core "$runtime" \
    '(, (Goal (Animal $a)))' \
    '(fact (Dog max) 1.0 1.0)' \
    '(fact (Dog ann) 1.0 1.0)'

  mork run "$rules" --steps 45 --aux-path "$runtime" "$out" >/dev/null

  assert_contains "$out" "(fact (Animal ann) 1.0 0.9)"
  assert_contains "$out" "(fact (Animal max) 1.0 0.9)"
  assert_contains "$out" "(proved (Animal ann) 1.0 0.9 (scheduledN 0000100 (Animal ann) (pcons (Dog ann) pnil)))"
  assert_contains "$out" "(proved (Animal max) 1.0 0.9 (scheduledN 0000100 (Animal max) (pcons (Dog max) pnil)))"
}

# Port of the independentKb behavior from
# PeTTaChainer/pettachainer/metta/tests/test_forward_backward_compose.metta,
# now via the generic ruleN frontend.
run_reference_independent_test() {
  local runtime="outputs/test_reference_independent_runtime.mm2"
  local rules="outputs/test_reference_independent_rules.mm2"
  local out_short="outputs/test_reference_independent_short.mm2"
  local out_long="outputs/test_reference_independent_long.mm2"

  cat > "$rules" <<'EOF'
(rule (A)
      0000100
      1.0
      1.0
      (X)
      (, (Goal (X))))

(ruleN (C)
       0000100
       1.0
       1.0
       (pcons (A) (pcons (B) pnil)))
EOF

  build_runtime_from_core "$runtime" \
    '(, (Goal (C)))' \
    '(fact (X) 1.0 1.0)' \
    '(fact (B) 1.0 1.0)'

  mork run "$rules" --steps 40 --aux-path "$runtime" "$out_short" >/dev/null
  mork run "$rules" --steps 110 --aux-path "$runtime" "$out_long" >/dev/null

  assert_no_line_regex "$out_short" '^\(fact \(C\) '
  assert_contains "$out_long" "(fact (C) 1.0 1.0)"
  assert_contains "$out_long" "(proved (C) 1.0 1.0 (scheduledN 0000100 (C) (pcons (A) (pcons (B) pnil))))"
}

# Simplified dependent-binding parity case modeled on the openAndFair behavior in
# PeTTaChainer/pettachainer/metta/tests/test_backward_open_query_results.metta,
# now via the generic ruleN frontend.
run_reference_binding_test() {
  local runtime="outputs/test_reference_binding_runtime.mm2"
  local rules="outputs/test_reference_binding_rules.mm2"
  local out_mid="outputs/test_reference_binding_mid.mm2"
  local out_long="outputs/test_reference_binding_long.mm2"

  cat > "$rules" <<'EOF'
(rule (Own (i $x))
      0000100
      0.8
      1.0
      (Have (i $x))
      (, (Goal (Have (i $x)))))

(rule (Pet $x)
      0000100
      0.7
      1.0
      (Dog $x)
      (, (Goal (Dog $x))))

(ruleN (And (Own (i $x)) (Pet $x))
       0000100
       1.0
       1.0
       (pcons (Own (i $x)) (pcons (Pet $x) pnil)))
EOF

  build_runtime_from_core "$runtime" \
    '(, (Goal (And (Own (i $a)) (Pet $a))))' \
    '(fact (Have (i ann)) 1.0 1.0)' \
    '(fact (Dog ann) 1.0 1.0)'

  mork run "$rules" --steps 70 --aux-path "$runtime" "$out_mid" >/dev/null
  mork run "$rules" --steps 220 --aux-path "$runtime" "$out_long" >/dev/null

  assert_contains "$out_mid" "(wait-premises (And (Own (i ann)) (Pet ann)) 1.0 1.0 (Pet ann) pnil 0.8 1.0 (scheduledN 0000100 (And (Own (i ann)) (Pet ann)) (pcons (Own (i ann)) (pcons (Pet ann) pnil))))"
  assert_contains "$out_long" "(fact (And (Own (i ann)) (Pet ann)) 0.7 1.0)"
  assert_contains "$out_long" "(proved (And (Own (i ann)) (Pet ann)) 0.7 1.0 (scheduledN 0000100 (And (Own (i ann)) (Pet ann)) (pcons (Own (i ann)) (pcons (Pet ann) pnil))))"
}

run_reference_three_premise_test() {
  local runtime="outputs/test_reference_three_runtime.mm2"
  local rules="outputs/test_reference_three_rules.mm2"
  local out_short="outputs/test_reference_three_short.mm2"
  local out_long="outputs/test_reference_three_long.mm2"

  cat > "$rules" <<'EOF'
(rule (A)
      0000100
      1.0
      1.0
      (X)
      (, (Goal (X))))

(ruleN (Goal3)
       0000100
       1.0
       1.0
       (pcons (A) (pcons (B) (pcons (D) pnil))))
EOF

  build_runtime_from_core "$runtime" \
    '(, (Goal (Goal3)))' \
    '(fact (X) 1.0 1.0)' \
    '(fact (B) 1.0 1.0)' \
    '(fact (D) 1.0 1.0)'

  mork run "$rules" --steps 60 --aux-path "$runtime" "$out_short" >/dev/null
  mork run "$rules" --steps 140 --aux-path "$runtime" "$out_long" >/dev/null

  assert_no_line_regex "$out_short" '^\(fact \(Goal3\) '
  assert_contains "$out_long" "(fact (Goal3) 1.0 1.0)"
  assert_contains "$out_long" "(proved (Goal3) 1.0 1.0 (scheduledN 0000100 (Goal3) (pcons (A) (pcons (B) (pcons (D) pnil)))))"
}

run_reduced_test
run_full_test
run_priority_test
run_reference_compose_test
run_reference_open_query_test
run_reference_independent_test
run_reference_binding_test
run_reference_three_premise_test

echo "PASS: runtime regression suite"
