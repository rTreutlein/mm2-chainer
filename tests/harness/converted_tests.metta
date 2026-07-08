!(import! &self /nexus/Dev/OpenCog/NL2PLN_Project/mm2-chainer/compiler/mm2_chainer)
!(mm2-init)

; test_stv_implication_derived_ctv.metta
!(mm2-compileadd stvRuleKb (: a (A x) (STV 1.0 0.9)))
!(mm2-compileadd stvRuleKb
   (: aToB (Implication (Premises (A $x)) (Conclusions (B $x))) (STV 0.6 0.9)))
!(mm2-test-query 20 stvRuleKb (: $prf (B x) $tv)
                 ((: $_ (B x) (STV 0.6 0.8999998649685302))))

; test_nary_conjuction.metta
!(mm2-compileadd nAryKb (: a A (STV 1.0 1.0)))
!(mm2-compileadd nAryKb (: b B (STV 1.0 1.0)))
!(mm2-compileadd nAryKb (: c C (STV 1.0 1.0)))
!(mm2-test-query 20 nAryKb (: $prf (And A B C) $tv)
                 ((: $_ (And A B C) (STV 1.0 0.999700089898053))))

; PLN Or All adapter: both children are required, then folded with OrFormula.
!(mm2-compileadd orAllKb (: oa OA (STV 0.7 0.8)))
!(mm2-compileadd orAllKb (: ob OB (STV 0.5 0.9)))
!(mm2-test-query 20 orAllKb (: $prf (Or OA OB) $tv)
                 ((: $_ (Or OA OB) (STV 0.85 0.8908311399639481))))

; Distribution bridge: concrete PeTTa ParticleDist facts expose their pairs to
; the MORK runtime for later MapDist/Map2Dist/AverageDist support.
!(let $pd (PointMass 3.0)
   (let $_ (mm2-compileadd distBridgeKb (: pm (DistHolder $pd) (STV 1.0 1.0)))
      (mm2-test-equal (mm2-dist-pairs $pd) ((3.0 1.0)))))

; Map2Dist *: derive a deterministic output distribution from two point masses
; and materialize the result pair through the MORK fsum sink.
!(let $len (PointMass 8.0)
   (let $wid (PointMass 4.0)
      (let $_r (mm2-compileadd distMap2Kb (: r (Rectangle rectB) (STV 1.0 1.0)))
        (let $_l (mm2-compileadd distMap2Kb (: len (LengthDist rectB $len) (STV 1.0 1.0)))
          (let $_w (mm2-compileadd distMap2Kb (: wid (WidthDist rectB $wid) (STV 1.0 1.0)))
            (let $_rule
              (mm2-compileadd distMap2Kb
                (: areaRule
                   (Implication
                     (Premises
                       (Rectangle $rect)
                       (Map2Dist *
                         (LengthDist $rect $lengthDist)
                         $lengthDist
                         (WidthDist $rect $widthDist)
                         $widthDist
                         ->
                         $areaDist))
                     (Conclusions (AreaDist $rect $areaDist)))
                   (CTV (STV 1.0 1.0) (STV 0.0 1.0))))
              (let $out (ParticleDist (dist-map2 * $len $wid) 1.0)
                (let $_q
                  (mm2-test-query 20 distMap2Kb (: $prf (AreaDist rectB $areaDist) $tv)
                    ((: $_ (AreaDist rectB $out) (STV 1.0 0.999700089898053))))
                  (let $_run (mm2-exec &mork 200)
                    (mm2-test-equal (mm2-dist-pairs $out) ((32.0 1))))))))))))

; test_implication_inversion.metta
!(mm2-compileadd invKb (: r (Implication (Premises (P $x)) (Conclusions (Q $x))) (CTV (STV 0.8 0.9) (STV 0.1 0.9))))
!(mm2-compileadd invKb (: qa (Q alice) (STV 0.9 0.8)))
!(mm2-compileadd invKb (: pb (P bob) (STV 0.7 0.8)))
!(mm2-test-query 240 invKb (: $prf (P alice) $tv)
                 ((: $_ (P alice) (STV 0.736162240263287 0.0003604307138536469))))

; kb isolation: stvRuleKb facts must not leak into nAryKb
!(mm2-test-query 5 nAryKb (: $prf (B x) $tv) ())
