; generated from PeTTaChainer tests/test_stv_implication_derived_ctv.metta by convert_petta_tests.py
!(import! &self /nexus/Dev/OpenCog/NL2PLN_Project/mm2-chainer/compiler/mm2_chainer)
!(mm2-init)
!(mm2-compileadd stvRuleKb (: a (A x) (STV 1.0 0.9)))
!(mm2-compileadd stvRuleKb (: aToB (Implication (Premises (A $x)) (Conclusions (B $x))) (STV 0.6 0.9)))
!(mm2-test-query 20 stvRuleKb (: $prf (B x) $tv) ((: (aToB a) (B x) (STV 0.6 0.8999998649685302))))
