# MM2 Chainer

Repository layout:

- `runtime/`
  - `core_runtime.mm2`: index explaining the split runtime layout
  - `default_seed.mm2`: default seed goal/facts for the shipped demos
  - `parts/`: ordered runtime phases assembled by `scripts/build-runtime.sh`
    - `00_frontier.mm2`: goal satisfaction, rule lowering, and scheduling
    - `10_premises.mm2`: premise frontier traversal and premise STV aggregation
    - `20_proofs.mm2`: proof STV calculation and proof emission
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

The STV pipeline takes more MM2 steps than the original chainer because it separates:

1. rule scheduling
2. proof production
3. STV computation
4. one-shot proof merge into canonical facts

The source is split by those runtime phases under `runtime/parts/`. MM2 aux loading uses one file,
so the run scripts first assemble the ordered parts into `outputs/*_runtime.mm2`.

It no longer allocates a temporary `exec-template` per proof attempt. Merge selection uses
short-lived per-goal selectors so proofs for distinct goals can merge independently, while
proofs for the same goal still revise the canonical fact one at a time. It no longer has
separate single-premise and multi-premise execution paths. All rules flow through one generic
`ruleN -> pendingN -> selectedN -> wait-premises` frontier, with plain `rule` lowered into a
single-premise `ruleN` shape at runtime.

Current script defaults:

- `scripts/run-reduced.sh`: `140` steps
- `scripts/run-full.sh`: `1000` steps
- `scripts/run-priority-demo.sh`: `1` step
- `scripts/run-multipremise.sh`: `60` steps
- `scripts/run-open-multiple-proofs.sh`: `90` steps
- `scripts/run-chain.sh`: `200` steps
- `scripts/run-cyclic.sh`: `80` steps
- `scripts/run-independent.sh`: `60` steps
