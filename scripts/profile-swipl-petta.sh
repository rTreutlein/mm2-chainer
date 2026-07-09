#!/usr/bin/env bash
# Profile one generated MeTTa fixture through SWI-Prolog's built-in profiler.
#
# This profiles the same entry point as the petta wrapper, but consumes
# profile_data/1 directly so the output is stable in headless environments.
#
# Example:
#   bash scripts/profile-swipl-petta.sh test_forward_chainer
#   MM2_SWIPL_PROFILE_TOP=50 bash scripts/profile-swipl-petta.sh tests/harness/generated/test_forward_chainer.metta

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

top_n="${MM2_SWIPL_PROFILE_TOP:-30}"
timeout_s="${MM2_SWIPL_PROFILE_TIMEOUT:-300}"
report="${MM2_SWIPL_PROFILE_OUT:-outputs/swipl_profile.tsv}"
log="${MM2_SWIPL_PROFILE_LOG:-outputs/swipl_profile.log}"
petta_dir="${PETTA_DIR:-/nexus/Dev/OpenCog/PeTTa}"

require_positive_int() {
  local name="$1"
  local value="$2"
  case "$value" in
    ''|*[!0-9]*)
      echo "$name must be a positive integer, got: $value" >&2
      exit 2
      ;;
  esac
  if [ "$value" -lt 1 ]; then
    echo "$name must be a positive integer, got: $value" >&2
    exit 2
  fi
}

usage() {
  echo "usage: bash scripts/profile-swipl-petta.sh <generated-fixture-or-stem>" >&2
}

require_positive_int MM2_SWIPL_PROFILE_TOP "$top_n"
require_positive_int MM2_SWIPL_PROFILE_TIMEOUT "$timeout_s"

if [ "$#" -ne 1 ]; then
  usage
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

if [ ! -f "$petta_dir/src/metta.pl" ]; then
  echo "PeTTa metta.pl not found under PETTA_DIR=$petta_dir" >&2
  exit 2
fi

mkdir -p "$(dirname "$report")" "$(dirname "$log")"
bash scripts/build-runtime.sh outputs/harness_runtime.mm2

tmp_runner="$(mktemp --suffix=.pl)"
trap 'rm -f "$tmp_runner"' EXIT

cat > "$tmp_runner" <<'PROLOG'
:- use_module(library(prolog_profile)).

main :-
    current_prolog_flag(argv, [File, TopText, Report|_]),
    atom_number(TopText, Top),
    getenv('PETTA_METTA_FILE', MettaFile),
    ensure_loaded(MettaFile),
    profile(load_metta_file(File, Results), [time(wall)]),
    length(Results, ResultCount),
    profile_data(Data),
    setup_call_cleanup(
        open(Report, write, Out),
        write_report(Out, File, ResultCount, Data, Top),
        close(Out)),
    halt.

node_key(self, Node, Value) :-
    !,
    Value is Node.ticks_self.
node_key(children, Node, Value) :-
    !,
    Value is Node.ticks_siblings.
node_key(total, Node, Value) :-
    Value is Node.ticks_self + Node.ticks_siblings.

compare_node(Key, Delta, A, B) :-
    node_key(Key, A, VA),
    node_key(Key, B, VB),
    compare(C, VB, VA),
    (   C == (=)
    ->  with_output_to(atom(PA), writeq(A.predicate)),
        with_output_to(atom(PB), writeq(B.predicate)),
        compare(Delta, PA, PB)
    ;   Delta = C
    ).

pct(_Ticks, TotalTicks, 0.0) :-
    TotalTicks =< 0,
    !.
pct(Ticks, TotalTicks, Percent) :-
    Percent is 100.0 * Ticks / TotalTicks.

write_summary(Out, File, ResultCount, Summary) :-
    NetTicks is max(0, Summary.ticks - Summary.accounting),
    format(Out, '# file=~w~n', [File]),
    format(Out, '# result_count=~w~n', [ResultCount]),
    format(Out, '# samples=~w~n', [Summary.samples]),
    format(Out, '# ticks=~w~n', [Summary.ticks]),
    format(Out, '# accounting_ticks=~w~n', [Summary.accounting]),
    format(Out, '# net_ticks=~w~n', [NetTicks]),
    format(Out, '# sampled_time_s=~6f~n', [Summary.time]),
    format(Out, '# sample_period_us=~w~n', [Summary.sample_period]),
    format(Out, '# call_graph_nodes=~w~n', [Summary.nodes]).

write_node(Out, Sort, Rank, TotalTicks, Node) :-
    Self is Node.ticks_self,
    Children is Node.ticks_siblings,
    Total is Self + Children,
    Fail is Node.call + Node.redo - Node.exit,
    pct(Self, TotalTicks, SelfPct),
    pct(Children, TotalTicks, ChildrenPct),
    pct(Total, TotalTicks, TotalPct),
    with_output_to(atom(Predicate), writeq(Node.predicate)),
    format(Out, '~w\t~d\t~w\t~d\t~d\t~d\t~d\t~d\t~d\t~d\t~2f\t~2f\t~2f~n',
           [Sort, Rank, Predicate, Node.call, Node.redo, Node.exit, Fail,
            Self, Children, Total, SelfPct, ChildrenPct, TotalPct]).

write_top(_, _, _, _, [], _) :-
    !.
write_top(_, _, Rank, Top, _, _) :-
    Rank > Top,
    !.
write_top(Out, Sort, Rank, Top, [Node|Rest], TotalTicks) :-
    write_node(Out, Sort, Rank, TotalTicks, Node),
    NextRank is Rank + 1,
    write_top(Out, Sort, NextRank, Top, Rest, TotalTicks).

write_section(Out, Sort, Nodes, Top, TotalTicks) :-
    predsort(compare_node(Sort), Nodes, Sorted),
    write_top(Out, Sort, 1, Top, Sorted, TotalTicks).

write_report(Out, File, ResultCount, Data, Top) :-
    Summary = Data.summary,
    Nodes = Data.nodes,
    TotalTicks is max(1, Summary.ticks - Summary.accounting),
    write_summary(Out, File, ResultCount, Summary),
    format(Out, 'sort\trank\tpredicate\tcalls\tredos\texits\tfails\tticks_self\tticks_children\tticks_total\tpct_self\tpct_children\tpct_total~n', []),
    write_section(Out, self, Nodes, Top, TotalTicks),
    write_section(Out, children, Nodes, Top, TotalTicks),
    write_section(Out, total, Nodes, Top, TotalTicks).

:- initialization(main, main).
PROLOG

mork_ffi="$petta_dir/mork_ffi/target/release/libmork_ffi.so"
status=0
if [ -f "$mork_ffi" ]; then
  PETTA_METTA_FILE="$petta_dir/src/metta.pl" LD_PRELOAD="$mork_ffi" timeout "$timeout_s" swipl --stack_limit=8g -q -s "$tmp_runner" -- "$fixture" "$top_n" "$report" mork -s > "$log" 2>&1 || status=$?
else
  PETTA_METTA_FILE="$petta_dir/src/metta.pl" timeout "$timeout_s" swipl --stack_limit=8g -q -s "$tmp_runner" -- "$fixture" "$top_n" "$report" mork -s > "$log" 2>&1 || status=$?
fi

if [ "$status" -ne 0 ]; then
  echo "profile failed with status $status; see $log" >&2
  exit "$status"
fi

echo "wrote $report"
echo "raw log: $log"
sed -n '1,20p' "$report"
