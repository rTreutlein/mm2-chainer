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

; test_implication_inversion.metta
!(mm2-compileadd invKb (: r (Implication (Premises (P $x)) (Conclusions (Q $x))) (CTV (STV 0.8 0.9) (STV 0.1 0.9))))
!(mm2-compileadd invKb (: qa (Q alice) (STV 0.9 0.8)))
!(mm2-compileadd invKb (: pb (P bob) (STV 0.7 0.8)))
!(mm2-test-query 240 invKb (: $prf (P alice) $tv)
                 ((: $_ (P alice) (STV 0.736162240263287 0.0003604307138536469))))

; kb isolation: stvRuleKb facts must not leak into nAryKb
!(mm2-test-query 5 nAryKb (: $prf (B x) $tv) ())
