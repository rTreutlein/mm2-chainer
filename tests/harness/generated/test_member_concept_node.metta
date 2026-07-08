; generated from PeTTaChainer tests/test_member_concept_node.metta by convert_petta_tests.py
!(import! &self /nexus/Dev/OpenCog/NL2PLN_Project/mm2-chainer/compiler/mm2_chainer)
!(mm2-init)
!(mm2-compileadd memberConceptKb (: m1 (Member tom Human) (STV 1.0 0.9)))
!(mm2-test-known-concept-node memberConceptKb Human true)
!(mm2-test-known-concept-node memberConceptKb tom false)
