; Minimal PeTTa-to-mm2-chainer backend.
;
; Lowers PeTTaChainer-style statements into mm2-chainer runtime IR:
;
;   (: a A (STV s c))                          -> (fact A (s c))
;                                                 + fact-evidence/proved records
;                                                 so later proofs revise and
;                                                 evidence-aware adapters can
;                                                 read source evidence
;   (: r (Implication (Premises p...)
;         (Conclusions q)) (CTV (STV ..) ..))  -> (ruleN q r (ctv (..) (..)) prems)
;   (: r (Implication ...) (STV s c))          -> (ruleN q r (stv (s c)
;                                                    (brpat a q')) prems)
;                                                 or application-local stv-local
;                                                 for structural-And premises
;                                                 + role-keyed base-rate-def /
;                                                   base-rate seeds
;   query (: $prf T $tv)                       -> (, (Goal T)) [+ adapterN for And]
;
; Single-premise implications additionally compile an inverse rule (PeTTa's
; CTVInversionFormula path) unless the proof name is (no_inverse $x):
;
;   (ruleN a r (inv (s+ c+) (brpat a' q')) (pcons q pnil))
;
; plus base-rate support for both patterns and an open materialization goal
; for the conclusion pattern. The goal mirrors PeTTaChainer's base-rate
; FoldAll premises, which are chaining queries: derived conclusion instances
; must reach the fact store so the base rates the inversion reads at fire
; time include them.
;
; Base-rate patterns are copy_term'd and keyed by rule+role so goal unification
; inside the runtime never instantiates them and unifiable antecedent/consequent
; patterns do not cross-match each other's maintained base-rate facts.

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
       (superpose (
         (fact $type ($s $c))
         (fact-evidence $type ($s $c) (pcons (fact-ev (fact-key $type) $type) pnil))
         (proved $type ($s $c) $name (pcons (fact-ev (fact-key $type) $type) pnil))))))

; Only CTV rules compile an inverse for now. An STV rule's derived CTV and
; its inverse both read the conclusion's base rate, and PeTTa's base-rate
; folds carry a recursion guard (a rule's own fold never includes conclusions
; derived via that same rule) that the mm2 runtime does not model yet; with
; inversion's materialization goal the STV rule would keep re-firing against
; its own derived conclusions.
(= (mm2-compile-add (: $name (Implication (Premises $p) (Conclusions $q)) $tv))
   (superpose (
     (mm2-implication-forward $name $tv (pcons $p pnil) $p $q)
     (if (or (=? $name (no_inverse $_)) (not (=? $tv (CTV $_pos $_neg))))
         (empty)
         (mm2-implication-inverse $name $tv $p $q)))))

(= (mm2-compile-add (: $name (Implication (Premises $p1 $p2) (Conclusions $q)) $tv))
   (mm2-implication-forward $name $tv (pcons $p1 (pcons $p2 pnil)) (And $p1 $p2) $q))

(= (mm2-compile-add (: $name (Implication (Premises $p1 $p2 $p3) (Conclusions $q)) $tv))
   (mm2-implication-forward $name $tv (pcons $p1 (pcons $p2 (pcons $p3 pnil))) (And $p1 $p2 $p3) $q))

(= (mm2-implication-forward $name (CTV (STV $pos-s $pos-c) (STV $neg-s $neg-c)) $premises $ante $concl)
   (ruleN $concl $name (ctv ($pos-s $pos-c) ($neg-s $neg-c)) $premises))

(= (mm2-implication-forward $name (STV $s $c) $premises $ante $concl)
   (superpose (
     (ruleN
       $concl
       $name
       (stv
         ($s $c)
         (brpat
           (mm2-base-rate-key $name antecedent $ante)
           (mm2-base-rate-key $name consequent $concl)))
       $premises)
     (mm2-base-rate-support $name antecedent $ante)
     (mm2-base-rate-support $name consequent $concl))))

; CTVInversionFormula only reads the rule's positive branch, so CTV and STV
; rules share one inverse shape.
(= (mm2-rule-pos (CTV (STV $pos-s $pos-c) $_neg)) ($pos-s $pos-c))
(= (mm2-rule-pos (STV $s $c)) ($s $c))

(= (mm2-implication-inverse $name $tv $ante $concl)
   (superpose (
     (ruleN
       $ante
       $name
       (inv
         (mm2-rule-pos $tv)
         (brpat
           (mm2-base-rate-key $name antecedent $ante)
           (mm2-base-rate-key $name consequent $concl)))
       (pcons $concl pnil))
     (mm2-base-rate-support $name antecedent $ante)
     (mm2-base-rate-support $name consequent $concl)
     (, (Goal (copy_term $concl))))))

(= (mm2-base-rate-key $name $role $pat)
   (base-rate-key (copy_term $name) $role (copy_term $pat)))

(= (mm2-base-rate-support $pat)
   (superpose (
     (base-rate-def (copy_term $pat) (copy_term $pat))
     (base-rate (copy_term $pat) (0.0 0.0))
     (contribution-state (base-rate (copy_term $pat)) (0.0 0.0))
     (contribution-value (base-rate (copy_term $pat)) (0.0 0.0))
     (base-rate-contribution-bootstrap
       (copy_term $pat) (copy_term $pat))
     (mm2-base-rate-materialization-goal $pat))))

(= (mm2-base-rate-support $name $role $pat)
   (let $key (mm2-base-rate-key $name $role $pat)
     (superpose (
       (base-rate-def $key (copy_term $pat))
       (base-rate (copy_term $key) (0.0 0.0))
       (contribution-state (base-rate (copy_term $key)) (0.0 0.0))
       (contribution-value (base-rate (copy_term $key)) (0.0 0.0))
       (base-rate-contribution-bootstrap $key (copy_term $pat))
       (mm2-base-rate-materialization-goal $pat)))))

; PeTTaChainer's FoldAll base-rate premises can derive compound query facts
; while folding. MM2's maintained base-rate relation only sees materialized
; facts, so compound antecedents need an explicit goal to populate adapterN
; facts before the fold is recomputed. Keep this narrow to And adapters; do
; not open arbitrary atomic base-rate patterns.
(= (mm2-base-rate-materialization-goal $pat)
   (case $pat
     (((And $a $b) (, (Goal (copy_term $pat))))
      ((And $a $b $c) (, (Goal (copy_term $pat))))
      ((And $a $b $c $d) (, (Goal (copy_term $pat))))
      (($scope (And $a $b)) (, (Goal (copy_term $pat))))
      (($scope (And $a $b $c)) (, (Goal (copy_term $pat))))
      (($scope (And $a $b $c $d)) (, (Goal (copy_term $pat))))
      ($other (empty)))))

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
