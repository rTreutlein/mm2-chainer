; generated from PeTTaChainer tests/test_height_average.metta by convert_petta_tests.py
!(import! &self /nexus/Dev/OpenCog/NL2PLN_Project/mm2-chainer/compiler/mm2_chainer)
!(mm2-init)
!(mm2-compileadd kb (: group1 (Group g1) (STV 1.0 1.0)))
!(mm2-compileadd kb (: group2 (Group g2) (STV 1.0 1.0)))
!(mm2-compileadd kb (: hd11 (HeightDist g1 alice (PointMass 160.0)) (STV 1.0 1.0)))
!(mm2-compileadd kb (: hd12 (HeightDist g1 bob (PointMass 170.0)) (STV 1.0 1.0)))
!(mm2-compileadd kb (: hd13 (HeightDist g1 carol (PointMass 180.0)) (STV 1.0 1.0)))
!(mm2-compileadd kb (: hd21 (HeightDist g2 dan (ParticleFromNormal 150.0 2.0)) (STV 1.0 1.0)))
!(mm2-compileadd kb (: hd22 (HeightDist g2 erin (ParticleFromNormal 170.0 2.0)) (STV 1.0 1.0)))
!(mm2-compileadd kb (: hd23 (HeightDist g2 frank (ParticleFromNormal 175.0 1.0)) (STV 1.0 1.0)))
!(mm2-compileadd kb (: avgHeightDistRule (Implication (Premises (Group $g) (AverageDist (HeightDist $g $person $hdist) $hdist -> $avgDist)) (Conclusions (AvgHeightDist $g $avgDist))) (CTV (STV 1.0 1.0) (STV 0.0 1.0))))
; UNSUPPORTED test form: (test (let (: $prf (AvgHeightDist g1 $avgDist) $tv) (query 20 kb (: $prf (AvgHeightDist g1 $avgDist) $tv)) (let (STV $s $c) (DistGreaterThanFormula $avgDist 170
!(mm2-test-unsupported (test (let (: $prf (AvgHeightDist g1 $avgDist) $tv) (query 2)
; UNSUPPORTED test form: (test (let (: $prf (AvgHeightDist g1 $avgDist) $tv) (query 20 kb (: $prf (AvgHeightDist g1 $avgDist) $tv)) (let (STV $s $c) (DistGreaterThanFormula $avgDist 169
!(mm2-test-unsupported (test (let (: $prf (AvgHeightDist g1 $avgDist) $tv) (query 2)
; UNSUPPORTED test form: (test (let (: $prf (AvgHeightDist g2 $avgDist) $tv) (query 20 kb (: $prf (AvgHeightDist g2 $avgDist) $tv)) (let (STV $s $c) (DistGreaterThanFormula $avgDist 165
!(mm2-test-unsupported (test (let (: $prf (AvgHeightDist g2 $avgDist) $tv) (query 2)
; UNSUPPORTED test form: (test (let (: $prf (AvgHeightDist g1 $avgDist) $tv) (query 20 kb (: $prf (AvgHeightDist g1 $avgDist) $tv)) (let (STV $s $c) (DistGreaterThanFormula $avgDist 169
!(mm2-test-unsupported (test (let (: $prf (AvgHeightDist g1 $avgDist) $tv) (query 2)
