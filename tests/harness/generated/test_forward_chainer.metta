; generated from PeTTaChainer tests/test_forward_chainer.metta by convert_petta_tests.py
; forward materialization subset; PeTTa agenda/proof-store internals are documented omissions
!(import! &self /nexus/Dev/OpenCog/NL2PLN_Project/mm2-chainer/compiler/mm2_chainer)
!(mm2-init)
!(mm2-compileadd fwdkb (: edgeAB (Edge A B) (STV 1.0 1.0)))
!(mm2-compileadd fwdkb (: edgeBC (Edge B C) (STV 1.0 1.0)))
!(mm2-compileadd fwdkb (: edgeToPath (Implication (Premises (Edge $x $y)) (Conclusions (Path $x $y))) (CTV (STV 1.0 1.0) (STV 0.0 1.0))))
!(mm2-compileadd fwdkb (: pathStep (Implication (Premises (Path $x $y) (Edge $y $z)) (Conclusions (Path $x $z))) (CTV (STV 1.0 1.0) (STV 0.0 1.0))))
!(mm2-compileadd fwdkb (: pathIdempotent (Implication (Premises (Path $x $y)) (Conclusions (Path $x $y))) (CTV (STV 1.0 1.0) (STV 0.0 1.0))))
!(mm2-test-forward-has-derived 50 fwdkb (Path A C) true)
; ADAPTED PeTTa forward proof-count check: MM2 checks materialized fact count
!(mm2-test-forward-fact-count 50 fwdkb (Path A C) 1)
!(mm2-compileadd loopkb (: seedLoop (Loop Start) (STV 1.0 1.0)))
!(mm2-compileadd loopkb (: keepLoop (Implication (Premises (Loop $x)) (Conclusions (Loop $x))) (CTV (STV 1.0 1.0) (STV 0.0 1.0))))
; ADAPTED PeTTa forward proof-count check: MM2 checks materialized fact count
!(mm2-test-forward-fact-count 200 loopkb (Loop Start) 1)
!(mm2-compileadd mergekb (: weakFact (WeakPremise) (STV 1.0 0.1)))
!(mm2-compileadd mergekb (: baseFact (BasePremise) (STV 1.0 1.0)))
!(mm2-compileadd mergekb (: ruleHighThenDrop (Implication (Premises (WeakPremise) (BasePremise)) (Conclusions (SwitchGoal))) (CTV (STV 1.0 0.9) (STV 0.0 1.0))))
!(mm2-compileadd mergekb (: ruleStable (Implication (Premises (BasePremise)) (Conclusions (SwitchGoal))) (CTV (STV 1.0 0.7) (STV 0.0 1.0))))
; OMITTED PeTTa forward proof-token merge-shape check: (test (let* (($_ (forward-chain 50 mergekb)) ($merged (collapse (match &kb ((SwitchGoal) (mergekb MAIN Nil) (merge/revision $p1 $p2) $tv) true)))) (== $merged (
; OMITTED PeTTa forward proof-store evidence check: (test (let* (($_ (forward-chain 50 mergekb)) ($ev-ok (collapse (match &kb ((SwitchGoal) (mergekb MAIN Nil) $prf $tv) (== (proof-atom-evidence-set ((SwitchGoal)
; ADAPTED PeTTa forward proof-count check: MM2 checks materialized fact count
!(mm2-test-forward-fact-count 50 mergekb (SwitchGoal) 1)
!(mm2-compileadd deltakb (: highFact (HighPriority) (STV 1.0 1.0)))
!(mm2-compileadd deltakb (: lowFact (LowPriority) (STV 1.0 0.8)))
!(mm2-compileadd deltakb (: lowToGoal (Implication (Premises (LowPriority)) (Conclusions (DeltaGoal))) (CTV (STV 1.0 1.0) (STV 0.0 1.0))))
; OMITTED PeTTa one-agenda-pop forward budget check: (test (let $_ (forward-chain 1 deltakb) (forward-has-derived? deltakb (DeltaGoal))) false)
!(mm2-test-forward-has-derived 1 deltakb (DeltaGoal) true)
!(mm2-compileadd selectedkb (: highFact (HighPriority) (STV 1.0 1.0)))
!(mm2-compileadd selectedkb (: lowFact (LowPriority) (STV 1.0 0.8)))
!(mm2-compileadd selectedkb (: lowToGoal (Implication (Premises (LowPriority)) (Conclusions (SelectedGoal))) (CTV (STV 1.0 1.0) (STV 0.0 1.0))))
; ADAPTED PeTTa selected forward agenda check: MM2 checks materialization after a whole-KB forward pass
!(mm2-test-forward-has-derived 1 selectedkb (SelectedGoal) true)
!(mm2-compileadd factseedkb (: highFact (HighPriority) (STV 1.0 1.0)))
!(mm2-compileadd factseedkb (: lowFact (LowPriority) (STV 1.0 0.8)))
!(mm2-compileadd factseedkb (: lowToGoal (Implication (Premises (LowPriority)) (Conclusions (FactSeedGoal))) (CTV (STV 1.0 1.0) (STV 0.0 1.0))))
; ADAPTED PeTTa fact-seeded forward agenda check: MM2 checks materialization after a whole-KB forward pass
!(mm2-test-forward-has-derived 1 factseedkb (FactSeedGoal) true)
!(mm2-compileadd ruleaddkb (: oldSeed (RuleSeed) (STV 1.0 1.0)))
!(mm2-test-forward-has-derived 1 ruleaddkb (RuleAddGoal) false)
!(mm2-compileadd ruleaddkb (: seedToGoal (Implication (Premises (RuleSeed)) (Conclusions (RuleAddGoal))) (CTV (STV 1.0 1.0) (STV 0.0 1.0))))
!(mm2-test-forward-has-derived 2 ruleaddkb (RuleAddGoal) true)
!(mm2-compileadd dedupekb (: dedupeSeed (DedupeSeed) (STV 1.0 0.4)))
!(mm2-compileadd dedupekb (: dedupeRule (Implication (Premises (DedupeSeed)) (Conclusions (DedupeGoal))) (CTV (STV 1.0 0.5) (STV 0.0 1.0))))
; ADAPTED PeTTa forward agenda dirty-state check: MM2 checks that forward goals are registered
!(mm2-test-forward-has-goals dedupekb true)
; ADAPTED PeTTa forward CPU-placeholder cleanup check: MM2 checks the materialized output fact
!(mm2-test-forward-has-derived 10 dedupekb (DedupeGoal) true)
