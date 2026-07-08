; generated from PeTTaChainer tests/test_implication_inversion.metta by convert_petta_tests.py
!(import! &self /nexus/Dev/OpenCog/NL2PLN_Project/mm2-chainer/compiler/mm2_chainer)
!(mm2-init)
!(mm2-compileadd invKb (: r (Implication (Premises (P $x)) (Conclusions (Q $x))) (CTV (STV 0.8 0.9) (STV 0.1 0.9))))
!(mm2-compileadd invKb (: qa (Q alice) (STV 0.9 0.8)))
!(mm2-compileadd invKb (: pb (P bob) (STV 0.7 0.8)))
!(mm2-test-query 200 invKb (: $prf (P alice) $tv) ((: ((inverted r with (foldall-proof pb) (foldall-proof qa (r pb))) qa) (P alice) (STV 0.736162240263287 0.0003604307138536469))))
