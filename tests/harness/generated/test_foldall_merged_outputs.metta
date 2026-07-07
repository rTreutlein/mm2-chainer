; generated from PeTTaChainer tests/test_foldall_merged_outputs.metta by convert_petta_tests.py
!(import! &self /nexus/Dev/OpenCog/NL2PLN_Project/mm2-chainer/compiler/mm2_chainer)
!(mm2-init)
!(mm2-compileadd foldMergedKb (: directScore (Score a 1) (STV 0.8 0.5)))
!(mm2-compileadd foldMergedKb (: qFact (Q a) (STV 1.0 0.9)))
!(mm2-compileadd foldMergedKb (: qToScore (Implication (Premises (Q $x)) (Conclusions (Score $x 1))) (CTV (STV 0.4 0.9) (STV 0.0 1.0))))
!(mm2-test (mm2-query 100 foldMergedKb (: $prf (Score a 1) $tv)) ((: (merge/revision (qToScore qFact) directScore) (Score a 1) (STV 0.44000002400830773 0.9090908594869702))))
!(mm2-test (mm2-query 100 foldMergedKb (: $prf (FoldAll (Score $x $n) $n 0 (|-> ($acc $elem) (+ $acc $elem)) -> $total) $tv)) ((: (foldall-proof (merge/revision (qToScore qFact) directScore)) (FoldAll (Score $_x $_n) $_n 0 lambda_17 -> 1) (STV 1.0 1.0))))
