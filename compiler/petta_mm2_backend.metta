; Minimal PeTTa-to-mm2-chainer backend.
;
; Lowers PeTTaChainer-style statements into mm2-chainer runtime IR:
;
;   (: a A (STV s c))                          -> (fact A (s c))
;   (: r (Implication (Premises p...)
;         (Conclusions q)) (CTV (STV ..) ..))  -> (ruleN q (ctv (..) (..)) prems)
;   (: r (Implication ...) (STV s c))          -> (ruleN q (stv (s c) (brpat a q')) prems)
;                                                 + base-rate-def / base-rate seeds
;   query (: $prf T $tv)                       -> (, (Goal T)) [+ adapterN for And]
;
; Plain STV rules derive their negative branch at runtime from the base rates
; of the antecedent and consequent patterns, so the rule lowering also emits
; the base-rate definitions and no-evidence seeds those folds start from.
; Base-rate patterns are copy_term'd so goal unification inside the runtime
; never instantiates them.

(= (mm2-and-premises (And $a $b))
   (pcons $a (pcons $b pnil)))

(= (mm2-and-premises (And $a $b $c))
   (pcons $a (pcons $b (pcons $c pnil))))

(= (mm2-and-premises (And $a $b $c $d))
   (pcons $a (pcons $b (pcons $c (pcons $d pnil)))))

; --- knowledge-base adds ------------------------------------------------

(= (mm2-compile-add (: $name $type (STV $s $c)))
   (if (=? $type (Implication $_p $_c))
       (empty)
       (fact $type ($s $c))))

(= (mm2-compile-add (: $name (Implication (Premises $p) (Conclusions $q)) $tv))
   (mm2-implication $tv (pcons $p pnil) $p $q))

(= (mm2-compile-add (: $name (Implication (Premises $p1 $p2) (Conclusions $q)) $tv))
   (mm2-implication $tv (pcons $p1 (pcons $p2 pnil)) (And $p1 $p2) $q))

(= (mm2-compile-add (: $name (Implication (Premises $p1 $p2 $p3) (Conclusions $q)) $tv))
   (mm2-implication $tv (pcons $p1 (pcons $p2 (pcons $p3 pnil))) (And $p1 $p2 $p3) $q))

(= (mm2-implication (CTV (STV $pos-s $pos-c) (STV $neg-s $neg-c)) $premises $ante $concl)
   (ruleN $concl (ctv ($pos-s $pos-c) ($neg-s $neg-c)) $premises))

(= (mm2-implication (STV $s $c) $premises $ante $concl)
   (let* (($ante-q (copy_term $ante))
          ($concl-q (copy_term $concl))
          ($ante-def-q (copy_term $ante))
          ($ante-def-m (copy_term $ante))
          ($concl-def-q (copy_term $concl))
          ($concl-def-m (copy_term $concl)))
     (superpose (
       (ruleN $concl (stv ($s $c) (brpat $ante-q $concl-q)) $premises)
       (base-rate-def $ante-def-q $ante-def-m)
       (base-rate (copy_term $ante) (0.0 0.0))
       (base-rate-def $concl-def-q $concl-def-m)
       (base-rate (copy_term $concl) (0.0 0.0))))))

; --- query lowering -----------------------------------------------------

(= (mm2-compile-query-goal (: $proof $type $tv))
   (, (Goal $type)))

; Compound And queries additionally need an identity adapter that derives the
; conjunction from its members with the premise-aggregate TV.
(= (mm2-compile-query-rule (: $proof (And $a $b) $tv))
   (adapterN (And $a $b) (mm2-and-premises (And $a $b))))

(= (mm2-compile-query-rule (: $proof (And $a $b $c) $tv))
   (adapterN (And $a $b $c) (mm2-and-premises (And $a $b $c))))

(= (mm2-compile-query-rule (: $proof (And $a $b $c $d) $tv))
   (adapterN (And $a $b $c $d) (mm2-and-premises (And $a $b $c $d))))
