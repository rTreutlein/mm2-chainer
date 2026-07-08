; generated from PeTTaChainer tests/test_backward_dag_helpers.metta by convert_petta_tests.py
!(import! &self /nexus/Dev/OpenCog/NL2PLN_Project/mm2-chainer/compiler/mm2_chainer)
!(mm2-init)
!(mm2-test-tv-confidence (STV 0.7 0.35) 0.35)
!(mm2-test-tv-confidence maybeUnknown 1.0)
!(mm2-test-tv-confidence (CTV (STV 0.9 0.7) (STV 0.1 0.4)) 0.4)
!(mm2-test-term-confidence-CTVModusPonensFormula (STV 0.8 0.9) (CTV (STV 1.0 0.6) (STV 0.0 0.4)) 0.8999975376989856)
!(mm2-test-CTVModusPonensFormula (STV 0.5 1.0) (CTV (STV 1.0 0.5) (STV 0.1 0.5)) (STV 0.55 0.916683750966784))
!(mm2-test-CTVModusPonensFormula (STV 0.5 1.0) (CTV (STV 0.8 0.6) (STV 0.0 0.0)) (STV 0.4 0.8993337363827603))
!(mm2-test-term-confidence-NotFormula (STV 0.75 0.6) 0.6)
!(mm2-test-term-confidence-AndFormula (STV 0.8 0.4) (STV 0.9 0.7) 0.47929561423062006)
!(mm2-test-term-confidence-OrFormula (STV 0.8 0.4) (STV 0.9 0.7) 0.8322690087859733)
!(mm2-test-OrProjection (STV 0.75 0.9) (STV 0.5 1.0) (STV 0.5 0.9))
!(mm2-test-LikelierThanFormula (STV 0.9 0.6) (STV 0.4 0.8) (STV 0.54 0.6))
!(mm2-test-LikelierThanFormula (STV 0.4 0.6) (STV 0.9 0.8) (STV 0.039999999999999994 0.6))
!(mm2-test-term-confidence-LikelierThanFormula (STV 0.8 0.4) (STV 0.9 0.7) 0.4)
!(mm2-test-term-confidence-CTVInversionFormula-vars (CTV (STV 0.8 0.632121) (STV 0.1 0.632121)) 0.5689089)
!(mm2-test-CTVInversionFormula (STV 0.2 1.0) (STV 0.24 1.0) (CTV (STV 0.8 1.0) (STV 0.1 1.0)) (CTV (STV 0.6666666666666669 0.9985188611281907) (STV 0.05263157894736841 0.9999538033069306)))
!(mm2-test-CTVInversionFormula (STV 0.0 1.0) (STV 0.1 1.0) (CTV (STV 0.8 1.0) (STV 0.1 1.0)) (CTV (STV 0.0 0.993640649761643) (STV 0.0 0.9999950617533683)))
; UNSUPPORTED test form: (test (premises-expected-confidence (cons (CPU CTVModusPonensFormula ((STV 1.0 1.0) (CTV (STV 1.0 0.2) (STV 0.0 1.0))) $tv1) (cons (CPU CTVModusPonensFormula ($
!(mm2-test-unsupported "test  premises-expected-confidence  cons  CPU CTVModusPonensFormula   STV 1.0 1")
; UNSUPPORTED test form: (test (premises-expected-confidence (cons (CPU CTVModusPonensFormula ((STV 0.25 1.0) (CTV (STV 1.0 0.8) (STV 0.0 1.0))) $tv) ())) 0.9998999264084577)
!(mm2-test-unsupported "test  premises-expected-confidence  cons  CPU CTVModusPonensFormula   STV 0.25")
; UNSUPPORTED test form: (test (premises-expected-confidence (cons (CPU NotFormula ((STV 0.75 1.0)) $not-tv) (cons (CPU CTVModusPonensFormula ($not-tv (CTV (STV 1.0 0.8) (STV 0.0 0.0)))
!(mm2-test-unsupported "test  premises-expected-confidence  cons  CPU NotFormula   STV 0.75 1.0   $not-")
; UNSUPPORTED test form: (test (premises-expected-confidence (cons ((Creature $c) (kb MAIN Nil) $prfC $tvB) (cons (CPU FoldAllCompiled (kb (Animal $a) extract-tv (BaseRateEvidence 0.0 0
!(mm2-test-unsupported "test  premises-expected-confidence  cons   Creature $c   kb MAIN Nil  $prfC $tv")
!(mm2-compileadd inverseTotalKb (: inverseTotalRule (Implication (Premises (InverseTotalA)) (Conclusions (InverseTotalB))) (CTV (STV 0.8 0.9) (STV 0.1 0.9))))
; UNSUPPORTED test form: (test (collapse (once (match rules ($id ((InverseTotalA) (inverseTotalKb $ctx $vars) ((inverted inverseTotalRule with cpu cpu) $prfb-wit) $mp-tv) (((InverseTota
!(mm2-test-unsupported "test  collapse  once  match rules  $id   InverseTotalA   inverseTotalKb $ctx $v")
; UNSUPPORTED test form: (test (let* (($heap0 (empty_heap)) ($heap1 (add_to_heap $heap0 3.0 low)) ($heap2 (add_to_heap $heap1 1.0 high)) ($heap3 (add_to_heap $heap2 2.0 mid)) ($pruned (
!(mm2-test-unsupported "test  let    $heap0  empty_heap    $heap1  add_to_heap $heap0 3.0 low    $heap2")
; UNSUPPORTED test form: (test (let* (($heap0 (empty_heap)) ($heap1 (add_to_heap $heap0 1.0 high)) ($heap2 (add_to_heap $heap1 2.0 low)) ($kept (bounded-agenda-prune 1 $heap2))) (heap_s
!(mm2-test-unsupported "test  let    $heap0  empty_heap    $heap1  add_to_heap $heap0 1.0 high    $heap")
; UNSUPPORTED test form: (test (let* (($heap0 (empty_heap)) ($heap1 (add_to_heap $heap0 1.0 high)) ($empty (bounded-agenda-prune 0 $heap1))) (heap_size $empty)) 1)
!(mm2-test-unsupported "test  let    $heap0  empty_heap    $heap1  add_to_heap $heap0 1.0 high    $empt")
; UNSUPPORTED test form: (test (let* (($heap0 (empty_heap)) ($heap1 (add_to_heap $heap0 1.0 high)) ($_disable (set-bounded-agenda-pruning false)) ($kept (bounded-agenda-prune 0 $heap1))
!(mm2-test-unsupported "test  let    $heap0  empty_heap    $heap1  add_to_heap $heap0 1.0 high    $_dis")
(= (clear-backward-state) (progn (foreach-flat remove-all-atoms (() &goal &goal_lookup &goal_waiter &aggregate &proof &proof_live_cache &goal_live_cache &proof_static_live)) (change-state! bwd_live_epoch 0) ()))
; UNSUPPORTED test form: (test (let* (($_clear (clear-backward-state)) ($_gidreset (change-state! bwd_gid 0)) ($open-a (ensure-goal-at-depth ((Pet $a) (kb MAIN ()) $prf $tv) 0)) ($open-
!(mm2-test-unsupported "test  let    $_clear  clear-backward-state    $_gidreset  change-state  bwd_gid")
; UNSUPPORTED test form: (test (let* (($_clear (clear-backward-state)) ($_gidreset (change-state! bwd_gid 0)) ($_pidreset (change-state! bwd_pid 0)) ($gid (ensure-goal-at-depth ((Goal) 
!(mm2-test-unsupported "test  let    $_clear  clear-backward-state    $_gidreset  change-state  bwd_gid")
; UNSUPPORTED test form: (test (let* (($_clear (clear-backward-state)) ($_gidreset (change-state! bwd_gid 0)) ($_pidreset (change-state! bwd_pid 0)) ($gid (ensure-goal-at-depth ((Goal) 
!(mm2-test-unsupported "test  let    $_clear  clear-backward-state    $_gidreset  change-state  bwd_gid")
; UNSUPPORTED test form: (test (let* (($_clear (clear-backward-state)) ($_gidreset (change-state! bwd_gid 0)) ($_pidreset (change-state! bwd_pid 0)) ($gid (ensure-goal-at-depth ((Goal) 
!(mm2-test-unsupported "test  let    $_clear  clear-backward-state    $_gidreset  change-state  bwd_gid")
; UNSUPPORTED test form: (test (proof-term-children-mode proof-walk-plain (custom-proof left right)) ())
!(mm2-test-unsupported "test  proof-term-children-mode proof-walk-plain  custom-proof left right")
; UNSUPPORTED test form: (test (once (proof-term-evidence-list-mode proof-walk-plain (own_have (fact-ev (kb MAIN ()) i_have_max (Have (i max)))))) ((own_have (fact-ev (kb MAIN ()) i_hav
!(mm2-test-unsupported "test  once  proof-term-evidence-list-mode proof-walk-plain  own_have  fact-ev")
; UNSUPPORTED test form: (test (let* (($_clear (clear-backward-state)) ($_gidreset (change-state! bwd_gid 0)) ($_pidreset (change-state! bwd_pid 0)) ($agg-gid (ensure-goal-at-depth (CPU
!(mm2-test-unsupported "test  let    $_clear  clear-backward-state    $_gidreset  change-state  bwd_gid")
; UNSUPPORTED test form: (test (let* (($_clear (clear-backward-state)) ($_gidreset (change-state! bwd_gid 0)) ($_pidreset (change-state! bwd_pid 0)) ($agg-gid (ensure-goal-at-depth (CPU
!(mm2-test-unsupported "test  let    $_clear  clear-backward-state    $_gidreset  change-state  bwd_gid")
; UNSUPPORTED test form: (test (let* (($_clear (clear-backward-state)) ($_gidreset (change-state! bwd_gid 0)) ($_pidreset (change-state! bwd_pid 0)) ($agg-gid (ensure-goal-at-depth (CPU
!(mm2-test-unsupported "test  let    $_clear  clear-backward-state    $_gidreset  change-state  bwd_gid")
