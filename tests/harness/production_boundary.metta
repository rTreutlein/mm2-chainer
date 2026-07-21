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
!(mm2-test-equal
   (collapse
     (compiler-specialization-fact
       boundaryKb
       (Inheritance Raven $concept)))
   ((Inheritance Raven Bird)))

; MORK canonicalizes variables in stored expressions. Independently copied,
; alpha-equivalent compiler facts therefore occupy one set entry without a
; harness-side scan.
!(let $copy
   (copy_term
     ((CompilerMetadataProbe $x)
      (boundaryKb MAIN ($x))
      metadata-probe
      (STV 1.0 1.0)))
   (mm2-store-compiler-fact-ir! $copy))
!(let $copy
   (copy_term
     ((CompilerMetadataProbe $y)
      (boundaryKb MAIN ($y))
      metadata-probe
      (STV 1.0 1.0)))
   (mm2-store-compiler-fact-ir! $copy))
!(mm2-test-equal
   (length
     (collapse
       (match &mork
         (mm2-compiler-fact-ir
           ((CompilerMetadataProbe $value)
            (boundaryKb MAIN ($value))
            metadata-probe
            (STV 1.0 1.0)))
         true)))
   1)
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

; No compiler metadata is mirrored into PeTTa's &kb, including during queries.
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
