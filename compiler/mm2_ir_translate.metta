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
;   [subgoal]  NotFormula (MP $not (CTV ..))                      -> ruleN not-ctv
;   [subgoals] NotFormula AndFormula (MP $agg (CTV ..))           -> ruleN not-and-ctv
;   [subgoals] Fold(a) Fold(b) (ImplCTV .. (STV s c)) MP          -> ruleN stv
;   [subgoals] Fold(a) Fold(b) (ImplCTV ..) Inversion MP          -> ruleN inv
;   [compound other*] AndFormula* (AndProjection ..)              -> ruleN (proj and)
;   [compound other]  (OrProjection ..)                           -> ruleN (proj or)
;   [compound] (AndMarginalProjection ..)                         -> ruleN (proj marg)
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

; --- kb scoping --------------------------------------------------------------
; Goal-level terms are scoped by the IR's own kb field: ($kb-triple $term).
; compile.metta scopes every item with a kb triple ($kb $ctx $vars) — MAIN/Nil
; for ordinary statements (kbctx), a numbered assumption context for query
; premises. Rule items share *free* ctx/vars variables between premises and
; conclusion, so rules are context-generic while facts stay context-specific;
; assumption facts therefore only feed derivations inside their own context.
; Plain kb symbols (base-rate fold args) scope like kbctx does.

(= (mm2-ir-scope-kb $kb) (if (is-expr $kb) $kb ($kb MAIN Nil)))

; --- premise/conclusion item classification --------------------------------

