!(import! &self /nexus/Dev/OpenCog/NL2PLN_Project/mm2-chainer/compiler/mm2_chainer)
!(mm2-init)

!(mm2-set-universe-size boundaryKb 4.0)
!(mm2-set-concept-prior-confidence boundaryKb 0.75)
!(mm2-compileadd boundaryKb
   (: sourceFact (Inheritance Raven Bird) (STV 0.9 0.8)))

; Compiler facts and configuration are persisted in MORK.
!(mm2-test-equal
   (not
     (==
       (collapse
         (match &mork
           (mm2-compiler-fact-ir
             ((Inheritance Raven Bird)
              (boundaryKb MAIN Nil)
              sourceFact
              (STV 0.9 0.8)))
           true))
       ()))
   true)
!(mm2-test-equal (mm2-kb-universe-size boundaryKb) 4.0)
!(mm2-test-equal
   (mm2-concept-node-prior-tv boundaryKb Raven)
   (STV 0.5 0.75))

; Cache/config state is also MORK-owned, and configuration changes invalidate
; derived (but not user-authored) base-rate entries.
!(mm2-store-computed-base-rate!
   boundaryKb (Sample $x) (STV 0.25 0.5) boundary-test)
!(mm2-test-cached-base-rate
   boundaryKb (Sample $x) (STV 0.25 0.5))
!(mm2-set-universe-size boundaryKb 5.0)
!(mm2-test-cached-base-rate boundaryKb (Sample $x) no-cache-entry)
!(mm2-test-equal (mm2-kb-universe-size boundaryKb) 5.0)

; The compiler's hard-coded &kb view is transient, including after queries.
!(mm2-test-equal
   (collapse
     (match &kb
       ($type (boundaryKb $ctx $vars) $proof $tv)
       ($type $proof $tv)))
   ())
!(collapse
   (mm2-query 5 boundaryKb
     (: $proof (Inheritance Raven Bird) $tv)))
!(mm2-test-equal
   (collapse
     (match &kb
       ($type (boundaryKb $ctx $vars) $proof $tv)
       ($type $proof $tv)))
   ())
