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
    for part in runtime/parts/*.mm2; do
      cat "$part"
      printf '\n'
    done
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
    printf '\n'
    cat runtime/parts/05_baserate.mm2
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
                no-stv
                (scheduledN $g $rule-stv $premises)
                pnil)))))
RUNTIME
    printf '\n'
    cat runtime/parts/10_premises.mm2
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

# Every seeded exec costs one step whether or not it fires, and the Z loop
# re-seeds all templates each round — so one round costs one step per
# template. Budgets are expressed as (rounds, extra-steps) and scale with the
# template count so adding runtime execs does not silently shift what stage
# of the derivation each snapshot test observes.
steps_budget() {
  echo $(( $1 * $(runtime_template_count) + $2 ))
}

run_reduced_test() {
  local runtime="outputs/test_reduced_runtime.mm2"
  local out="outputs/test_reduced.mm2"
  build_runtime_from_seed "$runtime" runtime/default_seed.mm2
  mork run rules/reduced_rules.mm2 --steps "$(steps_budget 15 5)" --aux-path "$runtime" "$out" >/dev/null

  assert_contains "$out" "(fact (Animal x) (0.6897720572471554 0.7530993828561005))"
  assert_contains "$out" "(fact (Mammal x) (0.9 0.5999999996754302))"
  assert_contains "$out" "(fact (Pet x) (0.8 0.6999999998037638))"

  local animal_proofs
  animal_proofs="$(grep -c '^(proved (Animal x) ' "$out")"
  assert_eq "$animal_proofs" "2" "reduced Animal proof count"

  local proof_records
  proof_records="$(grep -c '^(proved ' "$out")"
  assert_eq "$proof_records" "4" "reduced proof record count"

  local runtime_templates
  runtime_templates="$(runtime_template_count)"
  local out_templates
  out_templates="$(grep -c '^(exec-template' "$out")"
  assert_eq "$out_templates" "$runtime_templates" "reduced exec-template count"

  assert_no_line_regex "$out" '^\(open-proof '
  assert_no_line_regex "$out" '^\(selected-merge '
  assert_no_line_regex "$out" '^\(merge-input '
  assert_no_line_regex "$out" '^\(completed '
}

run_full_test() {
  local runtime="outputs/test_full_runtime.mm2"
  local out="outputs/test_full.mm2"
  build_runtime_from_seed "$runtime" runtime/default_seed.mm2
  mork run rules/full_rules.mm2 --steps "$(steps_budget 3 0)" --aux-path "$runtime" "$out" >/dev/null

  assert_contains "$out" "(wait-premise (Bat x) (ctv (1.0 1.0) (0.0 1.0)) (Paddle x) pnil no-stv (scheduledN (Bat x) (ctv (1.0 1.0) (0.0 1.0)) (pcons (Paddle x) pnil)) pnil)"
  assert_no_line_regex "$out" '^\(pendingN \$'

  local runtime_templates
  runtime_templates="$(runtime_template_count)"
  local out_templates
  out_templates="$(grep -c '^(exec-template' "$out")"
  assert_eq "$out_templates" "$runtime_templates" "full exec-template count"

  assert_no_line_regex "$out" '^\(open-proof '
  assert_no_line_regex "$out" '^\(selected-merge '
  assert_no_line_regex "$out" '^\(merge-input '
  assert_no_line_regex "$out" '^\(completed '
}

run_priority_test() {
  local runtime="outputs/test_confidence_priority_runtime.mm2"
  local rules="outputs/test_confidence_priority_rules.mm2"
  local out="outputs/test_confidence_priority.mm2"

  cat > "$rules" <<'EOF'
(ruleN (Animal $x) (ctv (0.9 0.9) (0.0 1.0)) (pcons (Mammal $x) pnil))
(ruleN (Animal $x) (ctv (0.7 0.7) (0.0 1.0)) (pcons (Pet $x) pnil))
(ruleN (Animal $x) (ctv (0.4 0.4) (0.0 1.0)) (pcons (Creature $x) pnil))
EOF

  for n in $(seq -w 1 33); do
    printf '(ruleN (Animal $x) (ctv (0.4 0.4) (0.0 1.0)) (pcons (LowPrem%s $x) pnil))\n' "$n" >> "$rules"
  done

  build_runtime_from_core "$runtime" \
    '(, (Goal (Animal x)))'

  mork run "$rules" --steps "$(steps_budget 2 1)" --aux-path "$runtime" "$out" >/dev/null

  assert_contains "$out" "(wait-premise (Animal x) (ctv (0.4 0.4) (0.0 1.0)) (Creature x) pnil no-stv (scheduledN (Animal x) (ctv (0.4 0.4) (0.0 1.0)) (pcons (Creature x) pnil)) pnil)"
  assert_contains "$out" "(wait-premise (Animal x) (ctv (0.4 0.4) (0.0 1.0)) (LowPrem33 x) pnil no-stv (scheduledN (Animal x) (ctv (0.4 0.4) (0.0 1.0)) (pcons (LowPrem33 x) pnil)) pnil)"
  assert_contains "$out" "(wait-premise (Animal x) (ctv (0.9 0.9) (0.0 1.0)) (Mammal x) pnil no-stv (scheduledN (Animal x) (ctv (0.9 0.9) (0.0 1.0)) (pcons (Mammal x) pnil)) pnil)"
}

# Port of the single-premise composition behavior from
# PeTTaChainer/pettachainer/metta/tests/test_forward_backward_compose.metta.
run_reference_compose_test() {
  local runtime="outputs/test_reference_compose_runtime.mm2"
  local rules="outputs/test_reference_compose_rules.mm2"
  local out_short="outputs/test_reference_compose_short.mm2"
  local out_long="outputs/test_reference_compose_long.mm2"

  cat > "$rules" <<'EOF'
(ruleN (B) (ctv (1.0 1.0) (0.0 1.0)) (pcons (A) pnil))
(ruleN (Goal) (ctv (1.0 1.0) (0.0 1.0)) (pcons (B) pnil))
EOF

  build_runtime_from_core "$runtime" \
    '(, (Goal (Goal)))' \
    '(fact (A) (1.0 1.0))'

  mork run "$rules" --steps "$(steps_budget 2 6)" --aux-path "$runtime" "$out_short" >/dev/null
  mork run "$rules" --steps "$(steps_budget 8 14)" --aux-path "$runtime" "$out_long" >/dev/null

  assert_no_line_regex "$out_short" '^\(fact \(Goal\) '
  assert_contains "$out_long" "(fact (Goal) (1.0 0.999700089898053))"
  assert_contains "$out_long" "(proved (Goal) (1.0 0.999700089898053) (scheduledN (Goal) (ctv (1.0 1.0) (0.0 1.0)) (pcons (B) pnil)) (pcons (fact-ev (B)) pnil))"
}

# Port of the first open-query result case from
# PeTTaChainer/pettachainer/metta/tests/test_backward_open_query_results.metta.
run_reference_open_query_test() {
  local runtime="outputs/test_reference_open_runtime.mm2"
  local rules="outputs/test_reference_open_rules.mm2"
  local out="outputs/test_reference_open.mm2"

  cat > "$rules" <<'EOF'
(ruleN (Animal $x) (ctv (1.0 0.9) (0.0 1.0)) (pcons (Dog $x) pnil))
EOF

  build_runtime_from_core "$runtime" \
    '(, (Goal (Animal $a)))' \
    '(fact (Dog max) (1.0 1.0))' \
    '(fact (Dog ann) (1.0 1.0))'

  mork run "$rules" --steps "$(steps_budget 3 4)" --aux-path "$runtime" "$out" >/dev/null

  assert_contains "$out" "(fact (Animal ann) (1.0 0.8999189847918191))"
  assert_contains "$out" "(fact (Animal max) (1.0 0.8999189847918191))"
  assert_contains "$out" "(proved (Animal ann) (1.0 0.8999189847918191) (scheduledN (Animal ann) (ctv (1.0 0.9) (0.0 1.0)) (pcons (Dog ann) pnil)) (pcons (fact-ev (Dog ann)) pnil))"
  assert_contains "$out" "(proved (Animal max) (1.0 0.8999189847918191) (scheduledN (Animal max) (ctv (1.0 0.9) (0.0 1.0)) (pcons (Dog max) pnil)) (pcons (fact-ev (Dog max)) pnil))"
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
(ruleN (A) (ctv (1.0 1.0) (0.0 1.0)) (pcons (X) pnil))
(ruleN (C) (ctv (1.0 1.0) (0.0 1.0)) (pcons (A) (pcons (B) pnil)))
EOF

  build_runtime_from_core "$runtime" \
    '(, (Goal (C)))' \
    '(fact (X) (1.0 1.0))' \
    '(fact (B) (1.0 1.0))'

  mork run "$rules" --steps "$(steps_budget 2 6)" --aux-path "$runtime" "$out_short" >/dev/null
  mork run "$rules" --steps "$(steps_budget 10 0)" --aux-path "$runtime" "$out_long" >/dev/null

  assert_no_line_regex "$out_short" '^\(fact \(C\) '
  assert_contains "$out_long" "(fact (C) (1.0 0.9996001597861454))"
  assert_contains "$out_long" "(proved (C) (1.0 0.9996001597861454) (scheduledN (C) (ctv (1.0 1.0) (0.0 1.0)) (pcons (A) (pcons (B) pnil))) (pcons (fact-ev (B)) (pcons (fact-ev (A)) pnil)))"
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
(ruleN (Own (i $x)) (ctv (0.8 1.0) (0.0 1.0)) (pcons (Have (i $x)) pnil))
(ruleN (Pet $x) (ctv (0.7 1.0) (0.0 1.0)) (pcons (Dog $x) pnil))
(adapterN (And (Own (i $x)) (Pet $x)) (pcons (Own (i $x)) (pcons (Pet $x) pnil)))
EOF

  build_runtime_from_core "$runtime" \
    '(, (Goal (And (Own (i $a)) (Pet $a))))' \
    '(fact (Have (i ann)) (1.0 1.0))' \
    '(fact (Dog ann) (1.0 1.0))'

  mork run "$rules" --steps "$(steps_budget 5 0)" --aux-path "$runtime" "$out_mid" >/dev/null
  mork run "$rules" --steps "$(steps_budget 17 11)" --aux-path "$runtime" "$out_long" >/dev/null

  assert_contains "$out_mid" "(wait-premise-pool (And (Own (i ann)) (Pet ann)) (Pet ann) pnil (and-pool (0.8 0.9999000095990804) (pcons (fact-ev (Have (i ann))) pnil) (pcons (indep-part (0.8 0.9999000095990804)) pnil)) (adapterN (And (Own (i ann)) (Pet ann)) (pcons (Own (i ann)) (pcons (Pet ann) pnil))))"
  assert_contains "$out_long" "(fact (And (Own (i ann)) (Pet ann)) (0.5599999999999999 0.9999136351865401))"
  assert_contains "$out_long" "(proved (And (Own (i ann)) (Pet ann)) (0.5599999999999999 0.9999136351865401) (adapterN (And (Own (i ann)) (Pet ann)) (pcons (Own (i ann)) (pcons (Pet ann) pnil))) (pcons (fact-ev (Have (i ann))) (pcons (fact-ev (Dog ann)) pnil)))"
}

run_reference_three_premise_test() {
  local runtime="outputs/test_reference_three_runtime.mm2"
  local rules="outputs/test_reference_three_rules.mm2"
  local out_short="outputs/test_reference_three_short.mm2"
  local out_long="outputs/test_reference_three_long.mm2"

  cat > "$rules" <<'EOF'
(ruleN (A) (ctv (1.0 1.0) (0.0 1.0)) (pcons (X) pnil))
(ruleN (Goal3) (ctv (1.0 1.0) (0.0 1.0)) (pcons (A) (pcons (B) (pcons (D) pnil))))
EOF

  build_runtime_from_core "$runtime" \
    '(, (Goal (Goal3)))' \
    '(fact (X) (1.0 1.0))' \
    '(fact (B) (1.0 1.0))' \
    '(fact (D) (1.0 1.0))'

  mork run "$rules" --steps "$(steps_budget 2 16)" --aux-path "$runtime" "$out_short" >/dev/null
  mork run "$rules" --steps "$(steps_budget 12 16)" --aux-path "$runtime" "$out_long" >/dev/null

  assert_no_line_regex "$out_short" '^\(fact \(Goal3\) '
  assert_contains "$out_long" "(fact (Goal3) (1.0 0.9995002496253119))"
  assert_contains "$out_long" "(proved (Goal3) (1.0 0.9995002496253119) (scheduledN (Goal3) (ctv (1.0 1.0) (0.0 1.0)) (pcons (A) (pcons (B) (pcons (D) pnil)))) (pcons (fact-ev (D)) (pcons (fact-ev (B)) (pcons (fact-ev (A)) pnil))))"
}

run_reference_nary_conjunction_test() {
  local compiler_src="outputs/test_reference_nary_conjunction_source.metta"
  local compiler_out="outputs/test_reference_nary_conjunction_compiled.mm2"
  local runtime="outputs/test_reference_nary_conjunction_runtime.mm2"
  local rules="outputs/test_reference_nary_conjunction_rules.mm2"
  local out="outputs/test_reference_nary_conjunction.mm2"

  cat > "$compiler_src" <<EOF
!(import! &self $ROOT_DIR/compiler/petta_mm2_backend)
!(mm2-compile-add (: a A (STV 1.0 1.0)))
!(mm2-compile-add (: b B (STV 1.0 1.0)))
!(mm2-compile-add (: c C (STV 1.0 1.0)))
!(mm2-compile-query-goal (: \$prf (And A B C) \$tv))
!(mm2-compile-query-rule (: \$prf (And A B C) \$tv))
EOF

  petta "$compiler_src" > "$compiler_out"

  grep -E '^\(adapterN ' "$compiler_out" > "$rules"

  local seed_exprs=()
  mapfile -t seed_exprs < <(grep -E '^\((fact |fact-evidence |proved |, \(Goal )' "$compiler_out")
  build_runtime_from_core "$runtime" "${seed_exprs[@]}"

  mork run "$rules" --steps "$(steps_budget 4 12)" --aux-path "$runtime" "$out" >/dev/null

  assert_contains "$compiler_out" "(fact A (1.0 1.0))"
  assert_contains "$compiler_out" "(fact B (1.0 1.0))"
  assert_contains "$compiler_out" "(fact C (1.0 1.0))"
  assert_contains "$compiler_out" "(, (Goal (And A B C)))"
  assert_contains "$compiler_out" "(adapterN (And A B C) (pcons A (pcons B (pcons C pnil))))"
  assert_contains "$out" "(fact (And A B C) (1.0 0.999700089898053))"
}

# Port of PeTTaChainer/pettachainer/metta/tests/test_stv_implication_derived_ctv.metta.
# A plain STV implication derives its negative branch from the base rates of
# its antecedent/consequent patterns before modus ponens is applied.
run_reference_stv_implication_test() {
  local compiler_src="outputs/test_reference_stv_implication_source.metta"
  local compiler_out="outputs/test_reference_stv_implication_compiled.mm2"
  local runtime="outputs/test_reference_stv_implication_runtime.mm2"
  local rules="outputs/test_reference_stv_implication_rules.mm2"
  local out="outputs/test_reference_stv_implication.mm2"

  cat > "$compiler_src" <<EOF
!(import! &self $ROOT_DIR/compiler/petta_mm2_backend)
!(mm2-compile-add (: a (A x) (STV 1.0 0.9)))
!(mm2-compile-add (: aToB (Implication (Premises (A \$x)) (Conclusions (B \$x))) (STV 0.6 0.9)))
!(mm2-compile-query-goal (: \$prf (B x) \$tv))
EOF

  petta "$compiler_src" > "$compiler_out"

  grep -E '^\((ruleN|adapterN|base-rate|base-rate-def) ' "$compiler_out" > "$rules"

  local seed_exprs=()
  mapfile -t seed_exprs < <(grep -E '^\((fact |fact-evidence |proved |, \(Goal )' "$compiler_out")
  build_runtime_from_core "$runtime" "${seed_exprs[@]}"

  mork run "$rules" --steps "$(steps_budget 7 1)" --aux-path "$runtime" "$out" >/dev/null

  assert_contains "$compiler_out" "(fact (A x) (1.0 0.9))"
  assert_contains "$compiler_out" "(, (Goal (B x)))"
  assert_contains "$out" '(base-rate (A $a) (1 0.0011237357972281184))'
  assert_contains "$out" '(base-rate (B $a) (0.6 0.0011237356288179173))'
  assert_contains "$out" "(fact (B x) (0.6 0.8999998649685302))"
}

# Port of PeTTaChainer/pettachainer/metta/tests/test_implication_inversion.metta.
# The inverse of P->Q proves (P alice) from the (Q alice) witness. The
# inverted CTV depends on the base rates of P and Q at fire time; the Q base
# rate must include the derived (Q bob) (PeTTa's base-rate folds are chaining
# queries, mirrored here by the compiler's materialization goal), and until it
# does the inversion is rejected as inconsistent and retried.
run_reference_implication_inversion_test() {
  local compiler_src="outputs/test_reference_inversion_source.metta"
  local compiler_out="outputs/test_reference_inversion_compiled.mm2"
  local runtime="outputs/test_reference_inversion_runtime.mm2"
  local rules="outputs/test_reference_inversion_rules.mm2"
  local out="outputs/test_reference_inversion.mm2"

  cat > "$compiler_src" <<EOF
!(import! &self $ROOT_DIR/compiler/petta_mm2_backend)
!(mm2-compile-add (: r (Implication (Premises (P \$x)) (Conclusions (Q \$x))) (CTV (STV 0.8 0.9) (STV 0.1 0.9))))
!(mm2-compile-add (: qa (Q alice) (STV 0.9 0.8)))
!(mm2-compile-add (: pb (P bob) (STV 0.7 0.8)))
!(mm2-compile-query-goal (: \$prf (P alice) \$tv))
EOF

  petta "$compiler_src" > "$compiler_out"

  grep -E '^\((ruleN|adapterN|base-rate|base-rate-def) ' "$compiler_out" > "$rules"

  local seed_exprs=()
  mapfile -t seed_exprs < <(grep -E '^\((fact |fact-evidence |proved |, \(Goal )' "$compiler_out")
  build_runtime_from_core "$runtime" "${seed_exprs[@]}"

  mork run "$rules" --steps "$(steps_budget 23 9)" --aux-path "$runtime" "$out" >/dev/null

  assert_contains "$out" "(proved (Q bob) (0.59 0.8725449130531222) (scheduledN (Q bob) (ctv (0.8 0.9) (0.1 0.9)) (pcons (P bob) pnil)) (pcons (fact-ev (P bob)) pnil))"
  assert_contains "$out" "(proved (P alice) (0.736162240263287 0.0003604307138536469) (scheduledInvN (P alice) (0.8 0.9) (pcons (Q alice) pnil)) (pcons (fact-ev (Q alice)) pnil))"
}

# Two rules proving the same goal from the same premises must produce two
# distinct proofs (the proof token includes the rule TV). Shaped after
# PeTTaChainer's test_lifting_merge diffImplKb; exact pooled-value parity is
# tracked separately (proof-store pooling), so only proof multiplicity and
# the current overlap-dominance merge are pinned here.
run_same_premise_rules_test() {
  local runtime="outputs/test_same_premise_runtime.mm2"
  local rules="outputs/test_same_premise_rules.mm2"
  local out="outputs/test_same_premise.mm2"

  cat > "$rules" <<'EOF'
(ruleN (B $x) (ctv (0.7 0.9) (0.0 1.0)) (pcons (A $x) pnil))
(ruleN (B $x) (ctv (0.6 0.9) (0.0 1.0)) (pcons (A $x) pnil))
EOF

  build_runtime_from_core "$runtime" \
    '(, (Goal (B i)))' \
    '(fact (A i) (1.0 1.0))'

  mork run "$rules" --steps "$(steps_budget 7 1)" --aux-path "$runtime" "$out" >/dev/null

  assert_contains "$out" "(proved (B i) (0.7 0.8999999998109365) (scheduledN (B i) (ctv (0.7 0.9) (0.0 1.0)) (pcons (A i) pnil)) (pcons (fact-ev (A i)) pnil))"
  assert_contains "$out" "(proved (B i) (0.6 0.8999999998784551) (scheduledN (B i) (ctv (0.6 0.9) (0.0 1.0)) (pcons (A i) pnil)) (pcons (fact-ev (A i)) pnil))"
  assert_contains "$out" "(fact (B i) (0.6499999999812448 0.9473684207998814))"

  local proofs
  proofs="$(grep -c '^(proved (B i) ' "$out")"
  assert_eq "$proofs" "2" "same-premise distinct proof count"
}

# PeTTaChainer-style tests running in-process against the mm2 runtime via
# petta + mork_ffi (compiler/mm2_chainer.metta). The `close` verdict is the
# inversion refinement drift documented in PLAN.md.
run_ffi_harness_test() {
  local summary
  summary="$(bash scripts/run-harness-tests.sh | tail -1)"
  assert_eq "$summary" "HARNESS: 12 pass, 0 close, 0 fail" "ffi harness verdict counts"
}

run_open_multiple_proofs_demo_test() {
  local runtime="outputs/test_open_multiple_proofs_runtime.mm2"
  local out="outputs/test_open_multiple_proofs.mm2"

  build_runtime_from_core "$runtime"
  mork run demos/open_multiple_proofs.mm2 --steps "$(steps_budget 8 14)" --aux-path "$runtime" "$out" >/dev/null

  assert_contains "$out" "(fact (Animal ann) (0.9249999999499686 0.888888888335445))"
  assert_contains "$out" "(proved (Animal ann) (0.9 0.7999999994236207) (scheduledN (Animal ann) (ctv (0.9 0.8) (0.0 1.0)) (pcons (Dog ann) pnil)) (pcons (fact-ev (Dog ann)) pnil))"
  assert_contains "$out" "(proved (Animal ann) (0.95 0.7999999987832213) (scheduledN (Animal ann) (ctv (0.95 0.8) (0.0 1.0)) (pcons (Cat ann) pnil)) (pcons (fact-ev (Cat ann)) pnil))"

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
(ruleN (Animal $x) (ctv (0.9 0.8) (0.0 1.0)) (pcons (Dog $x) pnil))
(ruleN (Animal $x) (ctv (0.95 0.8) (0.0 1.0)) (pcons (Cat $x) pnil))
(ruleN (Pet $x) (ctv (0.8 0.7) (0.0 1.0)) (pcons (Dog $x) pnil))
(ruleN (Combo $x) (ctv (0.7 0.9) (0.0 1.0)) (pcons (Animal $x) (pcons (Pet $x) pnil)))
EOF

  build_runtime_from_core "$source_runtime" \
    '(, (Goal (Combo ann)))' \
    '(fact (Dog ann) (1.0 1.0))' \
    '(fact (Cat ann) (1.0 1.0))'
  build_runtime_from_core_with_sink_head "$sink_runtime" \
    '(, (Goal (Combo ann)))' \
    '(fact (Dog ann) (1.0 1.0))' \
    '(fact (Cat ann) (1.0 1.0))'

  mork run "$rules" --steps "$(steps_budget 17 11)" --aux-path "$source_runtime" "$source_out" >/dev/null
  mork run "$rules" --steps "$(steps_budget 17 11)" --aux-path "$sink_runtime" "$sink_out" >/dev/null

  assert_semantic_outputs_equal "$source_out" "$sink_out" "head_source_sink"
  assert_contains "$source_out" "(fact (Combo ann) (0.5179999999719824 0.8494800133141293))"
}

run_reduced_test
run_full_test
run_priority_test
run_reference_compose_test
run_reference_open_query_test
run_reference_independent_test
run_reference_binding_test
run_reference_three_premise_test
run_reference_nary_conjunction_test
run_reference_stv_implication_test
run_reference_implication_inversion_test
run_same_premise_rules_test
run_ffi_harness_test
run_open_multiple_proofs_demo_test
run_head_source_sink_equivalence_test

echo "PASS: runtime regression suite"
