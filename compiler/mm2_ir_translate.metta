; Translator from PeTTaChainer's compiled rule IR to mm2-chainer atoms.
;
; PeTTaChainer's compile.metta already lowers statements/queries to an IR
; meant for MM2 (mm2compile / mm2compileQuery):
;
;   (: $shape $prf $type $tv)                      fact
;   (rules ($premise-items |- $conclusion-item))   rule
;   (compiled-query $goal-item $add-stmts)         query
;
; Premise/conclusion items are (: $shape $prf $type $tv) (compileadd form) or
; ($type $shape $prf $tv) (query form). CPU items compute truth values; the
; recognized chains map onto the mm2 runtime's rule kinds:
;
;   [subgoals] AndFormula*                                        -> adapterN
;   [subgoals] AndFormula* (MP $agg (CTV ..))                     -> ruleN ctv
;   [subgoals] Fold(a) Fold(b) (ImplCTV .. (STV s c)) MP          -> ruleN stv
;   [subgoals] Fold(a) Fold(b) (ImplCTV ..) Inversion MP          -> ruleN inv
;
; Anything else translates to a loud (notsupported-ir ...) atom: the corpus
; report collects those as the coverage gap list.
;
; Policy notes (documented divergences, see PLAN.md):
; - inv rules from CTV implications also emit an open materialization goal
;   for the consequent pattern (PeTTa's base-rate folds are chaining
;   queries); inv rules from STV implications do not, because the forward
;   STV rule would keep re-firing against its own derived conclusions
;   (PeTTa's fold recursion guard is not modeled).

; --- helpers ---------------------------------------------------------------

(= (mm2-ir-append () $ys) $ys)
(= (mm2-ir-append (cons $x $xs) $ys) (cons $x (mm2-ir-append $xs $ys)))

; --- premise/conclusion item classification --------------------------------

(= (mm2-ir-item $item)
   (case $item
     (((: $shape $prf $ptype $tv) (subgoal $ptype $tv))
      ((CPU $formula $args $out) (cpu $formula $args $out))
      (($ptype $shape $prf $tv) (subgoal $ptype $tv))
      ($other (unknown $other)))))

; Split the premise items into an ordered pcons list of subgoal types and the
; list of cpu items (order preserved).
(= (mm2-ir-collect ()) (collected pnil ()))
(= (mm2-ir-collect (cons $item $rest))
   (let (collected $ptypes $cpus) (mm2-ir-collect $rest)
     (case (mm2-ir-item $item)
       (((subgoal $t $v) (collected (pcons $t $ptypes) $cpus))
        ((cpu $f $a $o) (collected $ptypes (cons (cpu $f $a $o) $cpus)))
        ((unknown $o) (collected $ptypes (cons (unknown $o) $cpus)))))))

; The premise-aggregation AndFormula chain is implicit in the mm2 runtime's
; premise frontier, so leading AndFormula items are dropped before the tail
; is classified.
(= (mm2-ir-drop-and $cpus)
   (case $cpus
     (((cons (cpu AndFormula $args $out) $rest) (mm2-ir-drop-and $rest))
      ($other $other))))

; --- rule-kind classification of the cpu tail -------------------------------

(= (mm2-ir-fold-pattern (cpu FoldAllCompiled ($kbid $pat extract-tv $zero $acc $finish $resmode) $out))
   $pat)

(= (mm2-ir-classify $tail)
   (case $tail
     ((() identity)
      ((cons (cpu CTVModusPonensFormula ($agg (CTV (STV $ps $pc) (STV $ns $nc))) $out) ())
       (ctv-kind ($ps $pc) ($ns $nc)))
      ((cons $fold-a
         (cons $fold-b
           (cons (cpu ImplicationCTVFormula ($atv $btv (STV $s $c)) $ctv)
             (cons (cpu CTVModusPonensFormula ($agg $ctv) $out) ()))))
       (stv-kind ($s $c) (mm2-ir-fold-pattern $fold-a) (mm2-ir-fold-pattern $fold-b)))
      ((cons $fold-a
         (cons $fold-b
           (cons (cpu ImplicationCTVFormula ($atv $btv $rule-tv) $ctv)
             (cons (cpu CTVInversionFormula ($atv2 $btv2 $ctv) $ictv)
               (cons (cpu CTVModusPonensFormula ($agg $ictv) $out) ())))))
       (inv-kind (mm2-ir-rule-pos $rule-tv)
                 (mm2-ir-fold-pattern $fold-a)
                 (mm2-ir-fold-pattern $fold-b)
                 (mm2-ir-materialize? $rule-tv)))
      ($other (unsupported-tail $other)))))

(= (mm2-ir-rule-pos (CTV (STV $ps $pc) $neg)) ($ps $pc))
(= (mm2-ir-rule-pos (STV $s $c)) ($s $c))

(= (mm2-ir-materialize? (CTV $pos $neg)) yes)
(= (mm2-ir-materialize? (STV $s $c)) no)

; --- statement translation ---------------------------------------------------
; Each translation superposes the mm2 atoms for one IR statement.

(= (mm2-ir-emit-rule $ctype $ptypes identity)
   (adapterN $ctype $ptypes))

(= (mm2-ir-emit-rule $ctype $ptypes (ctv-kind $pos $neg))
   (ruleN $ctype (ctv $pos $neg) $ptypes))

(= (mm2-ir-emit-rule $ctype $ptypes (stv-kind $pos $pa $pb))
   (superpose (
     (ruleN $ctype (stv $pos (brpat $pa $pb)) $ptypes)
     (mm2-base-rate-support $pa)
     (mm2-base-rate-support $pb))))

(= (mm2-ir-emit-rule $ctype $ptypes (inv-kind $pos $pa $pb $materialize))
   (superpose (
     (ruleN $ctype (inv $pos (brpat $pa $pb)) $ptypes)
     (mm2-base-rate-support $pa)
     (mm2-base-rate-support $pb)
     (if (== $materialize yes)
       (, (Goal (copy_term $pb)))
       (empty)))))

(= (mm2-ir-emit-rule $ctype $ptypes (unsupported-tail $tail))
   (notsupported-ir (rule-tail $ctype $tail)))

(= (mm2-translate-stmt $stmt)
   (case $stmt
     (((: $shape $prf $type (STV $s $c))
       (superpose (
         (fact $type ($s $c))
         (fact-evidence $type ($s $c) (pcons (fact-ev $type) pnil)))))
      ((rules ($prems |- $ccl))
       (let* (((collected $ptypes $cpus) (mm2-ir-collect $prems))
              ((subgoal $ctype $ctv) (mm2-ir-item $ccl))
              ($kind (mm2-ir-classify (mm2-ir-drop-and $cpus))))
         (mm2-ir-emit-rule $ctype $ptypes $kind)))
      ($other (notsupported-ir (stmt $other))))))

(= (mm2-translate-all ()) ())
(= (mm2-translate-all (cons $stmt $rest))
   (mm2-ir-append (collapse (mm2-translate-stmt $stmt))
                  (mm2-translate-all $rest)))

; --- query translation --------------------------------------------------------
; (compiled-query ($type $shape $prf $tv) $adds) -> goal atom + translated adds.

(= (mm2-translate-query (compiled-query $goal-item $adds))
   (let (subgoal $type $tv) (mm2-ir-item $goal-item)
     (cons (, (Goal $type)) (mm2-translate-all $adds))))
