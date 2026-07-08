# Parity plan: port `test_stv_implication_derived_ctv.metta`

Goal: bring mm2-chainer closer to PeTTaChainer parity by porting
`PeTTaChainer/pettachainer/metta/tests/test_stv_implication_derived_ctv.metta`:

```metta
!(compileadd stvRuleKb (: a (A x) (STV 1.0 0.9)))
!(compileadd stvRuleKb
   (: aToB (Implication (Premises (A $x)) (Conclusions (B $x))) (STV 0.6 0.9)))
!(test (query 20 stvRuleKb (: $prf (B x) $tv))
       (: (aToB a) (B x) (STV 0.6 0.8999998649685302)))
```

Out of scope (per instructions): forward chaining, the Python interface,
distributional values.

## Status

- [x] Previous port (n-ary conjunction, task.txt) is complete and the whole
      suite passes. The only issue found was a stale `~/.cargo/bin/mork`
      binary; rebuilt from `../../MORK` (needed `cargo update indexmap` to fix
      a workspace resolution conflict) and copied into `~/.cargo/bin`.
- [x] 1. MORK pure ops for modus ponens
- [x] 2. MORK base-rate fold sink
- [x] 3. mm2 runtime: structured rule TVs + base-rate maintenance
      (new part `runtime/parts/05_baserate.mm2`)
- [x] 4. Compiler backend: Implication lowering + atomic query lowering
- [x] 5. Migrate existing rules/demos/tests to new `ruleN` TV shapes and
      PeTTa-parity expected values (binding test now routes its `And` goal
      through `adapterN` like PeTTa's compiler does, giving PeTTa's exact
      published value `(0.5599999999999999 0.9999136351865401)`)
- [x] 6. Add `run_reference_stv_implication_test`; full suite green

**DONE.** The port is complete: `bash tests/test_runtime.sh` passes all 12
tests, and all demo scripts complete. Values verified against
`scripts/pln_ref.py` (a Python mirror of the PeTTa/MORK formulas — extend it
when computing expected values for future ports).

# Follow-up port: `test_implication_inversion.metta` (DONE 2026-07-07)

Ported as `run_reference_implication_inversion_test` (13 tests total now).
The pieces:

- MORK pure ops `pln_inv_strength_f64`, `pln_inv_confidence_f64`,
  `pln_inversion_valid_f64` (CTVInversionFormula; the negative inverted
  branch reuses the same ops with complemented `sb`/`sb_a` arguments —
  `ideal-var` is symmetric in `s` vs `1-s`).
- Runtime `inv` rule kind: the fire attempt does not consume the wait record;
  it emits an `(inv-checked ($flag $s $c) ...)` verdict each round. Accepted
  verdicts (flag 1.0) consume both and open the proof; rejected ones are
  dropped and the attempt retries as base rates evolve. This reproduces
  PeTTa's fire-time semantics: the inversion in the test is *inconsistent*
  (Frechet bounds) until the derived `(Q bob)` reaches the Q base rate.
- Compiler emits, per single-premise **CTV** implication (unless the proof
  name is `(no_inverse $x)`): the inverse `ruleN`, base-rate support for both
  patterns, and an open materialization goal `(, (Goal <cons-pattern>))` —
  PeTTa's base-rate folds are chaining queries, so derived conclusion
  instances must reach the fact store.
- Two convergence bugs this surfaced, both fixed:
  1. The proofs-only revise exec ran before the revision-aware one and wrote
     duplicate `(fact $g ...)` atoms. Fix: revision-aware exec at priority C,
     proofs-only at D. Seeded facts need a `(fact-evidence ...)` record to be
     revisable — the compiler emits one per fact add.
  2. Evidence items carried TVs, so re-derivations from the same source
     looked like fresh evidence and revision ran away. Evidence is now source
     identity only: `(fact-ev $prem)`; overlapping evidence keeps the
     higher-confidence value (idempotent, converges).

Known scope limits (documented divergences):
- **STV rules do not compile inverses yet.** Their derived CTV reads the
  conclusion base rate, and PeTTa's folds have a recursion guard (a rule's
  own fold never includes conclusions derived via that same rule) that the
  mm2 base-rate relation doesn't model. With materialization the STV rule
  would re-fire against its own conclusions and drift from PeTTa's value.
