; generated from PeTTaChainer tests/test_distribution_values.metta by convert_petta_tests.py
; direct distribution-helper subset; FoldAllValue/query particle semantics are not generated yet
!(import! &self /nexus/Dev/OpenCog/NL2PLN_Project/mm2-chainer/compiler/mm2_chainer)
!(mm2-init)
!(mm2-test-ParticlePairs (ParticleAddBernoulliFromSTV (ParticleFromPairs ((0 1.0))) (STV 0.5 1.0)) ((0 0.5) (1 0.5)))
!(mm2-test-DistGreaterThanFormula (ParticleFromPairs ((0.1 0.25) (2.5 0.75))) 1.0 (STV 0.75 0.07407407407407407))
; Remaining source forms start at compileadd/FoldAllValue query coverage and are intentionally omitted here.
