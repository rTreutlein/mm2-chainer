; generated from PeTTaChainer tests/test_inheritance_aggregate_cycle.metta by convert_petta_tests.py
!(import! &self /nexus/Dev/OpenCog/NL2PLN_Project/mm2-chainer/compiler/mm2_chainer)
!(mm2-init)
!(mm2-set-concept-prior-confidence inheritanceAggregateCycleKb 0.5)
!(mm2-compileadd inheritanceAggregateCycleKb (: ravenBird (Inheritance Raven Bird) (STV 1.0 0.9)))
!(mm2-compileadd inheritanceAggregateCycleKb (: penguinBird (Inheritance Penguin Bird) (STV 1.0 0.9)))
!(mm2-test-query 100 inheritanceAggregateCycleKb (: $proof (Inheritance Raven Penguin) $tv) ((: (inheritance-implication-fold (total-implication ((inverted (inheritance-implication penguinBird) with cpu (foldall-proof ravenBird penguinBird)) ((inheritance-implication ravenBird) (ctx proof 0))) ((inverted (inheritance-implication penguinBird) with cpu (foldall-proof ravenBird penguinBird)) ((inheritance-implication ravenBird) (ctx proof 1))))) (Inheritance Raven Penguin) (STV 0.3571428571428571 0.4727586120223953))))
