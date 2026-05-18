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

assert_semantic_outputs_equal() {
  local lhs="$1"
  local rhs="$2"
  local label="$3"
  local lhs_sem="outputs/${label}_lhs_semantic.mm2"
  local rhs_sem="outputs/${label}_rhs_semantic.mm2"
  grep -E '^\((fact|proved) ' "$lhs" | sort > "$lhs_sem"
  grep -E '^\((fact|proved) ' "$rhs" | sort > "$rhs_sem"
  if ! diff -u "$lhs_sem" "$rhs_sem" >/dev/null; then
    diff -u "$lhs_sem" "$rhs_sem" >&2 || true
    fail "$label semantic outputs differ"
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
    cat runtime/parts/00_frontier.mm2
    printf '\n'
    cat runtime/parts/10_premises.mm2
    printf '\n'
    cat runtime/parts/20_proofs.mm2
    printf '\n'
    cat runtime/parts/30_merge.mm2
    printf '\n'
    cat runtime/parts/90_loop.mm2
  } > "$target"
}

build_runtime_from_core_with_sink_head() {
  local target="$1"
  shift
  {
    printf '; generated test runtime with sink-head scheduler\n'
    for expr in "$@"; do
      printf '%s\n' "$expr"
    done
    printf '\n'
    cat runtime/parts/00_frontier.mm2
    cat <<'RUNTIME'

(exec-template
  (exec 2
        (, (pendingN $priority $g $rule-stv $premises))
        (O (head 32 (selectedN $priority $g $rule-stv $premises)))))

(exec-template
  (exec 3
        (, (selectedN $priority $g $rule-stv $premises))
        (O (- (pendingN $priority $g $rule-stv $premises))
           (- (selectedN $priority $g $rule-stv $premises))
           (+ (wait-premises
                $g
                $rule-stv
                $premises
                (1.0 1.0)
                (scheduledN $g $premises))))))
RUNTIME
    printf '\n'
    sed '1,15d' runtime/parts/10_premises.mm2
    printf '\n'
    cat runtime/parts/20_proofs.mm2
    printf '\n'
    cat runtime/parts/30_merge.mm2
    printf '\n'
    cat runtime/parts/90_loop.mm2
  } > "$target"
}

build_runtime_from_seed() {
  local target="$1"
  local seed="$2"
  bash scripts/build-runtime.sh "$target" "$seed"
}

