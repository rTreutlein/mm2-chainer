; generated from PeTTaChainer tests/test_distribution_values.metta by convert_petta_tests.py
; FoldAllValue distribution-query subset; downstream GreaterThan rule checks are not generated yet
!(import! &self /nexus/Dev/OpenCog/NL2PLN_Project/mm2-chainer/compiler/mm2_chainer)
!(mm2-init)
!(mm2-test-ParticlePairs (ParticleAddBernoulliFromSTV (ParticleFromPairs ((0 1.0))) (STV 0.5 1.0)) ((0 0.5) (1 0.5)))
!(mm2-test-DistGreaterThanFormula (ParticleFromPairs ((0.1 0.25) (2.5 0.75))) 1.0 (STV 0.75 0.07407407407407407))
!(mm2-compileadd kb (: kid1 (Kid kid1) (STV 1.0 1.0)))
!(mm2-compileadd kb (: kid2 (Kid kid2) (STV 1.0 1.0)))
!(mm2-compileadd kb (: room1 (Room room1) (STV 1.0 1.0)))
!(mm2-compileadd kb (: room2 (Room room2) (STV 1.0 1.0)))
!(mm2-compileadd kb (: in11 (In room1 kid1) (STV 0.5 1.0)))
!(mm2-compileadd kb (: in12 (In room1 kid2) (STV 0.5 1.0)))
!(mm2-compileadd kb (: in21 (In room2 kid1) (STV 0.2 1.0)))
!(mm2-compileadd kb (: in22 (In room2 kid2) (STV 0.3 1.0)))
!(mm2-compileadd kb (: cntKidInRule (Implication (Premises (Room $room) (FoldAllValue (In $room $kid) (ParticleFromPairs ((0 1.0))) ParticleAddBernoulliFromSTV -> $dist)) (Conclusions (CntKidIn $room $dist))) (CTV (STV 1.0 0.8) (STV 0.0 1.0))))
; OMITTED downstream GreaterThan rule over FoldAllValue output: (compileadd kb (: playTogetherRule (Implication (Premises (Room $room) (CntKidIn $room $cnt) (GreaterThan $cnt 1)) (Conclusions (PlayTogetherIn $room))) (CTV (S
!(mm2-test-query-particle-pairs-between 40 kb (: $prf (CntKidIn room1 $cnt) $tv) ((0 0.2499 0.2501) (1 0.4999 0.5001) (2 0.2499 0.2501)))
!(mm2-test-query-particle-pairs-between 40 kb (: $prf (CntKidIn room2 $cnt) $tv) ((0 0.5599 0.5601) (1 0.3799 0.3801) (2 0.0599 0.0601)))
; Remaining source forms start at CTVMP helper coverage over FoldAllValue distributions and are intentionally omitted here.
