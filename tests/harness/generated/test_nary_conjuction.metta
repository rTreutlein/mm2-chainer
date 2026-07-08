; generated from PeTTaChainer tests/test_nary_conjuction.metta by convert_petta_tests.py
!(import! &self /nexus/Dev/OpenCog/NL2PLN_Project/mm2-chainer/compiler/mm2_chainer)
!(mm2-init)
!(mm2-compileadd kb (: a A (STV 1.0 1.0)))
!(mm2-compileadd kb (: b B (STV 1.0 1.0)))
!(mm2-compileadd kb (: c C (STV 1.0 1.0)))
!(mm2-test-query 10 kb (: $prf (And A B C) $tv) ((: (conjunction a b c) (And A B C) (STV 1.0 0.999700089898053))))
