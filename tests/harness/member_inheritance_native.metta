!(import! &self /nexus/Dev/OpenCog/NL2PLN_Project/mm2-chainer/compiler/mm2_chainer)
!(mm2-init)

(= (member-native-has-unsupported? ()) false)
(= (member-native-has-unsupported? (cons $atom $rest))
   (case $atom
     (((notsupported-ir $_reason) true)
      ($_other (member-native-has-unsupported? $rest)))))

(= (member-native-cold-cache-atoms ()) ())
(= (member-native-cold-cache-atoms (cons $atom $rest))
   (case $atom
     (((member-inheritance-cache-bootstrap $_cache $_scope $_subj $_concept)
       (cons $atom (member-native-cold-cache-atoms $rest)))
      ((member-inheritance-cold-query $_g $_sample $_rule $_mode)
       (cons $atom (member-native-cold-cache-atoms $rest)))
      ($_other (member-native-cold-cache-atoms $rest)))))

!(mm2-set-universe-size memberNativeKb 2.0)
!(mm2-compileadd memberNativeKb (: a1 (Member o1 A) (STV 0.9 0.9)))
!(mm2-compileadd memberNativeKb (: a2 (Member o2 A) (STV 0.9 0.9)))
!(mm2-compileadd memberNativeKb (: b1 (Member o1 B) (STV 0.8 0.9)))
!(mm2-compileadd memberNativeKb (: b2 (Member o2 B) (STV 0.0 0.9)))

; The generated FoldAllCompiled/WeightedBaseRateAcc tail must lower without a
; compatibility marker.
!(let $compiled
   (mm2-compile-query-ir memberNativeKb (: $prf (Inheritance A B) $tv))
   (mm2-test-equal
     (member-native-has-unsupported?
       (collapse (map-flat mm2-translate-query $compiled)))
     false))

; Both the value and the proof now come from the native runtime's materialized
; aggregate. The two sample adapters are the concrete proof certificate.
!(mm2-test-query-proofs
   100
   memberNativeKb
   (: $prf (Inheritance A B) $tv)
   ((: (mm2-proof
          (inheritance-query-result a2 b2 a1 b1))
       (Inheritance A B)
       (STV 0.39999999999999997 0.7290000000000001))))

; The no-universe mode uses WeightedBaseRateTv's count-confidence semantics.
!(mm2-compileadd memberNativeOpenKb
   (: openA (Member Alice A) (STV 0.5 0.8)))
!(mm2-compileadd memberNativeOpenKb
   (: openB (Member Alice B) (STV 0.25 0.6)))
!(mm2-test-query
   100
   memberNativeOpenKb
   (: $prf (Inheritance A B) $tv)
   ((: $_proof
       (Inheritance A B)
       (STV 0.25 0.00029991002699190244))))

; The first query installs a durable subscription. Later proof additions update
; only the affected object contribution, and warm query compilation emits no
; cold FoldAll path.
!(mm2-compileadd memberCacheKb (: cacheA1 (Member o1 A) (STV 0.9 0.9)))
!(mm2-compileadd memberCacheKb (: cacheB1 (Member o1 B) (STV 0.8 0.9)))
!(mm2-test-query-proofs
   100 memberCacheKb (: $prf (Inheritance A B) $tv)
   ((: (mm2-proof (inheritance-query-result cacheA1 cacheB1))
       (Inheritance A B)
       (STV 0.8 0.0009104203794292452))))
!(let $compiled
   (mm2-compile-query-ir memberCacheKb (: $prf (Inheritance A B) $tv))
   (mm2-test-equal
     (member-native-cold-cache-atoms
       (collapse (map-flat mm2-translate-query $compiled)))
     ()))
!(mm2-compileadd-many memberCacheKb
   (cons (: cacheA2 (Member o2 A) (STV 0.9 0.9))
     (cons (: cacheB2 (Member o2 B) (STV 0.0 0.9)) ())))
!(mm2-test-query-proofs
   100 memberCacheKb (: $prf (Inheritance A B) $tv)
   ((: (mm2-proof
          (inheritance-query-result cacheA2 cacheB2 cacheA1 cacheB1))
       (Inheritance A B)
       (STV 0.39999999999999997 0.001819184536182807))))
; A partial new object cannot contribute yet and must not leave a stale cache
; update waiting to be replayed by a later, unrelated insertion.
!(mm2-compileadd memberCacheKb
   (: cacheA3 (Member o3 A) (STV 0.9 0.9)))
!(mm2-test-query-proofs
   100 memberCacheKb (: $prf (Inheritance A B) $tv)
   ((: (mm2-proof
          (inheritance-query-result cacheA2 cacheB2 cacheA1 cacheB1))
       (Inheritance A B)
       (STV 0.39999999999999997 0.001819184536182807))))
!(mm2-compileadd memberCacheKb
   (: cacheB1Second (Member o1 B) (STV 0.4 0.9)))
!(mm2-test-query-proofs
   100 memberCacheKb (: $prf (Inheritance A B) $tv)
   ((: (mm2-proof
          (inheritance-query-result
            cacheA2 cacheB2 cacheA1 cacheB1 cacheB1Second))
       (Inheritance A B)
       (STV 0.3076923076923077 0.0018669684355532101))))
!(mm2-test-equal
   (collapse
     (match &mork
       (fact
         (member-inheritance-cache (memberCacheKb MAIN Nil) A B)
         $stv)
       $stv))
   ((0.3076923076923077 0.0018669684355532101)))

; MemberInheritanceEvidenceFormula returns no result when every sample has
; zero effective mass.
!(mm2-compileadd memberNativeEmptyKb
   (: emptyA (Member Alice A) (STV 0.0 0.8)))
!(mm2-compileadd memberNativeEmptyKb
   (: emptyB (Member Alice B) (STV 0.9 0.9)))
!(mm2-test-query
   100
   memberNativeEmptyKb
   (: $prf (Inheritance A B) $tv)
   ())

; Native member-fold queries open premise Goals internally. They are owned by
; the query session and must not accumulate after public query cleanup. Use a
; fresh runtime here because proof-aware helpers intentionally stop as soon as
; their expected row appears, whereas the public query runs its full budget.
!(mm2-init)
!(mm2-compileadd memberCleanupKb
   (: cleanupA (Member Alice A) (STV 0.5 0.8)))
!(mm2-compileadd memberCleanupKb
   (: cleanupB (Member Alice B) (STV 0.25 0.6)))
!(mm2-query 20 memberCleanupKb (: $prf (Inheritance A B) $tv))
!(mm2-test-equal
   (collapse
     (match &mork
       (, (Goal ((memberCleanupKb $ctx $vars) $type)))
       (($ctx $vars) $type)))
   ())
