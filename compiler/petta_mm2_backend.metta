; Minimal PeTTa-to-mm2-chainer backend.
;
; This first slice intentionally covers only the small shape needed by
; PeTTaChainer's test_nary_conjuction.metta:
;
;   (: a A (STV 1.0 1.0))                  -> (fact A (1.0 1.0))
;   (: $prf (And A B C) $tv) query pattern -> Goal + adapterN

(= (mm2-compile-add (: $name $term (STV $s $c)))
   (fact $term ($s $c)))

(= (mm2-and-premises (And $a $b))
   (pcons $a (pcons $b pnil)))

(= (mm2-and-premises (And $a $b $c))
   (pcons $a (pcons $b (pcons $c pnil))))

(= (mm2-and-premises (And $a $b $c $d))
   (pcons $a (pcons $b (pcons $c (pcons $d pnil)))))

(= (mm2-compile-query (: $proof (And $a $b) $tv))
   (, (, (Goal (And $a $b)))
      (adapterN (And $a $b) (mm2-and-premises (And $a $b)))))

(= (mm2-compile-query-goal (: $proof (And $a $b) $tv))
   (, (Goal (And $a $b))))

(= (mm2-compile-query-rule (: $proof (And $a $b) $tv))
   (adapterN (And $a $b) (mm2-and-premises (And $a $b))))

(= (mm2-compile-query (: $proof (And $a $b $c) $tv))
   (, (, (Goal (And $a $b $c)))
      (adapterN (And $a $b $c) (mm2-and-premises (And $a $b $c)))))

(= (mm2-compile-query-goal (: $proof (And $a $b $c) $tv))
   (, (Goal (And $a $b $c))))

(= (mm2-compile-query-rule (: $proof (And $a $b $c) $tv))
   (adapterN (And $a $b $c) (mm2-and-premises (And $a $b $c))))

(= (mm2-compile-query (: $proof (And $a $b $c $d) $tv))
   (, (, (Goal (And $a $b $c $d)))
      (adapterN (And $a $b $c $d) (mm2-and-premises (And $a $b $c $d)))))

(= (mm2-compile-query-goal (: $proof (And $a $b $c $d) $tv))
   (, (Goal (And $a $b $c $d))))

(= (mm2-compile-query-rule (: $proof (And $a $b $c $d) $tv))
   (adapterN (And $a $b $c $d) (mm2-and-premises (And $a $b $c $d))))