(= (mm2-ir-item $item)
   (case $item
     (((: $shape $prf $ptype $tv) (subgoal ($shape $ptype) $tv))
      ((CPU $formula $args $out) (cpu $formula $args $out))
      (($ptype $shape $prf $tv) (subgoal ($shape $ptype) $tv))
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

; Only the plain base-rate fold shape maps onto the runtime's base-rate
; relation. Anything else (weighted-universe folds for var-headed patterns,
; grouped folds, ...) makes the whole tail unsupported -- loudly: a partial
; match here used to leave an unreduced helper call inside the rule atom,
; which silently dropped the rule.
(= (mm2-ir-fold-pattern $cpu)
   (case $cpu
     (((cpu FoldAllCompiled ($kbid $pat extract-tv $zero BaseRateAcc base-rate $resmode) $out)
       (let $skb (mm2-ir-scope-kb $kbid) (brfold ($skb $pat))))
      ($other unsupported-fold))))

(= (mm2-ir-foldall-sum $cpu)
   (case $cpu
     (((cpu FoldAllCompiled ($kbid $pat (extract-value $pat2 $value) 0 lambda_17 identity unit-stv) $out)
       (if (== $pat $pat2)
         (let $skb (mm2-ir-scope-kb $kbid) (fold-sum ($skb $pat) $value $out))
         unsupported-foldall))
      ($other unsupported-foldall))))

(= (mm2-ir-foldall-pair-counts $cpu)
   (case $cpu
     (((cpu FoldAllCompiled ($kbid $pat (extract-value $pat2 $value) (PairCounts ()) DistValueCountAcc identity unit-stv) $out)
       (if (== $pat $pat2)
         (let $skb (mm2-ir-scope-kb $kbid) (fold-pair-counts ($skb $pat) $value $out))
         unsupported-foldall))
      ($other unsupported-foldall))))

(= (mm2-ir-stv-kind $pos $fa $fb $tail)
   (case ($fa $fb)
     ((((brfold $pa) (brfold $pb)) (stv-kind $pos $pa $pb))
      ($other (unsupported-tail $tail)))))

(= (mm2-ir-inv-kind $pos $fa $fb $materialize $tail)
   (case ($fa $fb)
     ((((brfold $pa) (brfold $pb)) (inv-kind $pos $pa $pb $materialize))
      ($other (unsupported-tail $tail)))))

(= (mm2-ir-classify $tail)
   (case $tail
     ((() identity)
      ((cons (cpu AndProjection ($tvin $ev) $out) ()) (proj-kind and))
      ((cons (cpu OrProjection ($tvin $ev) $out) ()) (proj-kind or))
      ((cons (cpu AndMarginalProjection ($tvin) $out) ()) (proj-kind marg))
      ((cons (cpu NotFormula ($tvin) $out) ()) (proj-kind not))
      ((cons (cpu CTVModusPonensFormula ($agg (CTV (STV $ps $pc) (STV $ns $nc))) $out) ())
       (ctv-kind ($ps $pc) ($ns $nc)))
      ((cons (cpu NotFormula ($tvin) $not)
         (cons (cpu CTVModusPonensFormula ($not2 (CTV (STV $ps $pc) (STV $ns $nc))) $out) ()))
       (if (== $not $not2)
         (not-ctv-kind ($ps $pc) ($ns $nc))
         (unsupported-tail $tail)))
      ((cons (cpu NotFormula ($tvin) $not)
         (cons (cpu AndFormula ($not2 $other) $agg)
           (cons (cpu CTVModusPonensFormula ($agg2 (CTV (STV $ps $pc) (STV $ns $nc))) $out) ())))
       (if (and (== $not $not2) (== $agg $agg2))
         (not-and-ctv-kind ($ps $pc) ($ns $nc))
         (unsupported-tail $tail)))
      ((cons (cpu CTVModusPonensFormula ($agg (CTV (STV $ps $pc) (STV $ns $nc))) $out)
         (cons (cpu NotFormula ($out2) $final) ()))
       (ctvn-kind ($ps $pc) ($ns $nc)))
      ((cons $fold ())
       (case (mm2-ir-foldall-sum $fold)
         (((fold-sum $pat $value $out) (fold-sum-kind $pat $value $out))
          ($other
           (case (mm2-ir-foldall-pair-counts $fold)
             (((fold-pair-counts $pat $value $out) (fold-pair-counts-kind $pat $value $out))
              ($other2 (unsupported-tail $tail))))))))
      ((cons $fold-a
         (cons $fold-b
           (cons (cpu ImplicationCTVFormula ($atv $btv (STV $s $c)) $ctv)
             (cons (cpu CTVModusPonensFormula ($agg $ctv) $out) ()))))
       (mm2-ir-stv-kind ($s $c)
                        (mm2-ir-fold-pattern $fold-a)
                        (mm2-ir-fold-pattern $fold-b)
                        $tail))
      ((cons $fold-a
         (cons $fold-b
           (cons (cpu ImplicationCTVFormula ($atv $btv $rule-tv) $ctv)
             (cons (cpu CTVInversionFormula ($atv2 $btv2 $ctv) $ictv)
               (cons (cpu CTVModusPonensFormula ($agg $ictv) $out) ())))))
       (mm2-ir-inv-kind (mm2-ir-rule-pos $rule-tv)
                        (mm2-ir-fold-pattern $fold-a)
                        (mm2-ir-fold-pattern $fold-b)
                        (mm2-ir-materialize? $rule-tv)
                        $tail))
      ($other (unsupported-tail $other)))))

; Total-implication rules assemble their conclusion TV structurally as
; (CTV $pos-tv $neg-tv) from the two context conclusions' TVs -- there is no
; CPU item, so they classify as identity; the CTV-shaped conclusion TV (a
; bound expression, never a free result var) distinguishes them from adapter
; chains.
(= (mm2-ir-refine-kind $kind $ctv)
   (if (and (== $kind identity) (is-expr $ctv))
     (case $ctv
       (((CTV $pos $neg) (proj-kind ctvpair))
        ($other $kind)))
     $kind))

(= (mm2-ir-rule-pos (CTV (STV $ps $pc) $neg)) ($ps $pc))
(= (mm2-ir-rule-pos (STV $s $c)) ($s $c))

(= (mm2-ir-materialize? (CTV $pos $neg)) yes)
(= (mm2-ir-materialize? (STV $s $c)) no)

; --- statement translation ---------------------------------------------------
; Each translation superposes the mm2 atoms for one IR statement.

(= (mm2-ir-emit-rule $ctype $ptypes identity)
   (adapterN $ctype $ptypes))

(= (mm2-ir-emit-rule $ctype $ptypes (proj-kind $op))
   (ruleN $ctype (proj $op) $ptypes))

(= (mm2-ir-emit-rule $ctype $ptypes (ctv-kind $pos $neg))
   (ruleN $ctype (ctv $pos $neg) $ptypes))

(= (mm2-ir-emit-rule $ctype $ptypes (not-ctv-kind $pos $neg))
   (ruleN $ctype (not-ctv $pos $neg) $ptypes))

(= (mm2-ir-emit-rule $ctype $ptypes (not-and-ctv-kind $pos $neg))
   (case $ptypes
     (((pcons ($scope $prem) $rest)
       (let $not-prem ($scope (Not $prem))
         (superpose (
           (ruleN $not-prem (proj not) (pcons ($scope $prem) pnil))
           (ruleN $ctype (ctv $pos $neg) (pcons $not-prem $rest))))))
      ($other (notsupported-ir (not-and-ctv $ctype $ptypes))))))

(= (mm2-ir-emit-rule $ctype $ptypes (ctvn-kind $pos $neg))
   (ruleN $ctype (ctvn $pos $neg) $ptypes))

(= (mm2-ir-emit-rule $ctype $ptypes (fold-sum-kind $pat $value $out))
   (case $ptypes
     ((pnil
       (let $result-copy (copy_term $ctype)
         (case $result-copy
           ((($scope (FoldAll $qpat $qvalue $zero $fun -> $out-copy))
             (let (fold-source $pat-copy $value-copy) (copy_term (fold-source $pat $value))
               (foldall-sum $result-copy $out-copy $pat-copy $value-copy)))
            ($other (notsupported-ir (foldall-result-copy $ctype)))))))
      ($other (notsupported-ir (foldall-with-premises $ctype $ptypes))))))

(= (mm2-ir-emit-rule $ctype $ptypes (fold-pair-counts-kind $pat $value $out))
   (case $ptypes
     ((pnil
       (let $result-copy (copy_term $ctype)
         (case $result-copy
           ((($scope (FoldAll $qpat $qvalue $zero $fun -> $out-copy))
             (let (fold-source $pat-copy $value-copy) (copy_term (fold-source $pat $value))
               (foldall-pair-counts $result-copy $out-copy $pat-copy $value-copy)))
            ($other (notsupported-ir (foldall-result-copy $ctype)))))))
      ($other (notsupported-ir (foldall-with-premises $ctype $ptypes))))))

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

(= (mm2-ir-emit-fact $g ($s $c))
   (superpose (
     (fact $g ($s $c))
     (fact-evidence $g ($s $c) (pcons (fact-ev $g) pnil)))))

; The TV is is-var-checked before structural matching: a case pattern
; (STV $s $c) would UNIFY with a free tv var (identity-query ctxatoms carry
; one) and emit a wildcard fact with unbound strength/confidence that then
; unifies with every premise lookup.
(= (mm2-ir-fact-stmt $g $tv)
   (if (is-var $tv)
     (notsupported-ir (free-tv-fact $g))
     (case $tv
       (((STV $s $c)
         (if (or (is-var $s) (is-var $c))
           (notsupported-ir (free-tv-fact $g))
           (mm2-ir-emit-fact $g ($s $c))))
        ($other (notsupported-ir (fact-tv $g $other)))))))

; Rules with an implication-typed premise need that premise's
; total-implication query scaffold (assumption contexts + ctvpair rule) in
; the store -- PeTTa compiles it lazily when the chainer reaches the subgoal;
; mm2 expands it eagerly at add time. The marker is resolved by the harness
; (mm2-add-compiled), which guards against duplicate scaffolds.
; The head is matched as a variable and checked explicitly: a case pattern
; (Implication $ps $cs) would UNIFY with a var-headed premise like ($r $x $y),
; binding the rule's own $r to Implication and mangling the rule.
(= (mm2-ir-implication-query $p)
   (case $p
     (((($kb $ctx $vars) ($head $ps $cs))
       (if (and (not (is-var $head)) (== $head Implication))
         (needs-implication-query $kb ($head $ps $cs))
         (empty)))
      ($other (empty)))))

(= (mm2-ir-implication-queries pnil) (empty))
(= (mm2-ir-implication-queries (pcons $p $rest))
   (superpose ((mm2-ir-implication-query $p)
               (mm2-ir-implication-queries $rest))))

; Facts arrive in compileadd form (: shape prf type tv) or query form
; (type shape prf tv) — the latter are the assumption facts total-implication
; queries add into their fresh contexts.
(= (mm2-translate-stmt $stmt)
   (case $stmt
     (((: $shape $prf $type $tv)
       (mm2-ir-fact-stmt ($shape $type) $tv))
      ((rules ($prems |- $ccl))
       (let* (((collected $ptypes $cpus) (mm2-ir-collect $prems))
              ((subgoal $ctype $ctv) (mm2-ir-item $ccl))
              ($kind (mm2-ir-refine-kind
                       (mm2-ir-classify (mm2-ir-drop-and $cpus))
                       $ctv)))
         (superpose ((mm2-ir-emit-rule $ctype $ptypes $kind)
                     (mm2-ir-implication-queries $ptypes)))))
      (($type $shape $prf $tv)
       (mm2-ir-fact-stmt ($shape $type) $tv))
      ($other (notsupported-ir (stmt $other))))))

(= (mm2-translate-all ()) ())
(= (mm2-translate-all (cons $stmt $rest))
   (mm2-ir-append (collapse (mm2-translate-stmt $stmt))
                  (mm2-translate-all $rest)))

; --- query translation --------------------------------------------------------
; (compiled-query ($type $shape $prf $tv) $adds) -> goal atom + translated adds.

(= (mm2-translate-query $cq)
   (case $cq
     (((compiled-query $goal-item $adds)
       (let (subgoal $g $tv) (mm2-ir-item $goal-item)
         (cons (, (Goal $g)) (mm2-translate-all $adds))))
      ($other (cons (notsupported-ir (query $other)) ())))))
