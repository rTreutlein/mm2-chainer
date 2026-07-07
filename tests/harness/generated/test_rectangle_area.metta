; generated from PeTTaChainer tests/test_rectangle_area.metta by convert_petta_tests.py
!(import! &self /nexus/Dev/OpenCog/NL2PLN_Project/mm2-chainer/compiler/mm2_chainer)
!(mm2-init)
!(mm2-compileadd kb (: rA (Rectangle rectA) (STV 1.0 1.0)))
!(mm2-compileadd kb (: rB (Rectangle rectB) (STV 1.0 1.0)))
!(mm2-compileadd kb (: lenA (LengthDist rectA (ParticleFromNormal 10.0 1.0)) (STV 1.0 1.0)))
!(mm2-compileadd kb (: widA (WidthDist rectA (ParticleFromNormal 5.0 0.5)) (STV 1.0 1.0)))
!(mm2-compileadd kb (: lenB (LengthDist rectB (PointMass 8.0)) (STV 1.0 1.0)))
!(mm2-compileadd kb (: widB (WidthDist rectB (PointMass 4.0)) (STV 1.0 1.0)))
!(mm2-compileadd kb (: areaDistRule (Implication (Premises (Rectangle $rect) (Map2Dist * (LengthDist $rect $lengthDist) $lengthDist (WidthDist $rect $widthDist) $widthDist -> $areaDist)) (Conclusions (AreaDist $rect $areaDist))) (CTV (STV 1.0 1.0) (STV 0.0 1.0))))
; UNSUPPORTED test form: (test (let (: $prf (AreaDist rectA $areaDist) $tv) (query 20 kb (: $prf (AreaDist rectA $areaDist) $tv)) (let (STV $s $c) (DistGreaterThanFormula $areaDist 50.0
!(mm2-test-unsupported "test  let    $prf  AreaDist rectA $areaDist  $tv   query 20 kb    $prf  AreaDis")
; UNSUPPORTED test form: (test (let (: $prf (AreaDist rectB $areaDist) $tv) (query 20 kb (: $prf (AreaDist rectB $areaDist) $tv)) (let (STV $s $c) (DistGreaterThanFormula $areaDist 31.0
!(mm2-test-unsupported "test  let    $prf  AreaDist rectB $areaDist  $tv   query 20 kb    $prf  AreaDis")
; UNSUPPORTED test form: (test (let (: $prf (AreaDist rectA $areaDist) $tv) (query 20 kb (: $prf (AreaDist rectA $areaDist) $tv)) (let (STV $s $c) (DistGreaterThanFormula $areaDist 10.0
!(mm2-test-unsupported "test  let    $prf  AreaDist rectA $areaDist  $tv   query 20 kb    $prf  AreaDis")
