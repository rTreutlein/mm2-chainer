!(import! &self /nexus/Dev/OpenCog/NL2PLN_Project/mm2-chainer/compiler/mm2_chainer)
!(mm2-init)

(= (member-native-has-unsupported? ()) false)
(= (member-native-has-unsupported? (cons $atom $rest))
   (case $atom
     (((notsupported-ir $_reason) true)
      ($_other (member-native-has-unsupported? $rest)))))

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
          (inheritance-query-result
            (adapterN
              ((memberNativeKb MAIN Nil)
               (MemberInheritanceSample o1 A B $_a1tv $_b1tv))
              (pcons
                ((memberNativeKb MAIN Nil) (Member o1 A))
                (pcons ((memberNativeKb MAIN Nil) (Member o1 B)) pnil)))
            (adapterN
              ((memberNativeKb MAIN Nil)
               (MemberInheritanceSample o2 A B $_a2tv $_b2tv))
              (pcons
                ((memberNativeKb MAIN Nil) (Member o2 A))
                (pcons ((memberNativeKb MAIN Nil) (Member o2 B)) pnil)))))
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
