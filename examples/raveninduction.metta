!(import! &self /nexus/Dev/OpenCog/NL2PLN_Project/mm2-chainer/compiler/mm2_chainer)
!(mm2-init)

; The direct observations are lowered by the shared compiler into implication
; views. MM2 keeps the dynamic concept prior and all derived evidence in MORK.
!(mm2-set-concept-prior-confidence ravenDerivedKb 0.9)

!(mm2-compileadd ravenDerivedKb (: rv1RavenObserved (Inheritance rv1 raven) (STV 0.9 0.9)))
!(mm2-compileadd ravenDerivedKb (: rv2RavenObserved (Inheritance rv2 raven) (STV 0.9 0.9)))
!(mm2-compileadd ravenDerivedKb (: rv1BlackObserved (Inheritance rv1 (IntSet black)) (STV 0.8 0.9)))
!(mm2-compileadd ravenDerivedKb (: rv2BlackObserved (Inheritance rv2 (IntSet black)) (STV 0.0 0.9)))

!(mm2-test-query-proofs 300 ravenDerivedKb
   (: $prf (Inheritance raven (IntSet black)) $tv)
   ((: (mm2-proof
          ((inheritance-implication rv1BlackObserved)
           (inheritance-implication rv2BlackObserved)
           (inheritance-implication rv1RavenObserved)
           (inheritance-implication rv2RavenObserved)
           (ctx proof 0)))
       (Inheritance raven (IntSet black))
       (STV 0.31926668671363573 0.7631999714085422))))
