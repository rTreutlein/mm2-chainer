!(import! &self /nexus/Dev/OpenCog/NL2PLN_Project/mm2-chainer/compiler/mm2_chainer)
!(mm2-init)

!(mm2-compileadd directKb
   (: fathersFatherGrandfather
      (Implication
         (Premises (Father $a $b) (Father $b $c))
         (Conclusions (Grandfather $a $c)))
      (CTV (STV 1.0 0.9) (STV 0.0 1.0))))

!(mm2-compileadd directKb
   (: fathersMotherGrandfather
      (Implication
         (Premises (Father $a $b) (Mother $b $c))
         (Conclusions (Grandfather $a $c)))
      (CTV (STV 1.0 0.9) (STV 0.0 1.0))))

!(mm2-compileadd directKb
   (: grandfatherOld
      (Implication
         (Premises (Grandfather $a $x))
         (Conclusions (Old $a)))
      (CTV (STV 1.0 0.9) (STV 0.0 1.0))))

!(mm2-compileadd directKb (: fatherAB (Father a b) (STV 1.0 0.9)))
!(mm2-compileadd directKb (: fatherBC (Father b c) (STV 1.0 0.9)))
!(mm2-compileadd directKb (: fatherAY (Father a y) (STV 1.0 0.9)))
!(mm2-compileadd directKb (: motherYC (Mother y c) (STV 0.0 0.9)))

!(mm2-test-query-proofs 50 directKb
   (: $prf (Grandfather a c) $tv)
   ((: (mm2-proof
          (fathersFatherGrandfather fathersMotherGrandfather
           fatherAB fatherAY fatherBC motherYC))
       (Grandfather a c)
       (STV 0.2501166485375841 0.9230240565975534))))

!(mm2-test-query-proofs 50 directKb
   (: $prf (Grandfather $who c) $tv)
   ((: (mm2-proof
          (fathersFatherGrandfather fathersMotherGrandfather
           fatherAB fatherAY fatherBC motherYC))
       (Grandfather a c)
       (STV 0.2501166485375841 0.9230240565975534))))

!(mm2-test-query-proofs 50 directKb
   (: $prf (Old $who) $tv)
   ((: (mm2-proof
          (fathersFatherGrandfather fathersMotherGrandfather
           fatherAB fatherAY fatherBC motherYC))
       (Old a)
       (STV 0.2501166485375841 0.9230240245003262))))
