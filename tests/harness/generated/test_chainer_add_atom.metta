; generated from PeTTaChainer tests/test_chainer_add_atom.metta by convert_petta_tests.py
!(import! &self /nexus/Dev/OpenCog/NL2PLN_Project/mm2-chainer/compiler/mm2_chainer)
!(mm2-init)
; UNSUPPORTED test form: (test (collapse (let $x (Cyclic $x) (chainer-add-atom &tmp (Stored $x)))) ())
!(mm2-test-unsupported "test  collapse  let $x  Cyclic $x   chainer-add-atom  tmp  Stored $x")
; UNSUPPORTED test form: (test (collapse (chainer-add-atom &tmp (Stored acyclic))) (true))
!(mm2-test-unsupported "test  collapse  chainer-add-atom  tmp  Stored acyclic     true")
