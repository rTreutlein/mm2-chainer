# Runtime Diagram

This document visualizes the current MM2 chainer runtime from two angles:

- how the runnable runtime is assembled by the shell entrypoints
- how a `Goal` moves through the generic `ruleN -> pendingN -> wait-premises -> proof -> merge` pipeline

## Assembly View

```mermaid
flowchart LR
    subgraph Inputs
        Seed[runtime/default_seed.mm2]
        Frontier[runtime/parts/00_frontier.mm2]
        Premises[runtime/parts/10_premises.mm2]
        Proofs[runtime/parts/20_proofs.mm2]
        Merge[runtime/parts/30_merge.mm2]
        Loop[runtime/parts/90_loop.mm2]
        ReducedRules[rules/reduced_rules.mm2]
        FullRules[rules/full_rules.mm2]
        Demo[demos/priority_scheduler_demo.mm2]
    end

    subgraph Launchers
        BuildRuntime[scripts/build-runtime.sh]
        RunReduced[scripts/run-reduced.sh]
        RunFull[scripts/run-full.sh]
        RunDemo[scripts/run-priority-demo.sh]
    end

    subgraph Generated
        ReducedRuntime[outputs/reduced_runtime.mm2]
        FullRuntime[outputs/full_runtime.mm2]
        ReducedOut[outputs/reduced_run.mm2]
        FullOut[outputs/full_run.mm2]
        DemoOut[outputs/priority_demo.mm2]
    end

    Seed --> BuildRuntime
    Frontier --> BuildRuntime
    Premises --> BuildRuntime
    Proofs --> BuildRuntime
    Merge --> BuildRuntime
    Loop --> BuildRuntime
    BuildRuntime --> ReducedRuntime
    BuildRuntime --> FullRuntime

    ReducedRules --> RunReduced
    ReducedRuntime --> RunReduced
    RunReduced -->|mork run| ReducedOut

    FullRules --> RunFull
    FullRuntime --> RunFull
    RunFull -->|mork run| FullOut

    Demo --> RunDemo
    RunDemo -->|mork run| DemoOut
```

## Runtime Flow

```mermaid
flowchart TD
    Start["Seed goal or regenerated subgoal"] --> Goal["Goal g
consume: exec 0, exec 1"]

    Goal --> FactCheck{fact g already exists?}
    FactCheck -->|yes| DropGoal["Drop Goal"]
    FactCheck -->|no| RuleMatch["Match rule or ruleN for g
exec 1"]

    RuleMatch --> LowerRule["Lower rule to generic premises list
exec 1"]
    LowerRule --> Pending["pendingN(priority, g, rule STV, premises)
produce: exec 1
consume: exec 3 via head 32 source"]

    Pending -->|head 32 source via exec 3| WaitList["wait-premises(remaining-premises, agg-stv, proof-id)
produce: exec 3, exec 4
consume: exec 4"]

    WaitList --> PremiseCheck{Premises empty?}
    PremiseCheck -->|yes| ProofSeed["proof-input(g, rule-stv, premise-stv, proof-id)
 produce: exec 4
 consume: exec 8"]
    PremiseCheck -->|no| Wait["wait-premise(current premise, rest, agg-stv, proof-id)
 produce: exec 4
 consume: exec 4"]

    Wait --> SpawnSubgoal["Emit Goal for current premise
produce: exec 4"]
    SpawnSubgoal --> Goal
    Wait --> FactPrem["Match fact for current premise
exec 4"]
    FactPrem --> PremStep["premise-step
produce: exec 4"]
    PremStep --> PremCalc["Compute packed next aggregate STV via min and advance
exec 4"]

    PremCalc --> PremDone{More premises left?}
    PremDone -->|yes| WaitNext["Advance wait-premises to remaining premises
exec 4"]
    WaitNext --> SpawnSubgoal
    PremDone -->|no| ProofSeed

    ProofSeed --> ProofCalc["Compute packed proof STV and emit proof
exec 8"]
    ProofCalc --> Proved["proved(g, stv, proof-id)
produce: exec 8
consume: exec C, exec D, exec E"]
    ProofCalc --> Slot["slot(g)
produce: exec 8
consume: exec B, exec D"]
    ProofCalc --> ProofOpen["proof-open(proof-id)
produce: exec 8
consume: exec B, exec C, exec D, exec E"]

    Proved --> MergeSelect["selected-merge(g, stv, proof-id)
produce: per-goal exec C via head 1
consume: exec D, exec E"]
    ProofOpen --> MergeSelect

    MergeSelect --> FirstProof{Canonical fact already present?}
    FirstProof -->|no| Promote["Promote first proof directly to fact
exec D"]
    FirstProof -->|yes| ReplaceFact["Atomically consume fact(g, old-stv)
and emit fact(g, merged-stv)
exec E"]

    Promote --> Fact["fact(g, stv)
produce: exec D, exec E
consume: exec 0, exec 4, exec B, exec E"]
    ReplaceFact --> Fact

    Fact --> CleanupSlot["Drop stale slot or stale reopen token
exec B"]
    Fact --> FutureGoals["Later Goal checks short-circuit on fact
exec 0"]
```

## Reading Notes

- `head 32` is the rule scheduler gate from `pendingN` into `wait-premises`.
- Merge selection installs a small selector for each concrete goal; each selector uses `head 1`, so proofs for the same goal are serialized while distinct goals can merge independently.
- Single-premise `rule` entries are normalized into the same generic `ruleN` path as multi-premise rules.
- STVs are packed as `(strength confidence)` tuples throughout the runtime. Premise aggregation uses `min` across premise STVs, then proof STV uses rule STV `*` aggregated premise STV.
- Later proofs do not create duplicate canonical facts; they revise the existing `fact` through the merge path.
- `exec Z` is the control loop that keeps all `exec-template` rules live; it is runtime scaffolding, so it is not shown as a flow node above.

## Helper State Map

Some helper states are part of the runtime but were left out of the main flowchart to keep it readable:

- `proof-merged(...)`: produced by `exec D` or `exec E`, consumed by `exec B`
