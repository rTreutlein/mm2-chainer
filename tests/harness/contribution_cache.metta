!(import! &self /nexus/Dev/OpenCog/NL2PLN_Project/mm2-chainer/compiler/mm2_chainer)
!(mm2-init)

; Ordinary base rates and Member folds share the same identity-keyed
; contribution ledger. A new fact updates only its own observation.
!(mm2-compileadd contributionKb
   (: pToQ
      (Implication (Premises (P $x)) (Conclusions (Q $x)))
      (CTV (STV 0.8 0.9) (STV 0.1 0.9))))
!(mm2-compileadd contributionKb (: qa (Q alice) (STV 0.9 0.8)))
!(mm2-compileadd contributionKb (: pb (P bob) (STV 0.7 0.8)))

!(mm2-test-cached-base-rate
   contributionKb (P $x)
   (STV 0.7 0.0009990009990009992))
!(mm2-test-equal
   (length
     (collapse
       (match &mork
         (contribution-observation
           (base-rate ((contributionKb MAIN Nil) (P $_which)))
           $_identity $_value $_weight $_proof)
         true)))
   1)
!(mm2-test-equal
   (collapse
     (match &mork
       (base-rate-contribution-bootstrap $_key $_pattern)
       true))
   ())

; A complete backward fold may refine the visible value. The ledger tracks
; that snapshot so the next insertion replaces it instead of leaving two
; alpha-equivalent base-rate rows.
!(mm2-test-query 200 contributionKb
   (: $proof (P alice) $tv)
   ((: $_ (P alice) (STV 0.736162240263287 0.0003604307138536469))))
!(mm2-compileadd contributionKb (: pc (P carol) (STV 0.3 0.8)))
!(mm2-test-cached-base-rate
   contributionKb (P $x)
   (STV 0.49999999999999994 0.0019960079840319364))
!(mm2-test-equal
   (length
     (collapse
       (match &mork
         (base-rate ((contributionKb MAIN Nil) (P $_which)) $_stv)
         true)))
   1)
!(mm2-test-equal
   (length
     (collapse
       (match &mork
         (contribution-observation
           (base-rate ((contributionKb MAIN Nil) (P $_which)))
           $_identity $_value $_weight $_proof)
         true)))
   2)

; User values remain authoritative even while keyed rule base rates continue
; to maintain their own contribution statistics.
!(mm2-set-base-rate contributionKb (P $x) (STV 0.42 0.75))
!(mm2-compileadd contributionKb (: pd (P dave) (STV 0.6 0.8)))
!(mm2-test-cached-base-rate contributionKb (P $x) (STV 0.42 0.75))
