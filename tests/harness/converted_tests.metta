!(import! &self /nexus/Dev/OpenCog/NL2PLN_Project/mm2-chainer/compiler/mm2_chainer)
!(mm2-init)

; test_stv_implication_derived_ctv.metta
!(mm2-compileadd stvRuleKb (: a (A x) (STV 1.0 0.9)))
!(mm2-compileadd stvRuleKb
   (: aToB (Implication (Premises (A $x)) (Conclusions (B $x))) (STV 0.6 0.9)))
!(mm2-test-query 20 stvRuleKb (: $prf (B x) $tv)
                 ((: $_ (B x) (STV 0.6 0.8999998649685302))))

; STV inverse materialization should populate the consequent base-rate fold
; with other rules' conclusions while excluding conclusions derived by the
; same STV rule whose CTV is being derived.
!(let $_r
   (mm2-compileadd stvGuardKb
     (: r
        (Implication (Premises (P $x)) (Conclusions (Q $x)))
        (STV 0.8 0.9)))
   (let $_s
     (mm2-compileadd stvGuardKb
       (: s
          (Implication (Premises (R $x)) (Conclusions (Q $x)))
          (CTV (STV 0.9 0.9) (STV 0.0 1.0))))
     (let $_qa (mm2-compileadd stvGuardKb (: qa (Q alice) (STV 0.5 0.8)))
       (let $_pb (mm2-compileadd stvGuardKb (: pb (P bob) (STV 0.3 0.8)))
         (let $_rc (mm2-compileadd stvGuardKb (: rc (R carol) (STV 1.0 0.8)))
           (let $_run (mm2-exec &mork 300)
             (mm2-test-equal
               (collapse
                 (match &mork
                   (base-rate
                     (guarded-base-rate
                       (r $rv)
                       ((stvGuardKb MAIN Nil) (Q $x)))
                     $stv)
                   $stv))
               ((0.7117645040873257 0.002120491681932299)))))))))

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

; AverageDist over point masses.
!(let $_g (mm2-compileadd avgPointKb (: group1 (Group g1) (STV 1.0 1.0)))
   (let $_h1 (mm2-compileadd avgPointKb (: h1 (HeightDist g1 alice (PointMass 160.0)) (STV 1.0 1.0)))
     (let $_h2 (mm2-compileadd avgPointKb (: h2 (HeightDist g1 bob (PointMass 170.0)) (STV 1.0 1.0)))
       (let $_h3 (mm2-compileadd avgPointKb (: h3 (HeightDist g1 carol (PointMass 180.0)) (STV 1.0 1.0)))
         (let $_rule
           (mm2-compileadd avgPointKb
             (: avgRule
                (Implication
                  (Premises
                    (Group $g)
                    (AverageDist (HeightDist $g $person $hdist) $hdist -> $avgDist))
                  (Conclusions (AvgHeightDist $g $avgDist)))
                (CTV (STV 1.0 1.0) (STV 0.0 1.0))))
           (let $out (ParticleDist (dist-average (avgPointKb MAIN Nil) AvgHeightDist g1) 1.0)
             (let $_q
               (mm2-test-query 40 avgPointKb (: $prf (AvgHeightDist g1 $avgDist) $tv)
                 ((: $_ (AvgHeightDist g1 $out) (STV 1.0 1.0))))
               (let $_run (mm2-exec &mork 400)
                 (mm2-test-equal (mm2-dist-pairs $out) ((170 1)))))))))))

; AverageDist over multi-pair inputs: the two ways to produce average 165.0
; must be pooled into one pair with mass 0.5.
!(let $_g (mm2-compileadd avgMultiKb (: group2 (Group g2) (STV 1.0 1.0)))
   (let $_h1 (mm2-compileadd avgMultiKb (: h1 (HeightDist g2 left (ParticleFromPairs ((150.0 0.5) (170.0 0.5)))) (STV 1.0 1.0)))
     (let $_h2 (mm2-compileadd avgMultiKb (: h2 (HeightDist g2 right (ParticleFromPairs ((160.0 0.5) (180.0 0.5)))) (STV 1.0 1.0)))
       (let $_rule
         (mm2-compileadd avgMultiKb
           (: avgRule
              (Implication
                (Premises
                  (Group $g)
                  (AverageDist (HeightDist $g $person $hdist) $hdist -> $avgDist))
                (Conclusions (AvgHeightDist $g $avgDist)))
              (CTV (STV 1.0 1.0) (STV 0.0 1.0))))
         (let $out (ParticleDist (dist-average (avgMultiKb MAIN Nil) AvgHeightDist g2) 1.0)
           (let $_q
             (mm2-test-query 40 avgMultiKb (: $prf (AvgHeightDist g2 $avgDist) $tv)
               ((: $_ (AvgHeightDist g2 $out) (STV 1.0 1.0))))
             (let $_run (mm2-exec &mork 400)
               (mm2-test-equal (mm2-dist-pairs $out) ((155 0.25) (165 0.5) (175 0.25))))))))))

; test_implication_inversion.metta
!(mm2-compileadd invKb (: r (Implication (Premises (P $x)) (Conclusions (Q $x))) (CTV (STV 0.8 0.9) (STV 0.1 0.9))))
!(mm2-compileadd invKb (: qa (Q alice) (STV 0.9 0.8)))
!(mm2-compileadd invKb (: pb (P bob) (STV 0.7 0.8)))
!(mm2-test-query 240 invKb (: $prf (P alice) $tv)
                 ((: $_ (P alice) (STV 0.736162240263287 0.0003604307138536469))))

; Selected MM2 forward materialization opens goals from the selected source
; fact only.
!(mm2-compileadd selectedNegativeKb (: highOnly (HighPriority) (STV 1.0 1.0)))
!(mm2-compileadd selectedNegativeKb (: lowOnly (LowPriority) (STV 1.0 0.8)))
!(mm2-compileadd selectedNegativeKb (: lowToGoal (Implication (Premises (LowPriority)) (Conclusions (SelectedGoal))) (CTV (STV 1.0 1.0) (STV 0.0 1.0))))
!(mm2-test-equal (let $_ (mm2-forward-chain-from 1 selectedNegativeKb (HighPriority)) (mm2-forward-derived? selectedNegativeKb (SelectedGoal))) false)
!(mm2-test-equal (let $_ (mm2-forward-chain-from 1 selectedNegativeKb (LowPriority)) (mm2-forward-derived? selectedNegativeKb (SelectedGoal))) true)

; kb isolation: stvRuleKb facts must not leak into nAryKb
!(mm2-test-query 5 nAryKb (: $prf (B x) $tv) ())
