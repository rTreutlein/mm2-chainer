; generated from PeTTaChainer tests/test_chainer_add_atom.metta by convert_petta_tests.py
!(import! &self /nexus/Dev/OpenCog/NL2PLN_Project/mm2-chainer/compiler/mm2_chainer)
!(mm2-init)
!(mm2-test-equal (collapse (let $x (Cyclic $x) (chainer-add-atom &tmp (Stored $x)))) ())
!(mm2-test-equal (collapse (chainer-add-atom &tmp (Stored acyclic))) (true))
