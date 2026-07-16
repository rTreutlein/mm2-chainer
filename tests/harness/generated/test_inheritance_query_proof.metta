; generated from PeTTaChainer tests/test_inheritance_query_proof.metta by convert_petta_tests.py
!(import! &self /nexus/Dev/OpenCog/NL2PLN_Project/mm2-chainer/compiler/mm2_chainer)
!(mm2-init)
!(mm2-compileadd inheritanceQueryKb (: i1 (Inheritance a Bird) (STV 1.0 0.9)))
!(mm2-compileadd inheritanceQueryKb (: i2 (Inheritance a Flier) (STV 1.0 0.9)))
!(mm2-compileadd inheritanceQueryKb (: i3 (Inheritance b Bird) (STV 1.0 0.9)))
!(mm2-compileadd inheritanceQueryKb (: i4 (Inheritance b Flier) (STV 1.0 0.9)))
; One exact public result: this simultaneously checks canonicalization and TV.
!(mm2-test-query 80 inheritanceQueryKb (: $prf (Inheritance Bird Flier) $tv) ((: inheritance-query-proof (Inheritance Bird Flier) (STV 0.9999999166665949 0.0012502032753877429))))
