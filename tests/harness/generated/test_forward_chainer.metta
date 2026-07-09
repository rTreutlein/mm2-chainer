; generated from PeTTaChainer tests/test_forward_chainer.metta by convert_petta_tests.py
; forward materialization subset; PeTTa forward agenda/proof bookkeeping is not generated yet
!(import! &self /nexus/Dev/OpenCog/NL2PLN_Project/mm2-chainer/compiler/mm2_chainer)
!(mm2-init)
!(mm2-compileadd fwdkb (: edgeAB (Edge A B) (STV 1.0 1.0)))
!(mm2-compileadd fwdkb (: edgeBC (Edge B C) (STV 1.0 1.0)))
!(mm2-compileadd fwdkb (: edgeToPath (Implication (Premises (Edge $x $y)) (Conclusions (Path $x $y))) (CTV (STV 1.0 1.0) (STV 0.0 1.0))))
!(mm2-compileadd fwdkb (: pathStep (Implication (Premises (Path $x $y) (Edge $y $z)) (Conclusions (Path $x $z))) (CTV (STV 1.0 1.0) (STV 0.0 1.0))))
!(mm2-compileadd fwdkb (: pathIdempotent (Implication (Premises (Path $x $y)) (Conclusions (Path $x $y))) (CTV (STV 1.0 1.0) (STV 0.0 1.0))))
!(mm2-test-forward-has-derived 50 fwdkb (Path A C) true)
; Remaining source forms start at PeTTa forward agenda/proof bookkeeping coverage and are intentionally omitted here.
