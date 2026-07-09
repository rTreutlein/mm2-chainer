#!/usr/bin/env bash

harness_floor_table() {
  cat <<'EOF'
test_backward_dag_helpers	34
test_backward_open_query_results	3
test_base_rate_cache	10
test_benchgen_metta	23
test_best_first_runtime	12
test_chainer_add_atom	2
test_distribution_values	6
test_evidence_semantics	2
test_foldall_merged_outputs	2
test_foldall_query_goal	3
test_forward_backward_compose	19
test_forward_chainer	30
test_frontier_pooling	6
test_height_average	4
test_idealized_confidence	12
test_implication_inversion	1
test_implication_premise	16
test_inheritance_query_proof	1
test_lifting_merge	6
test_logic_config	10
test_math	3
test_member_compat	3
test_member_concept_node	2
test_merged_subgoal_rule_application	2
test_nary_conjuction	1
test_negated_evidence_merge	5
test_numeric_pattern_dist	5
test_particle_values	22
test_query_adds	5
test_query_compute_in_compound	3
test_query_materialize	8
test_rectangle_area	3
test_specializing_rule	5
test_stv_implication_derived_ctv	1
test_total_implication_aggregate	1
test_uniform_prior	9
test_var_head	2
EOF
}

harness_floor_names() {
  harness_floor_table | cut -f1
}

validate_harness_floor_table() {
  harness_floor_table |
    awk -F '\t' '
      NF != 2 {
        print "invalid corpus pass floor row: " $0 > "/dev/stderr"
        err = 1
        next
      }
      $1 !~ /^test_[[:alnum:]_]+$/ {
        print "invalid corpus pass floor name: " $1 > "/dev/stderr"
        err = 1
      }
      seen[$1]++ {
        print "duplicate corpus pass floor entry: " $1 > "/dev/stderr"
        err = 1
      }
      $2 !~ /^[1-9][0-9]*$/ {
        print "invalid corpus pass floor for " $1 ": " $2 > "/dev/stderr"
        err = 1
      }
      END { exit err }
    '
}

min_pass_for_file() {
  harness_floor_table |
    awk -F '\t' -v name="$1" '$1 == name && !found { print $2; found = 1 } END { if (!found) print 0 }'
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
