!(import! &self /nexus/Dev/OpenCog/NL2PLN_Project/mm2-chainer/compiler/mm2_chainer)
!(mm2-init)

!(mm2-compileadd deductionRevisionKb (: aInheritsB (Inheritance A B) (STV 0.25 0.9)))
!(mm2-compileadd deductionRevisionKb (: aInheritsC (Inheritance A C) (STV 0.25 0.9)))
!(mm2-compileadd deductionRevisionKb (: bInheritsD (Inheritance B D) (STV 0.5 0.9)))
!(mm2-compileadd deductionRevisionKb (: cInheritsD (Inheritance C D) (STV 0.5 0.9)))

; Each deduction excludes the source assertions already used by that
; application from its query-local marginals. The two independent paths are
; then revised into one estimate.
!(mm2-test-query-proofs 30 deductionRevisionKb
   (: $prf (Inheritance A D) $tv)
   ((: (mm2-proof
          ((inheritance-implication aInheritsB)
           (inheritance-implication aInheritsC)
           (inheritance-implication bInheritsD)
           (inheritance-implication cInheritsD)
           (ctx proof 0)))
       (Inheritance A D)
       (STV 0.4999994166674445 0.001941283033087962))))

!(mm2-compileadd deductionRevisionImplicationKb
   (: aImpliesB
      (Implication (Premises (A $x)) (Conclusions (B $x)))
      (CTV (STV 0.25 0.9) (STV 0.0 1.0))))
!(mm2-compileadd deductionRevisionImplicationKb
   (: aImpliesC
      (Implication (Premises (A $x)) (Conclusions (C $x)))
      (CTV (STV 0.25 0.9) (STV 0.0 1.0))))
!(mm2-compileadd deductionRevisionImplicationKb
   (: bImpliesD
      (Implication (Premises (B $x)) (Conclusions (D $x)))
      (CTV (STV 0.5 0.9) (STV 0.0 1.0))))
!(mm2-compileadd deductionRevisionImplicationKb
   (: cImpliesD
      (Implication (Premises (C $x)) (Conclusions (D $x)))
      (CTV (STV 0.5 0.9) (STV 0.0 1.0))))

!(mm2-test-query-proofs 100 deductionRevisionImplicationKb
   (: $prf
      (Implication (Premises (A $x)) (Conclusions (D $x)))
      $tv)
   ((: mm2-merged-ctv
       (Implication (Premises (A $x)) (Conclusions (D $x)))
       (CTV
          (STV 0.125 0.9692294378874315)
          (STV 0.0 0.9999367205825538)))))