runtime_template_count() {
  grep -h '^(exec-template' runtime/parts/*.mm2 | wc -l
}

run_reduced_test() {
  local runtime="outputs/test_reduced_runtime.mm2"
  local out="outputs/test_reduced.mm2"
  build_runtime_from_seed "$runtime" runtime/default_seed.mm2
  mork run rules/reduced_rules.mm2 --steps 220 --aux-path "$runtime" "$out" >/dev/null

  assert_contains "$out" "(fact (Animal x) (0.6867605633802818 0.584))"
  assert_contains "$out" "(fact (Mammal x) (0.9 0.6))"
  assert_contains "$out" "(fact (Pet x) (0.8 0.7))"

  local animal_proofs
  animal_proofs="$(grep -c '^(proved (Animal x) ' "$out")"
  assert_eq "$animal_proofs" "2" "reduced Animal proof count"

  local merged_proofs
  merged_proofs="$(grep -c '^(proof-merged ' "$out")"
  assert_eq "$merged_proofs" "4" "reduced merged proof count"

  local runtime_templates
  runtime_templates="$(runtime_template_count)"
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
  build_runtime_from_seed "$runtime" runtime/default_seed.mm2
  mork run rules/full_rules.mm2 --steps 30 --aux-path "$runtime" "$out" >/dev/null

  assert_contains "$out" "(wait-premise (Bat x) (1.0 1.0) (Racket x) pnil (1.0 1.0) (scheduledN (Bat x) (pcons (Racket x) pnil)))"
  assert_no_line_regex "$out" '^\(pendingN \$'

  local runtime_templates
  runtime_templates="$(runtime_template_count)"
  local out_templates
  out_templates="$(grep -c '^(exec-template' "$out")"
  assert_eq "$out_templates" "$runtime_templates" "full exec-template count"

  assert_no_line_regex "$out" '^\(proof-open '
  assert_no_line_regex "$out" '^\(selected-merge '
  assert_no_line_regex "$out" '^\(merge-input '
  assert_no_line_regex "$out" '^\(completed '
}

run_priority_test() {
  local runtime="outputs/test_confidence_priority_runtime.mm2"
  local rules="outputs/test_confidence_priority_rules.mm2"
  local out="outputs/test_confidence_priority.mm2"

  cat > "$rules" <<'EOF'
(ruleN (Animal $x) 0.9 0.9 (pcons (Mammal $x) pnil))
(ruleN (Animal $x) 0.7 0.7 (pcons (Pet $x) pnil))
(ruleN (Animal $x) 0.4 0.4 (pcons (Creature $x) pnil))
EOF

  for n in $(seq -w 1 33); do
    printf '(ruleN (Animal $x) 0.4 0.4 (pcons (LowPrem%s $x) pnil))\n' "$n" >> "$rules"
  done

  build_runtime_from_core "$runtime" \
    '(, (Goal (Animal x)))'

  mork run "$rules" --steps 30 --aux-path "$runtime" "$out" >/dev/null

  assert_contains "$out" "(wait-premise (Animal x) (0.4 0.4) (Creature x) pnil (1.0 1.0) (scheduledN (Animal x) (pcons (Creature x) pnil)))"
  assert_contains "$out" "(wait-premise (Animal x) (0.4 0.4) (LowPrem33 x) pnil (1.0 1.0) (scheduledN (Animal x) (pcons (LowPrem33 x) pnil)))"
  assert_contains "$out" "(wait-premise (Animal x) (0.9 0.9) (Mammal x) pnil (1.0 1.0) (scheduledN (Animal x) (pcons (Mammal x) pnil)))"
}

# Port of the single-premise composition behavior from
# PeTTaChainer/pettachainer/metta/tests/test_forward_backward_compose.metta.
run_reference_compose_test() {
  local runtime="outputs/test_reference_compose_runtime.mm2"
  local rules="outputs/test_reference_compose_rules.mm2"
  local out_short="outputs/test_reference_compose_short.mm2"
  local out_long="outputs/test_reference_compose_long.mm2"

  cat > "$rules" <<'EOF'
(ruleN (B) 1.0 1.0 (pcons (A) pnil))
(ruleN (Goal) 1.0 1.0 (pcons (B) pnil))
EOF

  build_runtime_from_core "$runtime" \
    '(, (Goal (Goal)))' \
    '(fact (A) (1.0 1.0))'

  mork run "$rules" --steps 40 --aux-path "$runtime" "$out_short" >/dev/null
  mork run "$rules" --steps 130 --aux-path "$runtime" "$out_long" >/dev/null

  assert_no_line_regex "$out_short" '^\(fact \(Goal\) '
  assert_contains "$out_long" "(fact (Goal) (1.0 1.0))"
  assert_contains "$out_long" "(proved (Goal) (1.0 1.0) (scheduledN (Goal) (pcons (B) pnil)))"
}

# Port of the first open-query result case from
# PeTTaChainer/pettachainer/metta/tests/test_backward_open_query_results.metta.
run_reference_open_query_test() {
  local runtime="outputs/test_reference_open_runtime.mm2"
  local rules="outputs/test_reference_open_rules.mm2"
  local out="outputs/test_reference_open.mm2"

  cat > "$rules" <<'EOF'
(ruleN (Animal $x) 1.0 0.9 (pcons (Dog $x) pnil))
EOF

  build_runtime_from_core "$runtime" \
    '(, (Goal (Animal $a)))' \
    '(fact (Dog max) (1.0 1.0))' \
    '(fact (Dog ann) (1.0 1.0))'

  mork run "$rules" --steps 45 --aux-path "$runtime" "$out" >/dev/null

  assert_contains "$out" "(fact (Animal ann) (1.0 0.9))"
  assert_contains "$out" "(fact (Animal max) (1.0 0.9))"
  assert_contains "$out" "(proved (Animal ann) (1.0 0.9) (scheduledN (Animal ann) (pcons (Dog ann) pnil)))"
  assert_contains "$out" "(proved (Animal max) (1.0 0.9) (scheduledN (Animal max) (pcons (Dog max) pnil)))"
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
(ruleN (A) 1.0 1.0 (pcons (X) pnil))
(ruleN (C) 1.0 1.0 (pcons (A) (pcons (B) pnil)))
EOF

  build_runtime_from_core "$runtime" \
    '(, (Goal (C)))' \
    '(fact (X) (1.0 1.0))' \
    '(fact (B) (1.0 1.0))'

  mork run "$rules" --steps 40 --aux-path "$runtime" "$out_short" >/dev/null
  mork run "$rules" --steps 150 --aux-path "$runtime" "$out_long" >/dev/null

  assert_no_line_regex "$out_short" '^\(fact \(C\) '
  assert_contains "$out_long" "(fact (C) (1.0 1.0))"
  assert_contains "$out_long" "(proved (C) (1.0 1.0) (scheduledN (C) (pcons (A) (pcons (B) pnil))))"
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
(ruleN (Own (i $x)) 0.8 1.0 (pcons (Have (i $x)) pnil))
(ruleN (Pet $x) 0.7 1.0 (pcons (Dog $x) pnil))
(ruleN (And (Own (i $x)) (Pet $x)) 1.0 1.0 (pcons (Own (i $x)) (pcons (Pet $x) pnil)))
EOF

  build_runtime_from_core "$runtime" \
    '(, (Goal (And (Own (i $a)) (Pet $a))))' \
    '(fact (Have (i ann)) (1.0 1.0))' \
    '(fact (Dog ann) (1.0 1.0))'

  mork run "$rules" --steps 70 --aux-path "$runtime" "$out_mid" >/dev/null
  mork run "$rules" --steps 260 --aux-path "$runtime" "$out_long" >/dev/null

  assert_contains "$out_mid" "(wait-premises (And (Own (i ann)) (Pet ann)) (1.0 1.0) (pcons (Pet ann) pnil) (0.8 1.0) (scheduledN (And (Own (i ann)) (Pet ann)) (pcons (Own (i ann)) (pcons (Pet ann) pnil))))"
  assert_contains "$out_long" "(fact (And (Own (i ann)) (Pet ann)) (0.7 1.0))"
  assert_contains "$out_long" "(proved (And (Own (i ann)) (Pet ann)) (0.7 1.0) (scheduledN (And (Own (i ann)) (Pet ann)) (pcons (Own (i ann)) (pcons (Pet ann) pnil))))"
}

run_reference_three_premise_test() {
  local runtime="outputs/test_reference_three_runtime.mm2"
  local rules="outputs/test_reference_three_rules.mm2"
  local out_short="outputs/test_reference_three_short.mm2"
  local out_long="outputs/test_reference_three_long.mm2"

  cat > "$rules" <<'EOF'
(ruleN (A) 1.0 1.0 (pcons (X) pnil))
(ruleN (Goal3) 1.0 1.0 (pcons (A) (pcons (B) (pcons (D) pnil))))
EOF

  build_runtime_from_core "$runtime" \
    '(, (Goal (Goal3)))' \
    '(fact (X) (1.0 1.0))' \
    '(fact (B) (1.0 1.0))' \
    '(fact (D) (1.0 1.0))'

  mork run "$rules" --steps 50 --aux-path "$runtime" "$out_short" >/dev/null
  mork run "$rules" --steps 190 --aux-path "$runtime" "$out_long" >/dev/null

  assert_no_line_regex "$out_short" '^\(fact \(Goal3\) '
  assert_contains "$out_long" "(fact (Goal3) (1.0 1.0))"
  assert_contains "$out_long" "(proved (Goal3) (1.0 1.0) (scheduledN (Goal3) (pcons (A) (pcons (B) (pcons (D) pnil)))))"
}

run_open_multiple_proofs_demo_test() {
  local runtime="outputs/test_open_multiple_proofs_runtime.mm2"
  local out="outputs/test_open_multiple_proofs.mm2"

  build_runtime_from_core "$runtime"
  mork run demos/open_multiple_proofs.mm2 --steps 130 --aux-path "$runtime" "$out" >/dev/null

  assert_contains "$out" "(fact (Animal ann) (0.9249999999999999 0.96))"
  assert_contains "$out" "(proved (Animal ann) (0.9 0.8) (scheduledN (Animal ann) (pcons (Dog ann) pnil)))"
  assert_contains "$out" "(proved (Animal ann) (0.95 0.8) (scheduledN (Animal ann) (pcons (Cat ann) pnil)))"

  local animal_ann_proofs
  animal_ann_proofs="$(grep -c '^(proved (Animal ann) ' "$out")"
  assert_eq "$animal_ann_proofs" "2" "open multiple proofs demo Animal ann proof count"
}

run_head_source_sink_equivalence_test() {
  local rules="outputs/test_head_equivalence_rules.mm2"
  local source_runtime="outputs/test_head_source_runtime.mm2"
  local sink_runtime="outputs/test_head_sink_runtime.mm2"
  local source_out="outputs/test_head_source.mm2"
  local sink_out="outputs/test_head_sink.mm2"

  cat > "$rules" <<'EOF'
(ruleN (Animal $x) 0.9 0.8 (pcons (Dog $x) pnil))
(ruleN (Animal $x) 0.95 0.8 (pcons (Cat $x) pnil))
(ruleN (Pet $x) 0.8 0.7 (pcons (Dog $x) pnil))
(ruleN (Combo $x) 0.7 0.9 (pcons (Animal $x) (pcons (Pet $x) pnil)))
EOF

  build_runtime_from_core "$source_runtime" \
    '(, (Goal (Combo ann)))' \
    '(fact (Dog ann) (1.0 1.0))' \
    '(fact (Cat ann) (1.0 1.0))'
  build_runtime_from_core_with_sink_head "$sink_runtime" \
    '(, (Goal (Combo ann)))' \
    '(fact (Dog ann) (1.0 1.0))' \
    '(fact (Cat ann) (1.0 1.0))'

  mork run "$rules" --steps 260 --aux-path "$source_runtime" "$source_out" >/dev/null
  mork run "$rules" --steps 260 --aux-path "$sink_runtime" "$sink_out" >/dev/null

  assert_semantic_outputs_equal "$source_out" "$sink_out" "head_source_sink"
  assert_contains "$source_out" "(fact (Combo ann) (0.5599999999999999 0.63))"
}

run_reduced_test
run_full_test
run_priority_test
run_reference_compose_test
run_reference_open_query_test
run_reference_independent_test
run_reference_binding_test
run_reference_three_premise_test
run_open_multiple_proofs_demo_test
run_head_source_sink_equivalence_test

echo "PASS: runtime regression suite"
