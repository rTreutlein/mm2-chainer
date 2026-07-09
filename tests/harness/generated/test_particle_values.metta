; generated from PeTTaChainer tests/test_particle_values.metta by convert_petta_tests.py
; direct distribution-helper subset; FoldAllValue/query particle semantics are not generated yet
!(import! &self /nexus/Dev/OpenCog/NL2PLN_Project/mm2-chainer/compiler/mm2_chainer)
!(mm2-init)
!(mm2-test-DistGreaterThanFormula (ParticleFromPairs ((0 0.25) (2 0.75))) 1 (STV 0.75 0.07407407407407407))
!(mm2-test-DistGreaterThanFormula (let* (($pd0 (ParticleFromPairs ((0 1.0)))) ($pd1 (ParticleAddBernoulliFromSTV $pd0 (STV 0.5 1.0))) ($pd2 (ParticleAddBernoulliFromSTV $pd1 (STV 0.5 1.0)))) $pd2) 1 (STV 0.25 0.1176470588235294))
!(mm2-test-ParticlePairs (ParticleFromPairs ((170 0.5) (180 0.5))) ((170 0.5) (180 0.5)))
!(mm2-test-ParticlePairs (ParticleFromPairs ((175 1.0))) ((175 1.0)))
!(mm2-test-DistGreaterThanDistFormula (ParticleFromPairs ((170 0.5) (180 0.5))) (ParticleFromPairs ((175 1.0))) (STV 0.5 0.047619047619047616))
!(mm2-test-DistGreaterThanFormula (ParticleMap (|-> ($x) (+ $x 1)) (ParticleFromPairs ((0 0.25) (2 0.75)))) 2 (STV 0.75 0.07407407407407407))
!(mm2-test-DistGreaterThanFormula (ParticleMap2 + (ParticleFromPairs ((170 0.5) (180 0.5))) (ParticleFromPairs ((160 1.0)))) 335 (STV 0.5 0.09090909090909091))
!(mm2-test-DistGreaterThanFormula (ParticleMap2 (|-> ($a $b) (/ (+ $a $b) 2)) (ParticleFromPairs ((180 1.0))) (ParticleFromPairs ((160 1.0)))) 169 (STV 1.0 0.047619047619047616))
; Remaining source forms start at compileadd/FoldAllValue query coverage and are intentionally omitted here.
