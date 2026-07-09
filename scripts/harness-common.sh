#!/usr/bin/env bash

min_pass_for_file() {
  case "$1" in
    test_backward_dag_helpers) echo 34 ;;
    test_backward_open_query_results) echo 3 ;;
    test_base_rate_cache) echo 10 ;;
    test_benchgen_metta) echo 23 ;;
    test_best_first_runtime) echo 12 ;;
    test_chainer_add_atom) echo 2 ;;
    test_distribution_values) echo 6 ;;
    test_evidence_semantics) echo 2 ;;
    test_foldall_merged_outputs) echo 2 ;;
    test_foldall_query_goal) echo 3 ;;
    test_forward_backward_compose) echo 19 ;;
    test_forward_chainer) echo 30 ;;
    test_frontier_pooling) echo 6 ;;
    test_height_average) echo 4 ;;
    test_idealized_confidence) echo 12 ;;
    test_implication_inversion) echo 1 ;;
    test_implication_premise) echo 16 ;;
    test_inheritance_query_proof) echo 1 ;;
    test_lifting_merge) echo 6 ;;
    test_logic_config) echo 10 ;;
    test_math) echo 3 ;;
    test_member_compat) echo 3 ;;
    test_member_concept_node) echo 2 ;;
    test_merged_subgoal_rule_application) echo 2 ;;
    test_nary_conjuction) echo 1 ;;
    test_negated_evidence_merge) echo 5 ;;
    test_numeric_pattern_dist) echo 5 ;;
    test_particle_values) echo 22 ;;
    test_query_adds) echo 5 ;;
    test_query_compute_in_compound) echo 3 ;;
    test_query_materialize) echo 8 ;;
    test_rectangle_area) echo 3 ;;
    test_specializing_rule) echo 5 ;;
    test_stv_implication_derived_ctv) echo 1 ;;
    test_total_implication_aggregate) echo 1 ;;
    test_uniform_prior) echo 9 ;;
    test_var_head) echo 2 ;;
    *) echo 0 ;;
  esac
}

max_adapted_for_file() {
  echo 0
}

requires_harness_floor() {
  case "$1" in
    tests/harness/generated/test_*.metta|*/tests/harness/generated/test_*.metta)
      return 0
      ;;
    *)
      return 1
      ;;
  esac
}