- Multi-premise implications do not compile inverses (PeTTa skolemizes; not
  modeled).
- The final `(fact ...)` values may refine past PeTTa's one-shot query answer
  because mm2 keeps re-deriving as base rates evolve; port assertions should
  pin `(proved ...)` records (immutable), not facts, for inversion-affected
  goals.

# In-process FFI harness (DONE 2026-07-07)

`compiler/mm2_chainer.metta` runs PeTTaChainer-style test files near-verbatim
against the mm2 runtime **in one petta process**, via PeTTa's mork_ffi
(`&mork` space + `mm2-exec`, which calls MORK's `space.metta_calculus`):

```metta
!(import! &self .../compiler/mm2_chainer)
!(mm2-init)
!(mm2-compileadd kb (: a (A x) (STV 1.0 0.9)))
!(mm2-test (mm2-query 20 kb (: $prf (B x) $tv))
           ((: $_ (B x) (STV 0.6 0.8999998649685302))))
```

- Statements compile through the thin backend; every goal term is wrapped as
  `($kb $term)` so named KBs share the space without cross-talk (verified).
- `mm2-test` compares (type, tv) sets — mm2 proof tokens differ from PeTTa
  proof terms by design. Verdicts: `pass` (exact) / `close` (within 1e-3
  relative — the inversion refinement drift) / `FAIL`.
- Converted tests live in `tests/harness/converted_tests.metta`; run with
  `scripts/run-harness-tests.sh` (wired into the suite, currently
  3 pass / 1 close / 0 fail).
- Setup facts: petta wrapper LD_PRELOADs
  `PeTTa/mork_ffi/target/release/libmork_ffi.so`, which path-depends on our
  `../../MORK` — rebuild with `cargo build -p mork_ffi --release` in
  `PeTTa/mork_ffi` after MORK changes (done 2026-07-07). petta `add-atom`
  stores arguments *unevaluated*: force computed atoms through `let` first.
  MeTTa variables round-trip into MM2 atoms correctly, including shared vars.

## Real compiler ported by IR translation (DONE 2026-07-07)

`compiler/mm2_ir_translate.metta` translates the IR PeTTaChainer's
compile.metta already emits (`mm2compile` / `mm2compileQuery`) into mm2
atoms; the harness now compiles through the real `compileadd` (which also
populates the compiler's internal state — spec templates, rule evidence,
inheritance records). Recognized CPU chains:

    subgoals + AndFormula*                      -> adapterN
    ... + MP with literal CTV                   -> ruleN ctv
    ... + Fold Fold ImplCTV(STV) MP             -> ruleN stv (+ brpat support)
    ... + Fold Fold ImplCTV Inversion MP        -> ruleN inv (+ consequent
                                                   materialization goal for
                                                   CTV-derived inverses only;
                                                   STV-derived inverses skip it
                                                   pending the recursion guard)

Unrecognized IR -> `(notsupported-ir ...)` markers in the transcript and the
space. Hand-converted tests keep identical verdicts through the real
compiler (3 pass, 1 close).

Corpus: `scripts/convert_petta_tests.py` converted 29 test files into
`tests/harness/generated/`; `scripts/run-harness-corpus.sh` runs them
(one petta process per file, 180 s timeout) into
`outputs/harness_report.txt` (per-file pass/close/fail/unsupported/ERROR).

## First full corpus run (2026-07-07)

`outputs/harness_report.txt`, 29 generated files (+4 hand-converted):

    totals: pass=42 close=11 fail=56 unsupported=244 flagged-files=2

Best files: forward_backward_compose 13 pass / 1 fail; query_adds 5 pass /
0 fail; implication_premise 7 pass / 8 fail; best_first_runtime 4 pass /
11 fail. Timeouts: backward_open_query_results (openTimeKb self-feeding
rule, see item 6 below), math (Compute-heavy).

Unsupported-IR clusters (from harness_logs, by CPU head):

    108 AndProjection      \ And-elimination adapter chain (compile-adapter-
     54 AndMarginalProjection / chain): 2/3 of ALL unsupported markers.
                              Formulas are simple (min/div/count) and
                              composable from existing pure ops; needs an
                              adapter rule kind that applies a named
                              projection formula.
     21 CTVModusPonensFormula  in arrangements the classifier misses
     16 NotFormula             negated premises/conclusions
     11 AndFormula             non-leading positions
     15 OrProjection/OrFormula
     10 FoldAllCompiled variants (weighted / grouped)
      3 MemberInheritanceFormula

Unsupported stmt shapes: query-form assumption facts
`(($type) ($kb $ctx $vars) (ctx proof N) (STV ...))` — 4-tuple facts added
by total-implication queries; the translator's fact clause only accepts the
5-tuple `(: ...)` form. Easy fix, unlocks implication-premise/compose
queries.

## Projection rules + IR-driven kb scoping (DONE 2026-07-07)

Commit 49782b9 (mm2-chainer) + 3b7e80d (MORK):

- **Projection rule kind** `(ruleN $g (proj and|or|marg) (pcons $compound
  $others))` covers the And/Or element-projection adapter chains (was 162 of
  244 unsupported markers). The compound head premise's TV is captured into
  the rule-TV slot via a `wait-head` record (new exec at priority 1 + 4);
  the other elements run through the generic premise fold; three fire execs
  apply AndProjection / OrProjection / AndMarginalProjection (new MORK pure
  ops `pln_{and,or}_proj_{strength,confidence}_f64`,
  `pln_marginal_proj_confidence_f64`). OrProjection with 3+ elements stays
  unsupported (its evidence folds with OrFormula, not the premise
  machinery's AndFormula).
- **KB scoping now comes from the IR itself** (this replaced the harness's
  `($kb $term)` wrap layer entirely): compile.metta scopes every item with
  a kb triple — `($kb MAIN Nil)` for ordinary statements (kbctx), a
  numbered assumption context for query premises — and rule items share
  free ctx/vars vars between premises and conclusion. Translating terms as
  `($kb-triple $term)` makes rules context-generic and facts
  context-specific, so total-implication assumption contexts are isolated
  for free. Query readback follows each compiled query's own goal scope
  (some queries allocate a fresh context instead of MAIN).
- **Query-form (4-tuple) assumption facts** `($type $shape $prf (STV ..))`
  now translate as facts (they're the assumption facts total-implication
  queries add into their contexts).
- **Test suite step budgets** are now `steps_budget rounds extra` (scales
  with the exec-template count) because every seeded exec costs one step
  whether or not it fires — adding runtime execs used to shift what stage
  snapshot tests observed. Two snapshots recalibrated (full: 1+13,
  binding mid: 5+0).
- test_frontier_pooling now runs its projections (values appear instead of
  unsupported markers) but the *pooling* TVs still diverge: PeTTa pools
  same-source projections back into the source TV, mm2 revises the andproj
  and margproj proofs together (that's the task-#15 proof-store pooling
  work, not a projection bug). Independent-fact conjunctions pass exactly.

## Total-implication + negated conclusions (DONE 2026-07-07, commits
## 0a1c5da..HEAD)

- `(proj ctvpair)` rule kind: total-implication queries conclude a
  contextual pair fact `(fact $g (ctvpair $pos $neg))` assembled
  structurally from the two assumption-context conclusions (detected by the
  CTV-shaped conclusion TV, guarded by is-expr since adapter TVs are free
  vars). ctvpair facts bypass open-proof (revision is (s c)-only); CTV
  premises contribute their positive branch (tv_formulas.metta MP/BaseRateAcc
  CTV clauses); base-rate + revise execs destructure packed pairs so ctvpair
  facts can't panic the sinks (sinks.rs:763 asserts arity 2).
- Implication-typed rule premises eagerly expand their total-implication
  scaffold at add time (needs-implication-query marker, ti-compiled guard) —
  PeTTa compiles sub-queries lazily at chain time, mm2 can't.
- `ctvn` rule kind: modus ponens + NotFormula tails (negated conclusions).
- mm2-test keys compare with =alpha (open-query results carry free vars whose
  identities differ; == counted alpha-equivalent answers as FAIL).
- test_implication_premise 14 pass / 2 fail (was 7/8 at first corpus run).
  Remaining: LocalFact self-implication (identity-query ctxatom with free TV),
  BiImplication combined query (one context conclusion lands at strength 0.0
  — suspect inverse-rule interference via revision; the directional
  bi-forward/bi-backward tests pass).

## Translator unification guards (DONE 2026-07-07, after 2nd corpus rerun)

Root cause behind test_var_head and suspect for other silent wrongness:
**translator case patterns unify with free IR variables and instantiate
them.** Three fixes:

- `(Implication $ps $cs)` bound a var-headed premise's `$r` to Implication
  (rule mangled into a bogus scaffold). Now matches `($head $ps $cs)` and
  checks `(not (is-var $head))` first.
- `(STV $s $c)` bound free-tv ctxatoms (identity-query assumption atoms from
  mm2compileQuery's context branch) into wildcard facts with unbound s/c.
  Facts now go through mm2-ir-fact-stmt with is-var checks; free/non-STV TVs
  produce loud markers.
- `mm2-ir-fold-pattern` was partial: a weighted-universe fold left an
  unreduced helper call inside the rule atom and the rule vanished with no
  marker. Now total: only extract-tv/BaseRateAcc/base-rate folds map to the
  base-rate relation; other folds -> unsupported-tail markers.

Corpus totals: after ctvn + =alpha keys 55/10/46/107; guard fixes rerunning.

## Open investigation notes (2026-07-07)

- **test_var_head** (DONE 2026-07-08): the consequent pattern has a variable
  head, so PeTTa compiles its base rate as a non-prior weighted-universe fold
  over fully open `Inheritance` facts
  (`WeightedBaseRateAcc (weighted-base-rate-in-universe kb)`). The current
  translator handles only that narrow empty-evidence branch by seeding the
  consequent base-rate relation as `(0.0 0.0)`; this is enough for
  `test_var_head` and avoids pretending we have full weighted inheritance
  fold support.
- **test_uniform_prior** is not a primary parity driver right now. It mixes
  standalone prior helper checks, dynamic concept-prior configuration, and an
  explicitly legacy inheritance-induction integration case, so use it as
  broad later integration coverage rather than the next focused runtime task.
- **test_math** no longer times out/segfaults in the current corpus after the
  expected-aware query runner and query cleanup work; it is 3 pass / 0 fail /
  0 unsupported in the latest run.
- **test_best_first_runtime** fails are agenda-order semantics: expected
  values assume PeTTa's best-first agenda finds specific proofs first under
  budget; mm2's wave execution derives all and revises (same family as
  frontier bounding, PLAN item 6).
- **Lifting-merge pooling algorithm** (backward_proof_store.metta:265-425)
  is now understood: group proofs of one grounded output; shared = evidence
  intersection (fact-ev only); guards = all proofs implication-shaped +
  residual evidence pairwise disjoint + 2-point strength round-trip; pooled
  = MP(real shared conjunction TV, revised residual CTVs) where residual =
  CTV(reeval shared->STV(1 1), reeval shared->STV(0 1)) re-evaluated through
  each proof's own premise-fold+MP tree. Port needs per-premise TVs carried
  into the revise sink rows (evset items are in premise order) and the rule
  CTV in the proof token — flat (s c) agg is not enough.

## FoldAll query aggregates (DONE 2026-07-08)

Numeric `FoldAll ... -> sum` and distributional `PairCounts` query folds now
lower through `compiler/mm2_ir_translate.metta` into `runtime/parts/20_foldall.mm2`.
`sum` uses the existing MORK aggregate sink; `PairCounts` uses a new MORK
`pair-counts` aggregate sink that groups distinct values and emits a
deterministic `(PairCounts ((value mass) ...))` result. Both direct facts and
derived facts are covered by `test_foldall_query_goal`; merged-proof FoldAll
inputs are covered by `test_foldall_merged_outputs`.

Latest corpus snapshot after this port:

    totals: pass=69 close=2 fail=42 unsupported=122 flagged-files=0

## Base-rate cache operations (IN PROGRESS 2026-07-08)

Generated tests now rewrite `set-base-rate`, `clear-base-rate`, and
`store-computed-base-rate!` to MM2-harness operations that update the MM2
runtime state rather than PeTTa's separate `&base_rate_cache`. User-provided
base rates remove the corresponding `base-rate-def` so the runtime fold cannot
overwrite them; clearing re-adds the fold support and zero seed. MORK's
`fold-base-rate` sink now preserves a higher-confidence cached/computed value
instead of replacing it with a lower-confidence recomputation.

This moves `test_base_rate_cache` to 3 pass / 1 close / 1 fail. Remaining
divergence: with a high-confidence cached antecedent, MM2 can fire the inverse
after the consequent has direct base-rate evidence but before the derived
consequent proof is folded into that consequent base rate. PeTTa's agenda
orders that query so the consequent fold includes the derived witness first.

Latest corpus snapshot after this step:

    totals: pass=70 close=2 fail=41 unsupported=122 flagged-files=0

## CTV query assumption facts (DONE 2026-07-08)

Concrete CTV-valued facts now translate to `ctvpair` facts instead of
`notsupported-ir` markers. This covers total-implication query assumption
facts whose TV is already known as `(CTV (STV ...) (STV ...))`.

Latest corpus snapshot after this translator cleanup:

    totals: pass=70 close=2 fail=41 unsupported=120 flagged-files=0

## Var-head weighted inheritance fold shortcut (DONE 2026-07-08)

`test_var_head` now lowers the exact weighted fold emitted for a var-headed
STV consequent: a non-prior `WeightedBaseRateAcc` fold over fully open
`Inheritance` facts. MM2 still does not implement the full weighted fold; the
translator only recognizes this open shape and seeds the consequent base-rate
copy as no evidence, which matches PeTTa's result for this focused test.

Latest corpus snapshot after this translator shortcut:

    totals: pass=70 close=4 fail=39 unsupported=119 flagged-files=0

## Next

1. **Triage order from the corpus report**: (a) ~~And/Or projection adapter
   rule kind~~ done, (b) ~~query-form assumption facts~~ done (full
   total-implication queries still need a CTV-assembling rule kind: the
   final rule's conclusion TV is `(CTV $pos-tv $neg-tv)` built structurally
   from the two context conclusions' TVs — no CPU formula — and facts can
   then carry CTV values), (c) ~~single-premise NotFormula -> CTV MP~~ done
   via `not-ctv`, (d) ~~NotFormula+AndFormula query-compound chain~~ done by
   lowering through an ordinary `proj not` rule plus a normal `ctv` rule,
   then remaining MP arrangements, weighted/grouped folds, and member
   machinery. Rerun
   `scripts/run-harness-corpus.sh` after each to watch the totals move.
   Current corpus snapshot (2026-07-08, after query cleanup, `not-ctv`,
   Not+And compound lowering, preserved logic-config imports, FoldAll query
   aggregates, partial base-rate cache operations, CTV assumption facts, and
   the var-head weighted-fold shortcut): pass=70 close=4 fail=39 unsupported=119
   flagged-files=0, wall time about 52 s.
2. **Proof-store pooling / evidence semantics** (test_lifting_merge,
   test_evidence_semantics, test_negated_evidence_merge): PeTTa pools
   proofs that share a premise but differ in rules by factoring the shared
   premise out and revising the residual implications
   (backward_proof_store.metta); mm2's fact-ev overlap keeps the
   higher-confidence proof instead. Needs rule identity in the IR/evidence
   (note: byte-identical duplicate rules — same TV, different PeTTa names —
   currently collapse into one ruleN atom) and pooling in the revise sink.
   Nearby approximations (plain revision of proof TVs, or revising rule
   CTVs before one MP) land within ~1e-9 of PeTTa but are not bit-exact;
   the exact algorithm must come from backward_proof_store.metta.
3. **Base-rate freeze semantics** to eliminate the `close` drift: PeTTa
   caches base rates per (kb, pattern) at first use (base_rate_cache in
   compiled_query_runtime.metta) so all rule firings in a query see one
   value; mm2 recomputes every round and merged facts keep refining.
4. STV-rule inversion materialization still needs the fold recursion guard
   (see above).
5. Converter gaps: `!(test (let ...))` forms and non-query test forms
   (set-base-rate, forward-chain, chainer-internal APIs) are passed through
   and surface as unsupported markers / unreduced terms.
6. **Frontier bounding for self-feeding rules**: PeTTa's query budget counts
   agenda pops, so a rule whose conclusion matches its own premises (e.g.
   test_backward_open_query_results' openTimeKb:
   `(AtTime $x $t),(AtTime $y $t) -> (AtTime (And $x $y) $t)`) derives only
   as deep as the budget allows. mm2's wave execution re-matches *all*
   premise pairs every round, so such KBs explode combinatorially (the
   scheduler's `head 32` bounds pendingN, but premise matching is
   unbounded). Runaway queries currently hit the corpus runner's per-file
   timeout; verdicts before them survive via the side log. A fix needs
   bounded premise matching (head-style sink on wait-premise instantiation)
   or PeTTa-style expansion accounting.
7. petta facts: bang results print only at process exit (main.pl collects
   them), so long files lose output on kill — hence the side log; `swrite`
   + open/write/nl/close via callPredicate is the durable-logging idiom.

## Key findings that drive the design

1. **The current mm2 rule application is not PeTTa-parity.** It computes the
   proof TV as `(rule-s*prem-s, rule-c*prem-c)`. PeTTa applies
   `CTVModusPonensFormula(premiseAggTV, ruleCTV)` (tv_formulas.metta):
   - strength `= bs_a*as + bs_na*(1-as)`
   - confidence `= ideal-mp-confidence(as, ac, bs_a, bc_a, bs_na, bc_na)`
     (second-order variance propagation, `VarsB = as^2*Va + (1-as)^2*Vna +
     (bs_a-bs_na)^2*Vz + Vz*(Va+Vna)`, then `ideal-conf-from-var`).
   E.g. PeTTa's own open-query test (rule CTV `((1.0 1.0)(0.0 1.0))`, exact
   premise) yields conf `0.9998000399670116`, not `1.0`. So the existing mm2
   test expectations (products) must be recomputed, not preserved.
2. **Rule TVs are CTVs.** `compileadd` rules authored with
   `(CTV (STV s+ c+) (STV s- c-))` use that CTV directly. Rules authored with
   a plain `(STV s c)` get a *derived* CTV at rule-fire time:
   - pos = `(STV s c)`
   - neg = `HeuristicNegativeBranchFormula(baserate(antecedent),
     baserate(consequent), (STV s c))` where
     `NegativeBranchStrength(sa,sb,sb_a) = sb if sa>=1 else
     clamp((sb - sa*sb_a)/(1-sa), 0, 1)` and
     `neg conf = 0.25*min(ca, cb, c)`.
   - base rate of a pattern = weighted fold over all facts matching it:
     `wsum = sum(s*c)`, `csum = sum(c)`, result
     `(wsum/csum, csum/(csum+800))`; no matches => no-evidence, which
     `ImplicationCTVFormula` coerces to `(STV 0.0 0.0)`.
3. **`confidence-to-count` parity:** PeTTa uses
   `c*800/(1 - min(c, 0.9999))` (chainer_utils.metta:149). MORK's
   `pln_confidence_to_count` uses `8e6` for `c>=1` (same value) but diverges
   for `c` in `(0.9999, 1)`. Unify MORK's helper to the PeTTa formula.
4. **MM2 execution model** (from MORK space.rs / sinks.rs): one exec fires per
   step; execs run in lexicographic priority order (`0,1,3,4,...,B,C,Z`); the
   `Z` loop re-seeds all `exec-template`s each round. Each output template of
   a firing exec gets its own sink instance (grouped aggregation happens
   within one firing). Store data may contain variables; conjunct patterns
   unify data-with-vars against ground facts (this is how `Goal`/`ruleN`
   matching already works — MORK commit e551924).

## Design

### 1. MORK pure ops (kernel/src/pure.rs)

Next to `pln_and_confidence_f64`:

- `pln_negative_branch_strength_f64(sa, sb, sb_a)` — NegativeBranchStrength.
- `pln_mp_strength_f64(as, bs_a, bs_na)` — `bs_a*as + bs_na*(1-as)`.
- `pln_mp_confidence_f64(as, ac, bs_a, bc_a, bs_na, bc_na)` —
  ideal-mp-confidence, sharing the existing `pln_ideal_var` /
  `pln_ideal_conf_from_var` helpers.
- Change `pln_confidence_to_count` to `800*c/(1 - min(c,0.9999))` (c<=0 -> 0).

Register all in `register()`.

### 2. MORK base-rate fold sink (kernel/src/sinks.rs)

`fold-base-rate` sink, modeled on ReviseProofsSink. Input rows
`(fold-base-rate $patQ $old $stv)` grouped by `$patQ` (an *uninstantiated*
pattern copy — stays constant across rows). Finalize per group: weighted base
rate over the `$stv` rows; if result != `$old`, remove `(base-rate patQ old)`
and add `(base-rate patQ new)`. No rows for a pattern => value untouched.
Zero evidence (`csum<=0`) keeps `(0.0 0.0)`.

### 3. mm2 runtime

`ruleN` rule-TV field becomes structured (arity stays 3 payload args):

- `(ruleN $g (ctv ($s+ $c+) ($s- $c-)) $premises)` — explicit CTV.
- `(ruleN $g (stv $s $c (brpat $ante $cons)) $premises)` — plain STV rule;
  `$ante`/`$cons` are pattern copies with variables *independent* of
  `$g`/`$premises` (so goal unification never instantiates them). They key
  the base-rate relation.
- `adapterN` (identity) unchanged.

Base-rate maintenance (new `runtime/parts/05_baserate.mm2`, priority 2 so
values are fresh before premise/application execs at 3/4):

```mm2
; (base-rate-def $patQ $patM): static, emitted by the compiler per STV rule
;   ($patQ and $patM are two copies of the same pattern with disjoint vars).
; (base-rate $patQ $stv): maintained value, seeded (0.0 0.0) by the compiler.
(exec-template
  (exec 2
        (, (base-rate-def $patQ $patM)
           (base-rate $patQ $old)
           (fact $patM $stv))
        (O (fold-base-rate $patQ $old $stv))))
```

Scheduler (00_frontier): two `ruleN` variants (priority key from `$c+` resp.
`$c`); `pendingN`/`wait-premises` carry the structured rule TV through
unchanged; premise folding (AndFormula) unchanged.

Application (10_premises), replacing the single `($rule-s $rule-c)` pnil case:

- ctv case: `pure` open-proof with `pln_mp_strength_f64` /
  `pln_mp_confidence_f64`.
- stv case: additionally matches `(base-rate $ante ($ba-s $ba-c))` and
  `(base-rate $cons ($bb-s $bb-c))` (non-consuming), computes
  `bs_na = pln_negative_branch_strength_f64(ba-s, bb-s, s)`,
  `bc_na = product_f64(0.25, min_f64(ba-c, bb-c, c))`, then mp as above.
- identity (adapterN) case unchanged.

### 4. Compiler backend (compiler/petta_mm2_backend.metta)

- `(: name (Implication (Premises p...) (Conclusions c)) (STV s c))` ->
  `(ruleN c' (stv s c (brpat ante cons)) (pcons p ... pnil))` plus
  `(base-rate-def ante anteM)`, `(base-rate ante (0.0 0.0))`, ditto cons.
  `ante` = single premise or `(And p...)` for multi (seq2expr parity).
- Same with `(CTV (STV ..)(STV ..))` -> `(ruleN c' (ctv (..) (..)) ...)`.
- Atomic (non-And, non-Implication) query -> `(, (Goal <term>))` seed.

### 5. Migration + expected values

Rewrite authored `(ruleN g s c prems)` in rules/, demos/, tests/ to
`(ctv (s c) (0.0 1.0))` (the shape PeTTa tests author). Recompute every
expected TV with a Python reference model (scripts or scratchpad) that
mirrors the Rust f64 ops: AndFormula fold, derived CTV, modus ponens, and
`revise_stv` (sinks.rs) for merges. Sanity-check the model by reproducing
already-passing values (`0.9998000399670116` for 2 exact premises,
`0.999700089898053` for 3, and the expected `0.8999998649685302` for this
port) before regenerating the rest.

### 6. New test (tests/test_runtime.sh)

`run_reference_stv_implication_test`: compile the PeTTa source through the
backend (like `run_reference_nary_conjunction_test` does with `petta`),
build the runtime, run, assert `(fact (B x) (0.6 0.8999998649685302))`.

## Risks / open questions

- Variable-vs-variable unification for `(base-rate $ante ...)` matching
  (data pattern against data pattern) — validate early with a micro .mm2
  experiment before building everything on it.
- Structurally different but unifiable patterns (e.g. `(P $x $y)` vs
  `(P $x c)`) would cross-match base-rate keys; acceptable for now.
- Sink no-op when recomputed value equals old (avoid churn) — compare bytes
  in finalize.
- `outputs/` contains stale generated files; regenerate via scripts.

## How to run

```bash
bash tests/test_runtime.sh          # full regression suite (needs `petta` + `mork` on PATH)
cd ../../MORK && cargo build --release -p mork && cp target/release/mork ~/.cargo/bin/
```
