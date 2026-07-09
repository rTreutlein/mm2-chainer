# MM2 Chainer

Repository layout:

- `runtime/`
  - `core_runtime.mm2`: index explaining the split runtime layout
  - `default_seed.mm2`: default seed goal/facts for the shipped demos
  - `parts/`: ordered runtime phases assembled by `scripts/build-runtime.sh`
    - `00_frontier.mm2`: goal satisfaction, rule lowering, and scheduling
    - `05_baserate.mm2`: base-rate maintenance for derived rule CTVs
    - `10_premises.mm2`: premise frontier traversal, premise STV aggregation, and proof emission
    - `30_merge.mm2`: proof merge and canonical fact revision
    - `90_loop.mm2`: `exec-template` activation loop
- `rules/`
  - `full_rules.mm2`: full paired one-premise rule export with rule STVs
  - `reduced_rules.mm2`: reduced example rule set with two distinct proofs for one atom
- `demos/`
  - `priority_scheduler_demo.mm2`: minimal priority queue demo
  - `multipremise.mm2`: two-premise `ruleN` reasoning
  - `open_multiple_proofs.mm2`: open query with two proofs for the same grounded fact
  - `chain.mm2`: deep transitive forward chain with STV propagation
  - `cyclic.mm2`: self-loop cycle handling
  - `independent.mm2`: parallel satisfaction of independent goals
- `scripts/`
  - `build-runtime.sh`: assemble ordered runtime parts into one aux file
  - `run-full.sh`: run the full pipeline
  - `run-reduced.sh`: run the reduced STV merge example
  - `run-priority-demo.sh`: run the scheduler demo
  - `run-multipremise.sh`: run the two-premise demo
  - `run-open-multiple-proofs.sh`: run the open-query multiple-proof merge demo
  - `run-chain.sh`: run the transitive-chain demo
  - `run-cyclic.sh`: run the cycle-handling demo
  - `run-independent.sh`: run the independent-goals demo
  - `bench-harness-corpus.sh`: repeat selected generated harness fixtures and
    report baseline-subtracted timing medians
- `outputs/`
  - ignored generated results from the scripts
- `docs/`
  - `runtime-diagram.md`: Mermaid diagrams for runtime assembly and execution flow

Quick usage:

```bash
bash scripts/run-reduced.sh
bash scripts/run-full.sh
bash scripts/run-priority-demo.sh
bash scripts/run-multipremise.sh
bash scripts/run-open-multiple-proofs.sh
bash scripts/run-chain.sh
bash scripts/run-cyclic.sh
bash scripts/run-independent.sh
bash scripts/test.sh
```

`scripts/test.sh` runs the MM2 runtime regression suite, verifies the generated
PeTTaChainer corpus is in sync with `scripts/convert_petta_tests.py`, and then
runs the corpus gate. The generated-corpus check also verifies that generated
files match upstream PeTTaChainer `test_*.metta` files and that every generated
fixture has an explicit pass floor. The corpus gate fails if generated tests produce
close or fail verdicts, unsupported IR, converter skips, omitted forms, or
timeout/error files, and it also fails if the total pass count drops below the
current coverage floor or an individual generated file drops below its current
pass count. Real generated corpus fixtures must have an explicit pass floor in
`scripts/harness-common.sh`; scratch `.metta` probes outside
`tests/harness/generated/` may still use the default floor of zero. The corpus
report also includes per-file and total elapsed time so slow fixtures are
visible in the normal gate output. Corpus files run in parallel with 4 jobs by
default; set positive-integer `MM2_HARNESS_JOBS=1` for serial debugging or a
higher value for local timing experiments. Harness side-log files live under
`outputs/` and are managed by the runner scripts.
After each corpus run, `outputs/harness_perf.tsv` lists generated files sorted
slowest-first by elapsed milliseconds.

For focused iteration on a generated fixture, pass one or more file stems or
paths:

```bash
bash scripts/run-harness-corpus.sh test_forward_chainer
bash scripts/run-harness-corpus.sh tests/harness/generated/test_math.metta
```

Focused runs write `outputs/harness_report.focus.txt` and
`outputs/harness_perf.focus.tsv`, leaving the last full-corpus reports intact.

For local performance triage, repeat selected generated fixtures with startup
overhead separated from fixture work:

```bash
bash scripts/bench-harness-corpus.sh
MM2_BENCH_RUNS=5 bash scripts/bench-harness-corpus.sh test_forward_chainer test_particle_values
```

With no fixture arguments, the benchmark script uses the slowest
`MM2_BENCH_TOP=5` files from the last `outputs/harness_perf.tsv` report. It
writes median gross and baseline-subtracted timings to
`outputs/harness_bench.tsv` plus per-run samples to
`outputs/harness_bench_runs.tsv`. It exits nonzero if any sampled fixture has a
`petta` error, timeout, close/fail verdict, unsupported IR marker, or skipped
form, if it contains an omitted/adapted marker outside the corpus limits, or if
its pass count drops below the generated corpus floor.

The STV pipeline takes more MM2 steps than the original chainer because it separates:

1. rule scheduling
2. proof production
3. STV computation
4. one-shot proof merge into canonical facts

The source is split by those runtime phases under `runtime/parts/`. MM2 aux loading uses one file,
so the run scripts first assemble the ordered parts into `outputs/*_runtime.mm2`.

It no longer allocates temporary `exec-template`s per proof attempt or per merge goal.
Proofs still revise the canonical fact one at a time. It no longer has
separate single-premise and multi-premise execution paths. All rules flow through one generic
`ruleN -> pendingN -> wait-premises` frontier.

Rule truth values are structured PeTTaChainer-style contextual TVs:

- `(ruleN $g (ctv ($s+ $c+) ($s- $c-)) $premises)`: explicit CTV rule
- `(ruleN $g (stv ($s $c) (brpat $ante $cons)) $premises)`: plain STV rule whose
  negative branch is derived at fire time from the base rates of the `brpat`
  keys. Compiled STV rules key these by rule id and fold role so unifiable
  antecedent/consequent patterns do not cross-match.
- `(ruleN $a (inv ($s+ $c+) (brpat $ante $cons)) $premises)`: inverse of an
  implication (PeTTa's `CTVInversionFormula`); the original rule's positive
  branch is inverted through the fire-time base rates, and the attempt retries
  without consuming its premises while the inversion is rejected (no base-rate
  evidence yet, or marginals outside the Frechet bounds)
- `(adapterN $g $premises)`: identity rule for compound queries; the premise
  aggregate is used directly

Proof evidence items name their source only (`(fact-ev $prem)`), like
PeTTaChainer proof names: a re-derivation from the same source overlaps the
fact's accumulated evidence and the merge keeps the higher-confidence value
instead of revising the same evidence in twice.

Truth-value propagation matches PeTTaChainer's formulas (tv_formulas.metta):
premise lists fold with `AndFormula` (product strength, idealized product
confidence) and rule application is `CTVModusPonensFormula` (idealized
second-order modus ponens), implemented as MORK pure ops
(`pln_and_confidence_f64`, `pln_mp_strength_f64`, `pln_mp_confidence_f64`,
`pln_negative_branch_strength_f64`).

Current script defaults:

- `scripts/run-reduced.sh`: `220` steps
- `scripts/run-full.sh`: `200` steps
- `scripts/run-priority-demo.sh`: `1` step
- `scripts/run-multipremise.sh`: `90` steps
- `scripts/run-open-multiple-proofs.sh`: `130` steps
- `scripts/run-chain.sh`: `260` steps
- `scripts/run-cyclic.sh`: `100` steps
- `scripts/run-independent.sh`: `90` steps
