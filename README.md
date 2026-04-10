# MM2 Chainer

Repository layout:

- `runtime/`
  - `core_runtime.mm2`: shared STV-aware chainer core
  - `full_seed.mm2`: seed goal/facts for the full run
  - `reduced_seed.mm2`: seed goal/facts for the reduced example
- `rules/`
  - `full_rules.mm2`: full paired one-premise rule export with rule STVs
  - `reduced_rules.mm2`: reduced example rule set with two distinct proofs for one atom
- `demos/`
  - `priority_scheduler_demo.mm2`: minimal priority queue demo
- `scripts/`
  - `run-full.sh`: run the full pipeline
  - `run-reduced.sh`: run the reduced STV merge example
  - `run-priority-demo.sh`: run the scheduler demo
- `outputs/`
  - ignored generated results from the scripts

Quick usage:

```bash
bash scripts/run-reduced.sh
bash scripts/run-full.sh
bash scripts/run-priority-demo.sh
bash scripts/test.sh
```

The STV pipeline takes more MM2 steps than the original chainer because it now separates:

1. rule scheduling
2. proof production
3. STV computation
4. one-shot proof merge into canonical facts

It no longer allocates a temporary `exec-template` per proof attempt, and it no longer has
separate single-premise and multi-premise execution paths. All rules flow through one generic
`ruleN -> pendingN -> selectedN -> wait-premises` frontier, with `rule` and `rule2` kept only as
compatibility shims.

Current script defaults:

- `scripts/run-reduced.sh`: `140` steps
- `scripts/run-full.sh`: `1000` steps
- `scripts/run-priority-demo.sh`: `1` step
