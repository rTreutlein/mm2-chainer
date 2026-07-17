; generated from PeTTaChainer tests/test_foldall_merged_outputs.metta by convert_petta_tests.py
!(import! &self /nexus/Dev/OpenCog/NL2PLN_Project/mm2-chainer/compiler/mm2_chainer)
!(mm2-init)
!(mm2-compileadd foldMergedKb (: directScore (Score a 1) (STV 0.8 0.5)))
!(mm2-compileadd foldMergedKb (: qFact (Q a) (STV 1.0 0.9)))
!(mm2-compileadd foldMergedKb (: qToScore (Implication (Premises (Q $x)) (Conclusions (Score $x 1))) (CTV (STV 0.4 0.9) (STV 0.0 1.0))))
!(mm2-test-query 100 foldMergedKb (: $prf (Score a 1) $tv) ((: (merge/revision (qToScore qFact) directScore) (Score a 1) (STV 0.44000002400830773 0.9090908594869702))))
; UNSUPPORTED test form: (test (let (: $proof (FoldAll $pattern $extractor $init $_fold-function -> $total) $tv) (car-atom (collapse (query 100 foldMergedKb (: $prf (FoldAll (Score $x $
!(mm2-test-unsupported "test  let    $proof  FoldAll $pattern $extractor $init $_fold-function -  $tota")
