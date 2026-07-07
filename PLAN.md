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

## Next: convert the corpus + port the real compiler

1. **Convert PeTTaChainer's test corpus** into `tests/harness/` (mechanical:
   `compileadd`->`mm2-compileadd`, `(test (query N kb pat) exp)` ->
   `(mm2-test (mm2-query N kb pat) (exp...))`, expected always as a list,
   skipping forward-chainer/Python/distribution tests). Run for a
   pass/close/FAIL gap list; each FAIL is either a missing statement shape in
   the thin backend or a real runtime gap.
2. **Port the real compiler by IR translation, not rewrite**: PeTTaChainer's
   `mm2compile`/`mm2compileQuery` (compile.metta:877-988) already emit a
   compiled IR — `(rules ($premises |- $conclusion))` with `(CPU Formula args
   out)` premise items — whose current consumer is the MeTTa chainer
   (compiled_query_runtime.metta), *not* MM2. Replace `mm2-compile-add` in the
   harness with: run `mm2compile`, translate IR to mm2 atoms (subgoal premises
   -> pcons list; recognized CPU chains -> ctv/stv/inv rule kinds + brpat;
   unrecognized -> loud `notsupported-ir` marker feeding the gap list).
3. **Base-rate freeze semantics** to eliminate the `close` drift: PeTTa
   caches base rates per (kb, pattern) at first use (base_rate_cache in
   compiled_query_runtime.metta) so all rule firings in a query see one
   value; mm2 recomputes every round and merged facts keep refining.
4. STV-rule inversion still needs the fold recursion guard (see above).

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
