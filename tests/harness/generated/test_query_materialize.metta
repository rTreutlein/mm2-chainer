; generated from PeTTaChainer tests/test_query_materialize.metta by convert_petta_tests.py
; mm2's low-level firings need a wider budget than PeTTa's agenda count for
; this two-hop materialization chain; budget 10 is the smallest passing fresh
; Goal query in the current runtime.
!(import! &self /nexus/Dev/OpenCog/NL2PLN_Project/mm2-chainer/compiler/mm2_chainer)
!(mm2-init)
!(mm2-compileadd materializeKb (: a0 (A) (STV 1.0 1.0)))
!(mm2-compileadd materializeKb (: r1 (Implication (Premises (A)) (Conclusions (B))) (CTV (STV 1.0 1.0) (STV 0.0 1.0))))
!(mm2-compileadd materializeKb (: r2 (Implication (Premises (B)) (Conclusions (Goal))) (CTV (STV 1.0 1.0) (STV 0.0 1.0))))
!(mm2-test-query 10 materializeKb (: $p (Goal) $tv) ((: (r2 (r1 a0)) (Goal) (STV 1.0 0.999700089898053))))
!(mm2-test-equal (mm2-materialized-list materializeKb (B)) ())
!(mm2-test-equal (mm2-materialized-list materializeKb (Goal)) ())
!(mm2-test-query-materialize 10 materializeKb (: $p (Goal) $tv) ((: (r2 (r1 a0)) (Goal) (STV 1.0 0.999700089898053))))
!(mm2-test-equal (not (== (mm2-materialized-list materializeKb (B)) ())) true)
!(mm2-test-equal (not (== (mm2-materialized-list materializeKb (Goal)) ())) true)
!(mm2-test-query 1 materializeKb (: $p (B) $tv) ((: (r1 a0) (B) (STV 1.0 0.9998000399670116))))
!(mm2-test-query 10 materializeKb (: $p (Goal) $tv) ((: (r2 (r1 a0)) (Goal) (STV 1.0 0.999700089898053))))
