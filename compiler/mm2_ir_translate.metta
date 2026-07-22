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
;   [subgoals] OrFormula*                                         -> adapterOrN
;   [subgoals] AndFormula* (MP $agg (CTV ..))                     -> ruleN ctv
;   [subgoal]  Compute + [subgoal] AndFormula* MP                 -> ruleN compute-plus-ctv
;   [subgoals] DistGreaterThan* AndFormula MP                     -> ruleN dist-gt-ctv
;   [subgoal]  FoldAllValue ParticleAddBernoulliFromSTV MP        -> ruleN fold-value-bernoulli-ctv
;   [subgoal]  NotFormula (MP $not (CTV ..))                      -> fused TV pipeline (premise-not)
;   [subgoals] NotFormula AndFormula (MP $agg (CTV ..))           -> ruleN not-and-ctv
;   [subgoals] Fold(a) Fold(b) (ImplCTV .. (STV s c)) MP          -> ruleN stv
;   [subgoals] Fold(a) Fold(b) (ImplCTV ..) Inversion MP          -> ruleN inv
;   [FoldAll OrFormula] MP                                        -> foldall-or-ctv
;   [subgoal]  NotFormula AndFormula                              -> not-first
;   [TotalEvidence helpers]                                       -> total evidence
;   [compound other*] AndFormula* (AndProjection ..)              -> ruleN (proj and)
;   [compound other]  (OrProjection ..)                           -> ruleN (proj or)
;   [compound other*] OrFormula* (OrProjection ..)                 -> redundant scaffold
;   [compound] (AndMarginalProjection ..)                         -> ruleN (proj marg)
;
; Anything else translates to a loud (notsupported-ir ...) atom: the corpus
; report collects those as the coverage gap list.
;
; Policy notes (documented divergences, see PLAN.md):
; - inv rules emit an open materialization goal for the consequent pattern
;   (PeTTa's base-rate folds are chaining queries).  STV-derived CTVs use
;   guarded base-rate keys so a rule's own derived conclusions do not feed
;   the folds used to derive that same rule's CTV.

; --- helpers ---------------------------------------------------------------

(= (mm2-ir-append () $ys) $ys)
(= (mm2-ir-append (cons $x $xs) $ys) (cons $x (mm2-ir-append $xs $ys)))

(= (mm2-ir-dist-pair-atoms $_pid ()) ())
(= (mm2-ir-dist-pair-atoms $pid (cons ($x $w) $rest))
   (cons (dist-pair $pid $x $w) (mm2-ir-dist-pair-atoms $pid $rest)))

(= (mm2-ir-dist-particle-atom $term $pid)
   ((dist-particle-dist $term $pid)))

(= (mm2-ir-dist-point-atoms $term $pid (cons ($x $w) ()))
   ((dist-point-pair $pid $x $w) (dist-point-dist $term $x $w)))
(= (mm2-ir-dist-point-atoms $_term $_pid $_pairs) ())

(= (mm2-ir-dist-atoms-list ()) ())
(= (mm2-ir-dist-atoms-list (cons $term $rest))
   (mm2-ir-append (mm2-ir-dist-atoms $term) (mm2-ir-dist-atoms-list $rest)))

(= (mm2-ir-dist-atoms $term)
   (if (is-var $term)
     ()
     (if (is-expr $term)
       (let $head (car-atom $term)
         (if (and (not (is-var $head)) (== $head ParticleDist))
           (case $term
             (((ParticleDist $pid $_scale)
               (let $pairs (mm2-particle-pairs $term)
                 (mm2-ir-append
                   (mm2-ir-dist-particle-atom $term $pid)
                   (mm2-ir-append
                     (mm2-ir-dist-pair-atoms $pid $pairs)
                     (mm2-ir-dist-point-atoms $term $pid $pairs)))))))
           (mm2-ir-dist-atoms-list (cdr-atom $term))))
       ())))

(= (mm2-ir-superpose-list ()) (empty))
(= (mm2-ir-superpose-list (cons $atom $rest))
   (superpose ($atom (mm2-ir-superpose-list $rest))))

(= (mm2-ir-dist-map2-conclusion $ctype $dist-out $result-dist)
   (case $ctype
     ((($scope ($head $dist-out)) ($scope ($head $result-dist)))
      (($scope ($head $arg1 $dist-out)) ($scope ($head $arg1 $result-dist)))
      (($scope ($head $arg1 $arg2 $dist-out)) ($scope ($head $arg1 $arg2 $result-dist)))
      (($scope ($head $arg1 $arg2 $arg3 $dist-out)) ($scope ($head $arg1 $arg2 $arg3 $result-dist)))
      ($other (notsupported-ir (dist-map2-conclusion $ctype $dist-out))))))

(= (mm2-ir-dist-avg-rule-data $ctype $dist-out)
   (case $ctype
     ((($scope ($head $dist-out))
       (dist-avg-rule-data
         ($scope ($head (ParticleDist (dist-average $scope $head) 1.0)))
         (dist-average $scope $head)))
      (($scope ($head $arg1 $dist-out))
       (dist-avg-rule-data
         ($scope ($head $arg1 (ParticleDist (dist-average $scope $head $arg1) 1.0)))
         (dist-average $scope $head $arg1)))
      (($scope ($head $arg1 $arg2 $dist-out))
       (dist-avg-rule-data
         ($scope ($head $arg1 $arg2 (ParticleDist (dist-average $scope $head $arg1 $arg2) 1.0)))
         (dist-average $scope $head $arg1 $arg2)))
      (($scope ($head $arg1 $arg2 $arg3 $dist-out))
       (dist-avg-rule-data
         ($scope ($head $arg1 $arg2 $arg3 (ParticleDist (dist-average $scope $head $arg1 $arg2 $arg3) 1.0)))
         (dist-average $scope $head $arg1 $arg2 $arg3)))
      ($other (notsupported-ir (dist-avg-conclusion $ctype $dist-out))))))

(= (mm2-ir-dist-sum-rule-data $ctype $dist-out)
   (case $ctype
     ((($scope ($head $dist-out))
       (dist-sum-rule-data
         ($scope ($head (ParticleDist (dist-sum $scope $head) 1.0)))
         (dist-sum $scope $head)))
      (($scope ($head $arg1 $dist-out))
       (dist-sum-rule-data
         ($scope ($head $arg1 (ParticleDist (dist-sum $scope $head $arg1) 1.0)))
         (dist-sum $scope $head $arg1)))
      (($scope ($head $arg1 $arg2 $dist-out))
       (dist-sum-rule-data
         ($scope ($head $arg1 $arg2 (ParticleDist (dist-sum $scope $head $arg1 $arg2) 1.0)))
         (dist-sum $scope $head $arg1 $arg2)))
      (($scope ($head $arg1 $arg2 $arg3 $dist-out))
       (dist-sum-rule-data
         ($scope ($head $arg1 $arg2 $arg3 (ParticleDist (dist-sum $scope $head $arg1 $arg2 $arg3) 1.0)))
         (dist-sum $scope $head $arg1 $arg2 $arg3)))
      ($other (notsupported-ir (dist-sum-conclusion $ctype $dist-out))))))

(= (mm2-ir-last-list-item (cons $x ())) $x)
(= (mm2-ir-last-list-item (cons $_x $rest)) (mm2-ir-last-list-item $rest))
(= (mm2-ir-last-arg $term)
   (if (is-expr $term) (mm2-ir-last-list-item (cdr-atom $term)) $term))

; --- kb scoping --------------------------------------------------------------
; Goal-level terms are scoped by the IR's own kb field: ($kb-triple $term).
; compile.metta scopes every item with a kb triple ($kb $ctx $vars) — MAIN/Nil
; for ordinary statements (kbctx), a numbered assumption context for query
; premises. Rule items share *free* ctx/vars variables between premises and
; conclusion, so rules are context-generic while facts stay context-specific;
; assumption facts therefore only feed derivations inside their own context.
; Plain kb symbols (base-rate fold args) scope like kbctx does.

(= (mm2-ir-scope-kb $kb) (if (is-expr $kb) $kb ($kb MAIN Nil)))

(= (mm2-ir-open-inheritance-pattern? $pat)
   (and (= $pat (Inheritance $subj $concept))
        (and (is-var $subj) (is-var $concept))))

(= (mm2-ir-subject-open-inheritance-pattern? $pat)
   (and (= $pat (Inheritance $subj $concept))
        (and (is-var $subj) (not (is-var $concept)))))

; --- premise/conclusion item classification --------------------------------

(= (mm2-ir-item $item)
   (case $item
     (((: $shape $prf $ptype $tv) (subgoal ($shape $ptype) $tv $prf))
      ((CPU $formula $args $out) (cpu $formula $args $out))
      (($ptype $shape $prf $tv) (subgoal ($shape $ptype) $tv $prf))
      ($other (unknown $other)))))

; Split the premise items into an ordered pcons list of subgoal types and the
; list of cpu items (order preserved).
(= (mm2-ir-collect ()) (collected pnil ()))
(= (mm2-ir-collect (cons $item $rest))
   (let (collected $ptypes $cpus) (mm2-ir-collect $rest)
     (case (mm2-ir-item $item)
       (((subgoal $t $v $_prf) (collected (pcons $t $ptypes) $cpus))
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

; Plain base-rate folds map onto the runtime's maintained base-rate relation.
; The non-prior weighted inheritance fold appears for fully open Inheritance
; patterns; for current var-headed STV consequents PeTTa sees no consequent
; base-rate evidence, so the narrow translation below seeds it as no-evidence
; without claiming full weighted inheritance-fold support.
(= (mm2-ir-fold-pattern $cpu)
   (case $cpu
     (((cpu FoldAllCompiled ($kbid $pat extract-tv $zero BaseRateAcc base-rate $resmode) $out)
       (let $skb (mm2-ir-scope-kb $kbid) (brfold ($skb $pat))))
      ((cpu FoldAllCompiled ($kbid $pat (extract-inheritance-tv $kbid2 $pat2) $zero WeightedBaseRateAcc (weighted-base-rate-in-universe $kbid3) $resmode) $out)
       (if (and (== $kbid $kbid2)
                (and (== $kbid $kbid3)
                     (and (== $pat $pat2) (mm2-ir-open-inheritance-pattern? $pat))))
         (let $skb (mm2-ir-scope-kb $kbid) (weighted-brfold ($skb $pat)))
         unsupported-fold))
      ((cpu FoldAllCompiled
         ($kbid
          $pat
          (extract-inheritance-tv $kbid2 $pat2)
          (BaseRateEvidenceWithPrior
            (ConceptNodePriorRuntime $kbid3 $concept)
            (BaseRateEvidence 0.0 0.0))
          WeightedBaseRateWithPriorAcc
          (weighted-base-rate-with-prior-in-universe $kbid4)
          $resmode)
         $out)
       (if (and (== $kbid $kbid2)
                (and (== $kbid $kbid3)
                     (and (== $kbid $kbid4)
                          (and (== $pat $pat2)
                               (mm2-ir-subject-open-inheritance-pattern? $pat)))))
         (let $skb (mm2-ir-scope-kb $kbid)
           (prior-weighted-brfold ($skb $pat) $kbid $concept))
         unsupported-fold))
      ($other unsupported-fold))))

(= (mm2-ir-stv-fold-supported? $fold)
   (case $fold
     (((brfold $_pat) true)
      ((weighted-brfold $_pat) true)
      ((prior-weighted-brfold $_pat $_kb $_concept) true)
      ($other false))))

(= (mm2-ir-inv-fold-supported? $fold)
   (case $fold
     (((brfold $_pat) true)
      ((prior-weighted-brfold $_pat $_kb $_concept) true)
      ($other false))))

(= (mm2-ir-fold-key $fold)
   (case $fold
     (((brfold $pat) $pat)
      ((weighted-brfold $pat) $pat)
      ((prior-weighted-brfold $pat $_kb $_concept) $pat)
      ($other unsupported-fold))))

(= (mm2-ir-fold-support $fold)
   (case $fold
     (((brfold $pat) (mm2-base-rate-support $pat))
      ((weighted-brfold $pat) (base-rate (copy_term $pat) (0.0 0.0)))
      ((prior-weighted-brfold $pat $kb $concept)
       (mm2-prior-base-rate-support $pat $kb $concept))
      ($other (notsupported-ir (fold-support $other))))))

(= (mm2-guarded-base-rate-key $rule-id $role $pat)
   (guarded-base-rate (copy_term $rule-id) $role (copy_term $pat)))

(= (mm2-guarded-base-rate-support $pat $rule-id $role)
   (let* (($key (mm2-guarded-base-rate-key $rule-id $role $pat))
          ($match (copy_term $pat))
          ($guard (copy_term $rule-id))
          ($seed (copy_term $key)))
     (superpose (
       (base-rate-def-guarded $key $match $guard without-rule)
       (base-rate $seed (0.0 0.0))))))

(= (mm2-local-guarded-base-rate-support $pat $rule-id $role)
   (let* (($key (mm2-guarded-base-rate-key $rule-id $role $pat))
          ($match (copy_term $pat))
          ($guard (copy_term $rule-id))
          ($seed (copy_term $key)))
     (superpose (
       (base-rate-def-guarded $key $match $guard without-rule-instance)
       (base-rate $seed (0.0 0.0))))))

(= (mm2-guarded-prior-base-rate-key $rule-id $role $pat)
   (guarded-prior-base-rate (copy_term $rule-id) $role (copy_term $pat)))

(= (mm2-guarded-prior-base-rate-support $pat $rule-id $role $kb $concept)
   (let* (($key (mm2-guarded-prior-base-rate-key $rule-id $role $pat))
          ($match (copy_term $pat))
          ($guard (copy_term $rule-id))
          ($seed (copy_term $key)))
     (superpose (
       (base-rate-prior-def-guarded $key $match $guard $kb $concept)
       (base-rate $seed (0.0 0.0))))))

(= (mm2-ir-guarded-fold-key $rule-id $role $fold)
   (case $fold
     (((brfold $pat) (mm2-guarded-base-rate-key $rule-id $role $pat))
      ((prior-weighted-brfold $pat $_kb $_concept)
       (mm2-guarded-prior-base-rate-key $rule-id $role $pat))
      ($other (mm2-ir-fold-key $other)))))

(= (mm2-ir-guarded-fold-support $rule-id $role $fold)
   (case $fold
     (((brfold $pat) (mm2-guarded-base-rate-support $pat $rule-id $role))
      ((prior-weighted-brfold $pat $kb $concept)
       (mm2-guarded-prior-base-rate-support $pat $rule-id $role $kb $concept))
      ($other (mm2-ir-fold-support $other)))))

(= (mm2-ir-and-fold? $fold)
   (case $fold
     (((brfold ($_scope (And $_a $_b))) true)
      ((brfold ($_scope (And $_a $_b $_c))) true)
      ((brfold ($_scope (And $_a $_b $_c $_d))) true)
      ((brfold ($_scope (And $_a $_b $_c $_d $_e))) true)
      ($_other false))))

(= (mm2-ir-stv-runtime-kind $rid $pos $fa $fb)
   (if (mm2-ir-and-fold? $fa)
     (stv-local
       $pos
       (rule-brpat
         $rid
         (mm2-ir-guarded-fold-key $rid antecedent $fa)
         (mm2-ir-guarded-fold-key $rid consequent $fb)))
     (stv
       $pos
       (brpat
         (mm2-ir-guarded-fold-key $rid antecedent $fa)
         (mm2-ir-guarded-fold-key $rid consequent $fb)))))

(= (mm2-ir-stv-fold-support $rid $role $antecedent-fold $fold)
   (if (mm2-ir-and-fold? $antecedent-fold)
     (case $fold
       (((brfold $pat) (mm2-local-guarded-base-rate-support $pat $rid $role))
        ($other (mm2-ir-guarded-fold-support $rid $role $other))))
     (mm2-ir-guarded-fold-support $rid $role $fold)))

(= (mm2-ir-keyed-fold-key $rule-id $role $fold)
   (case $fold
     (((brfold $pat) (mm2-base-rate-key $rule-id $role $pat))
      ($other (mm2-ir-fold-key $other)))))

(= (mm2-ir-keyed-fold-support $rule-id $role $fold)
   (case $fold
     (((brfold $pat)
       (superpose (
         (mm2-base-rate-support $rule-id $role $pat)
         (mm2-base-rate-support $pat))))
      ($other (mm2-ir-fold-support $other)))))

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

(= (mm2-ir-foldall-dist-average $cpu)
   (case $cpu
     (((cpu FoldAllCompiled
        ($kbid
         $pat
         (extract-value $pat2 $value)
         (SumCount $_zero 0)
         DistSumCountAcc
         dist-average
         result-tv)
        $out)
       (if (== $pat $pat2)
         (let $skb (mm2-ir-scope-kb $kbid) (fold-dist-average ($skb $pat) $value $out))
         unsupported-foldall))
      ($other unsupported-foldall))))

(= (mm2-ir-foldall-bernoulli $cpu)
   (case $cpu
     (((cpu FoldAllCompiled
        ($kbid
         $pat
         extract-tv
         (ParticleDist $init-pid $init-scale)
         ParticleAddBernoulliFromSTV
         identity
         result-tv)
       $out)
       (let $skb (mm2-ir-scope-kb $kbid)
         (fold-value-bernoulli
           ($skb $pat)
           (mm2-ir-last-arg $pat)
           (ParticleDist $init-pid $init-scale)
           $out)))
      ($other unsupported-foldall))))

(= (mm2-ir-foldall-or $cpu)
   (case $cpu
     (((cpu FoldAllCompiled ($kbid $pat extract-tv (STV 0.0 1.0) OrFormula identity result-tv) $out)
       (let $skb (mm2-ir-scope-kb $kbid) (fold-or ($skb $pat) $out)))
      ((cpu GroupedFoldAllCompiled ($kbid $pat $_group-vars extract-tv (STV 0.0 1.0) OrFormula identity result-tv) $out)
       ; Variables shared by the result goal and $pat remain unbound in the
       ; emitted foldall-or-ctv atom. MORK's sink therefore groups matches by
       ; exactly the compiler-provided result key without a second mechanism.
       (let $skb (mm2-ir-scope-kb $kbid) (fold-or ($skb $pat) $out)))
      ($other unsupported-foldall))))

(= (mm2-ir-foldall-total-evidence $cpu)
   (case $cpu
     (((cpu FoldAllCompiled
        ($kbid
         (TotalEvidence $case $p1 $p2 $x $case-tv)
         (extract-value
           (TotalEvidence $case $p1 $p2 $x $case-tv)
           (EvidenceCase $case $case-tv))
         (TotalEvidenceTvs none none)
         TotalEvidenceAcc
         identity
         result-tv)
        $out)
       (let $skb (mm2-ir-scope-kb $kbid)
         (fold-total-evidence
           $skb
           $p1
           $p2
           $out)))
      ($other unsupported-foldall))))

(= (mm2-ir-stv-kind $pos $fa $fb $tail)
   (if (and (mm2-ir-stv-fold-supported? $fa)
            (mm2-ir-stv-fold-supported? $fb))
     (stv-kind $pos $fa $fb)
     (unsupported-tail $tail)))

(= (mm2-ir-inv-kind $pos $fa $fb $mode $tail)
   (if (and (mm2-ir-inv-fold-supported? $fa)
            (mm2-ir-inv-fold-supported? $fb))
     (inv-kind $pos $fa $fb $mode)
     (unsupported-tail $tail)))

(= (mm2-ir-foldall-ctv-kind $fold $agg $agg2 $ps $pc $ns $nc $tail)
   (case (mm2-ir-foldall-dist-average $fold)
     (((fold-dist-average $pat $value $dist-out)
       (if (and (== $agg $agg2)
                (and (== $ps 1.0)
                     (and (== $pc 1.0)
                          (and (== $ns 0.0) (== $nc 1.0)))))
         (avg-dist-ctv-kind $pat $value $dist-out ($ps $pc) ($ns $nc))
         (unsupported-tail $tail)))
      ($other
       (case (mm2-ir-foldall-bernoulli $fold)
         (((fold-value-bernoulli $pat $source $init $dist-out)
           (if (== $agg $agg2)
             (fold-value-bernoulli-ctv-kind $pat $source $init $dist-out ($ps $pc) ($ns $nc))
             (unsupported-tail $tail)))
          ($other2 (unsupported-tail $tail))))))))

(= (mm2-ir-classify $tail)
   (case $tail
     ((() identity)
      ((cons (cpu AndProjection ($tvin $ev) $out) ()) (proj-kind and))
      ((cons (cpu OrProjection ($tvin $ev) $out) ()) (proj-kind or))
      ((cons (cpu AndMarginalProjection ($tvin) $out) ()) (proj-kind marg))
      ((cons (cpu NotFormula ($tvin) $out) ()) (proj-kind not))
      ((cons
         (cpu FoldAllCompiled
           ($kb
            (MemberInheritanceSample $obj $subj $concept $ante-tv $consequent-tv)
            (extract-value
              (MemberInheritanceSample $obj $subj $concept $ante-tv $consequent-tv)
              (WeightedTv $ante-tv $consequent-tv))
            (BaseRateEvidence 0.0 0.0)
            WeightedBaseRateAcc
            (member-inheritance $kb)
            result-tv)
           $fold-out)
         (cons (cpu MemberInheritanceEvidenceFormula ($fold-out) $out) ()))
       (member-inheritance-fold-kind
         $kb
         $subj
         $concept
         ((mm2-ir-scope-kb $kb)
          (MemberInheritanceSample $obj $subj $concept $ante-tv $consequent-tv))))
      ((cons (cpu CTVModusPonensFormula ($agg (CTV (STV $ps $pc) (STV $ns $nc))) $out) ())
       (ctv-kind ($ps $pc) ($ns $nc)))
      ((cons (cpu + ($lhs $rhs) $res)
         (cons (cpu AndFormula ($prem-tv (STV 1.0 1.0)) $agg1)
           (cons (cpu AndFormula ($agg1b $next-tv) $agg2)
             (cons (cpu CTVModusPonensFormula ($agg2b (CTV (STV $ps $pc) (STV $ns $nc))) $out) ()))))
       (if (and (== $agg1 $agg1b) (== $agg2 $agg2b))
         (compute-plus-ctv-kind $lhs $rhs $res ($ps $pc) ($ns $nc))
         (unsupported-tail $tail)))
      ((cons (cpu DistMap2Formula ($fun $lhs $rhs) $dist-out)
         (cons (cpu AndFormula ($prem-tv (STV 1.0 1.0)) $agg)
           (cons (cpu CTVModusPonensFormula ($agg2 (CTV (STV $ps $pc) (STV $ns $nc))) $out) ())))
       (if (and (== $agg $agg2)
                (and (== $ps 1.0)
                     (and (== $pc 1.0)
                          (and (== $ns 0.0) (== $nc 1.0)))))
         (dist-map2-ctv-kind $fun $lhs $rhs $dist-out ($ps $pc) ($ns $nc))
         (unsupported-tail $tail)))
      ((cons (cpu DistGreaterThanFormula ($dist $threshold) $gt-tv)
         (cons (cpu AndFormula ($prem-tv $gt-tv2) $agg)
           (cons (cpu CTVModusPonensFormula ($agg2 (CTV (STV $ps $pc) (STV $ns $nc))) $out) ())))
       (if (and (== $gt-tv $gt-tv2) (== $agg $agg2))
         (dist-gt-ctv-kind $dist $threshold ($ps $pc) ($ns $nc))
         (unsupported-tail $tail)))
      ((cons (cpu DistGreaterThanDistFormula ($lhs $rhs) $gt-tv)
         (cons (cpu AndFormula ($prem-tv $gt-tv2) $agg)
           (cons (cpu CTVModusPonensFormula ($agg2 (CTV (STV $ps $pc) (STV $ns $nc))) $out) ())))
       (if (and (== $gt-tv $gt-tv2) (== $agg $agg2))
         (dist-gt-dist-ctv-kind $lhs $rhs ($ps $pc) ($ns $nc))
         (unsupported-tail $tail)))
      ((cons (cpu FoldAllCompiled $fold-args $fold-out)
         (cons (cpu AndFormula ($prem-tv (STV 1.0 1.0)) $agg)
           (cons (cpu CTVModusPonensFormula ($agg2 (CTV (STV $ps $pc) (STV $ns $nc))) $out) ())))
       (mm2-ir-foldall-ctv-kind (cpu FoldAllCompiled $fold-args $fold-out) $agg $agg2 $ps $pc $ns $nc $tail))
      ((cons (cpu NotFormula ($tvin) $not)
         (cons (cpu CTVModusPonensFormula ($not2 (CTV (STV $ps $pc) (STV $ns $nc))) $out) ()))
       (if (== $not $not2)
         (premise-not-mp-kind ($ps $pc) ($ns $nc))
         (unsupported-tail $tail)))
      ((cons (cpu NotFormula ($tvin) $not)
         (cons (cpu AndFormula ($not2 $other) $agg)
           (cons (cpu CTVModusPonensFormula ($agg2 (CTV (STV $ps $pc) (STV $ns $nc))) $out) ())))
       (if (and (== $not $not2) (== $agg $agg2))
         (not-and-ctv-kind ($ps $pc) ($ns $nc))
         (unsupported-tail $tail)))
      ((cons (cpu NotFormula ($tvin) $not)
         (cons (cpu AndFormula ($not2 $other) $agg) ()))
       (if (== $not $not2)
         (not-first-kind $agg)
         (unsupported-tail $tail)))
      ((cons (cpu OrFormula ($lhs $rhs) $or-out) $rest)
       (mm2-ir-classify-or-tail $or-out $rest $tail))
      ((cons (cpu CTVModusPonensFormula ($agg (CTV (STV $ps $pc) (STV $ns $nc))) $out)
         (cons (cpu NotFormula ($out2) $final) ()))
       (mp-conclusion-not-kind ($ps $pc) ($ns $nc)))
      ((cons (cpu NotEqual ($p1 $p2) true)
         (cons $fold
           (cons (cpu TotalEvidenceCTVModusPonensFormula ($atv $evidence-tvs) $out) ())))
       (case (mm2-ir-foldall-total-evidence $fold)
         (((fold-total-evidence $fold-scope $fp1 $fp2 $fold-out)
           (if (and (=alpha $fold-out $evidence-tvs)
                    (and (=alpha $p1 $fp1) (=alpha $p2 $fp2)))
             (total-evidence-ctv-kind $p1 $p2 $fold-scope)
             (unsupported-tail $tail)))
          ($other (unsupported-tail $tail)))))
      ((cons $fold
         (cons (cpu CTVModusPonensFormula ($agg (CTV (STV $ps $pc) (STV $ns $nc))) $out) ()))
       (case (mm2-ir-foldall-or $fold)
         (((fold-or $pat $fold-out)
           (if (== $fold-out $agg)
             (fold-or-ctv-kind $pat ($ps $pc) ($ns $nc))
             (unsupported-tail $tail)))
          ($other (unsupported-tail $tail)))))
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
                        (mm2-ir-inv-mode $rule-tv)
                        $tail))
      ($other (unsupported-tail $other)))))

(= (mm2-ir-classify-or-tail $or-out $rest $tail)
   (case $rest
     ((() adapter-or-kind)
      ((cons (cpu OrFormula ($lhs $rhs) $next-out) $next-rest)
       (mm2-ir-classify-or-tail $next-out $next-rest $tail))
      ((cons (cpu OrProjection ($tvin $ev) $out) ())
       (if (== $or-out $ev)
         ignore-kind
         (unsupported-tail $tail)))
      ($other (unsupported-tail $tail)))))

; Total-implication rules assemble their conclusion TV structurally as
; (CTV $pos-tv $neg-tv) from the two context conclusions' TVs -- there is no
; CPU item, so they classify as identity; the CTV-shaped conclusion TV (a
; bound expression, never a free result var) distinguishes them from adapter
; chains.
(= (mm2-ir-refine-total-evidence-kind $kind $case $case-tv $ctv)
   (case $kind
     ((identity
       (if (== $case-tv $ctv)
         (total-evidence-case $case)
         $kind))
      ((not-first-kind $agg)
       (if (and (== $case-tv $ctv) (== $agg $ctv))
         (not-first-kind (total-evidence-case $case))
         (unsupported-tail (total-evidence-tv $case-tv $ctv $agg))))
      ($other $kind))))

(= (mm2-ir-refine-non-total-kind $kind $ctv)
   (case $kind
     (((not-first-kind $agg)
       (if (== $agg $ctv)
         (not-first-kind identity)
         (unsupported-tail (not-first-tv $agg $ctv))))
      ($k2
       (if (and (== $k2 identity) (is-expr $ctv))
         (case $ctv
           (((CTV $pos $neg) (proj-kind ctvpair))
           ($other2 $k2)))
         $k2)))))

(= (mm2-ir-var-output-scaffold? $tail)
   (case $tail
     (((cons (cpu GroupedFoldAllCompiled $fold-args $fold-tv)
        (cons (cpu AndFormula ($lhs $fold-tv2) $agg)
          (cons (cpu CTVModusPonensFormula ($agg2 (CTV (STV 1.0 1.0) (STV 0.0 1.0))) $mp)
            (cons (cpu NotFormula ($mp2) $out) ()))))
       (and (== $fold-tv $fold-tv2)
            (and (== $agg $agg2) (== $mp $mp2))))
      ($other false))))

(= (mm2-ir-refine-var-kind $kind $ctv)
   (case $kind
     (((unsupported-tail $tail)
       (if (mm2-ir-var-output-scaffold? $tail)
         ignore-kind
         $kind))
      ($other (mm2-ir-refine-non-total-kind $kind $ctv)))))

(= (mm2-ir-refine-kind $kind $ctype $ctv)
   (case $ctype
     ((($scope $term)
       (if (is-var $term)
         (mm2-ir-refine-var-kind $kind $ctv)
         (case $term
           (((TotalEvidence pos $p1 $p2 $x $case-tv)
             (mm2-ir-refine-total-evidence-kind $kind pos $case-tv $ctv))
            ((TotalEvidence neg $p1 $p2 $x $case-tv)
             (mm2-ir-refine-total-evidence-kind $kind neg $case-tv $ctv))
            ($other (mm2-ir-refine-non-total-kind $kind $ctv))))))
      ($other (mm2-ir-refine-non-total-kind $kind $ctv)))))

(= (mm2-ir-rule-pos (CTV (STV $ps $pc) $neg)) ($ps $pc))
(= (mm2-ir-rule-pos (STV $s $c)) ($s $c))

(= (mm2-ir-inv-mode (CTV $pos $neg)) unguarded)
(= (mm2-ir-inv-mode (STV $s $c)) guarded)

; --- statement translation ---------------------------------------------------
; Each translation superposes the mm2 atoms for one IR statement.

(= (mm2-ir-emit-rule $_rid $ctype $ptypes identity)
   (adapterN $ctype $ptypes))

(= (mm2-ir-emit-rule $rid $ctype $ptypes inheritance-query-result)
   (case $ptypes
     (((pcons $pos (pcons $neg pnil))
       (ruleN $ctype $rid inheritance-query-result $ptypes))
      ($other
       (notsupported-ir
         (inheritance-query-result-premises $ctype $other))))))

(= (mm2-ir-emit-rule $_rid $ctype $ptypes adapter-or-kind)
   (adapterOrN $ctype $ptypes))

(= (mm2-ir-emit-rule $_rid $_ctype $_ptypes ignore-kind)
   (empty))

(= (mm2-ir-emit-rule $rid $ctype $ptypes (proj-kind $op))
   (ruleN $ctype $rid (proj $op) $ptypes))

(= (mm2-ir-emit-rule $rid $ctype $ptypes (ctv-kind $pos $neg))
   (superpose (
     (ruleN $ctype $rid (ctv $pos $neg) $ptypes)
     (mm2-ir-forward-chain-goal-marker $ctype))))

(= (mm2-ir-emit-rule $rid $ctype $ptypes (compute-plus-ctv-kind $lhs $rhs $res $pos $neg))
   (ruleN $ctype $rid (compute-plus-ctv $pos ($lhs $rhs $res $neg)) $ptypes))

(= (mm2-ir-emit-rule $rid $ctype $ptypes (dist-map2-ctv-kind $fun $lhs $rhs $dist-out $pos $neg))
   (let $result-dist (ParticleDist (dist-map2 $fun $lhs $rhs) 1.0)
     (ruleN
       (mm2-ir-dist-map2-conclusion $ctype $dist-out $result-dist)
       $rid
       (dist-map2-ctv $pos (map2 $fun $lhs $rhs $neg))
       $ptypes)))

(= (mm2-ir-emit-rule $rid $ctype $ptypes (dist-gt-ctv-kind $dist $threshold $pos $neg))
   (ruleN $ctype $rid (dist-gt-ctv $pos (gt $dist $threshold $neg)) $ptypes))

(= (mm2-ir-emit-rule $rid $ctype $ptypes (dist-gt-dist-ctv-kind $lhs $rhs $pos $neg))
   (ruleN $ctype $rid (dist-gt-dist-ctv $pos (gt2 $lhs $rhs $neg)) $ptypes))

(= (mm2-ir-emit-rule $rid $ctype $ptypes (avg-dist-ctv-kind $pat $value $dist-out $pos $neg))
   (case (mm2-ir-dist-avg-rule-data $ctype $dist-out)
     (((dist-avg-rule-data $result-ctype $result-pid)
       (ruleN
         $result-ctype
         $rid
         (avg-dist-ctv $pos (avg $result-pid $pat $value $neg))
         $ptypes))
      ($other $other))))

(= (mm2-ir-emit-rule $rid $ctype $ptypes (fold-value-bernoulli-ctv-kind $pat $source $init $dist-out $pos $neg))
   (case (mm2-ir-dist-sum-rule-data $ctype $dist-out)
     (((dist-sum-rule-data $result-ctype $result-pid)
       (superpose (
         (ruleN
           $result-ctype
           $rid
           (fold-value-bernoulli-ctv $pos (bernoulli $result-pid $pat $source $init $neg))
           $ptypes)
         (mm2-ir-superpose-list (mm2-ir-dist-atoms $init)))))
      ($other $other))))

(= (mm2-ir-emit-rule $rid $ctype $ptypes (premise-not-mp-kind $pos $neg))
   (ruleN $ctype $rid (premise-not-mp $pos $neg) $ptypes))

(= (mm2-ir-emit-rule $rid $ctype $ptypes (mp-conclusion-not-kind $pos $neg))
   (ruleN $ctype $rid (mp-conclusion-not $pos $neg) $ptypes))

(= (mm2-ir-emit-rule $rid $ctype $ptypes (not-and-ctv-kind $pos $neg))
   (case $ptypes
     (((pcons ($scope $prem) $rest)
       (let $not-prem ($scope (Not $prem))
         (superpose (
           (ruleN $not-prem $rid (proj not) (pcons ($scope $prem) pnil))
           (ruleN $ctype $rid (ctv $pos $neg) (pcons $not-prem $rest))))))
      ($other (notsupported-ir (not-and-ctv $ctype $ptypes))))))

(= (mm2-ir-emit-rule $rid $ctype $ptypes (fold-or-ctv-kind $pat $pos $neg))
   (case $ptypes
     ((pnil (foldall-or-ctv $ctype $rid $pos $neg $pat))
      ($other (notsupported-ir (foldall-or-with-premises $ctype $ptypes))))))

(= (mm2-ir-emit-rule $rid $ctype $ptypes (total-evidence-case $case))
   (ruleN $ctype $rid (total-evidence-case $case) $ptypes))

(= (mm2-ir-emit-rule $rid $ctype $ptypes (not-first-kind $final-kind))
   (case $ptypes
     (((pcons $prem $rest) (ruleN $ctype $rid (not-first $final-kind) $ptypes))
      ($other (notsupported-ir (not-first-without-premise $ctype $ptypes))))))

(= (mm2-ir-emit-rule $rid $ctype $ptypes (total-evidence-ctv-kind $p1 $p2 $fold-scope))
   (case $ptypes
     (((pcons $prem pnil)
       (ruleN $ctype $rid (total-evidence-ctv $p1 $p2 $fold-scope) $ptypes))
      ($other (notsupported-ir (total-evidence-ctv-premises $ctype $ptypes))))))

(= (mm2-ir-member-inheritance-confidence-mode $kb)
   (case
     (collapse
       (match &mork
         (mm2-universe-size $kb $n)
         (universe-size $n)))
     ((() count-confidence)
      ((cons (universe-size $n) $_rest) (universe-confidence $n)))))

(= (mm2-ir-member-inheritance-cache-has-sample? $scope $subj $concept)
   (not
     (==
       (collapse
         (once
           (match &mork
             (member-inheritance-source-proof
               ($scope (Member $obj $subj)) $_ante-proof)
             (match &mork
               (member-inheritance-source-proof
                 ($scope (Member $obj $concept)) $_consequent-proof)
               sample))))
       ())))

(= (mm2-ir-member-inheritance-cache-bootstrap $ctype $sample-type)
   (case $sample-type
     ((($scope
         (MemberInheritanceSample
           $_obj $subj $concept $_ante-tv $_consequent-tv))
       (case
         (collapse
           (match &mork
             (member-inheritance-cache-def
               (member-inheritance-cache $scope $subj $concept)
               $scope $subj $concept)
             cached))
         ((()
           (if (mm2-ir-member-inheritance-cache-has-sample?
                 $scope $subj $concept)
             (member-inheritance-cache-bootstrap
               (member-inheritance-cache
                 (copy_term $scope)
                 (copy_term $subj)
                 (copy_term $concept))
               (copy_term $scope)
               (copy_term $subj)
               (copy_term $concept))
             (empty)))
          ($_cached (empty)))))
      ($_other
       (notsupported-ir
         (member-inheritance-cache-shape $ctype $sample-type))))))

(= (mm2-ir-member-inheritance-cold-query
      $ctype $sample-type $rid $mode)
   (case $sample-type
     ((($scope
         (MemberInheritanceSample
           $_obj $subj $concept $_ante-tv $_consequent-tv))
       (case
         (collapse
           (match &mork
             (member-inheritance-cache-def
               (member-inheritance-cache $scope $subj $concept)
               $scope $subj $concept)
             cached))
         ((()
           (if (mm2-ir-member-inheritance-cache-has-sample?
                 $scope $subj $concept)
             (empty)
             (member-inheritance-cold-query
               $ctype $sample-type $rid $mode)))
          ($_cached (empty)))))
      ($_other (empty)))))

(= (mm2-ir-emit-rule
      $rid
      $ctype
      $ptypes
      (member-inheritance-fold-kind $kb $_subj $_concept $sample-type))
   (case $ptypes
     ((pnil
       (let $mode (mm2-ir-member-inheritance-confidence-mode $kb)
         (superpose (
           (member-inheritance-query
             $ctype $sample-type $rid $mode)
           (mm2-ir-member-inheritance-cache-bootstrap $ctype $sample-type)
           (mm2-ir-member-inheritance-cold-query
             $ctype $sample-type $rid $mode)))))
      ($other
       (notsupported-ir
         (member-inheritance-fold-premises $ctype $ptypes))))))

(= (mm2-ir-emit-rule $_rid $ctype $ptypes (fold-sum-kind $pat $value $out))
   (case $ptypes
     ((pnil
       (let $result-copy (copy_term $ctype)
         (case $result-copy
           ((($scope (FoldAll $qpat $qvalue $zero $fun -> $out-copy))
             (let (fold-source $pat-copy $value-copy) (copy_term (fold-source $pat $value))
               (foldall-sum $result-copy $out-copy $pat-copy $value-copy)))
            ($other (notsupported-ir (foldall-result-copy $ctype)))))))
      ($other (notsupported-ir (foldall-with-premises $ctype $ptypes))))))

(= (mm2-ir-emit-rule $_rid $ctype $ptypes (fold-pair-counts-kind $pat $value $out))
   (case $ptypes
     ((pnil
       (let $result-copy (copy_term $ctype)
         (case $result-copy
           ((($scope (FoldAll $qpat $qvalue $zero $fun -> $out-copy))
             (let (fold-source $pat-copy $value-copy) (copy_term (fold-source $pat $value))
               (foldall-pair-counts $result-copy $out-copy $pat-copy $value-copy)))
            ($other (notsupported-ir (foldall-result-copy $ctype)))))))
      ($other (notsupported-ir (foldall-with-premises $ctype $ptypes))))))

(= (mm2-ir-emit-rule $rid $ctype $ptypes (stv-kind $pos $fa $fb))
   (case ($fa $fb)
     ((((prior-weighted-brfold $_apat $kb $ante-concept)
        (prior-weighted-brfold $_cpat $kb $cons-concept))
       (superpose (
         (ruleN
           $ctype
           $rid
           (stv-prior $pos (prior-brpat $kb $ante-concept $cons-concept))
           $ptypes)
         (mm2-ir-guarded-fold-support $rid antecedent $fa)
         (mm2-ir-guarded-fold-support $rid consequent $fb))))
      ($other
       (superpose (
         (ruleN
           $ctype
           $rid
           (mm2-ir-stv-runtime-kind $rid $pos $fa $fb)
           $ptypes)
         (mm2-ir-stv-fold-support $rid antecedent $fa $fa)
         (mm2-ir-stv-fold-support $rid consequent $fa $fb)))))))

(= (mm2-ir-inv-evidence-id $rid)
   (case $rid
     ((((inverted $base with $_pa $_pb) $_wit) $base)
      ((inverted $base with $_pa $_pb) $base)
      ($other $other))))

; BiImplication compileadd already emits both direct directional rules
; (bi-forward and bi-backward). Inverting those generated directions adds a
; redundant, weaker proof path that can race ahead of the direct proof in
; query-assumption contexts.
(= (mm2-ir-bidirectional-inverse? $rid)
   (case $rid
     ((((inverted (bi-forward $base) with $_pa $_pb) $_wit) true)
      (((inverted (bi-backward $base) with $_pa $_pb) $_wit) true)
      ((inverted (bi-forward $base) with $_pa $_pb) true)
      ((inverted (bi-backward $base) with $_pa $_pb) true)
      ($other false))))

(= (mm2-ir-inv-fold-key-for-mode unguarded $rid $role $fold) (mm2-ir-keyed-fold-key $rid $role $fold))
(= (mm2-ir-inv-fold-key-for-mode guarded $rid $role $fold) (mm2-ir-guarded-fold-key $rid $role $fold))

(= (mm2-ir-inv-fold-support-for-mode unguarded $rid $role $fold) (mm2-ir-keyed-fold-support $rid $role $fold))
(= (mm2-ir-inv-fold-support-for-mode guarded $rid $role $fold) (mm2-ir-guarded-fold-support $rid $role $fold))

(= (mm2-ir-forward-chain-goal-marker ($scope $type))
   (forward-chain-goal $scope ($scope $type)))
(= (mm2-ir-forward-chain-goal-marker $_other) (empty))

(= (mm2-ir-open-forward-chain-goal $fb)
   (let $g (copy_term (mm2-ir-fold-key $fb))
     (superpose (
       (, (Goal $g))
       (mm2-ir-forward-chain-goal-marker $g)))))

(= (mm2-ir-inv-materialization-goal unguarded $_rid $fb)
   (mm2-ir-open-forward-chain-goal $fb))
; Guarded STV inverses are backward-query rules. Eagerly opening their
; consequent population during forward chaining manufactures inverse facts
; that PeTTa's forward frontier never observed and feeds them back into later
; base-rate folds. The forward observation cache is the only approximation;
; a backward query can still refine through the inverse rule below.
(= (mm2-ir-inv-materialization-goal guarded $_rid $_fb) (empty))

(= (mm2-ir-emit-rule $rid $ctype $ptypes (inv-kind $pos $fa $fb $mode))
   (if (mm2-ir-bidirectional-inverse? $rid)
     (empty)
     (superpose (
       (ruleN $ctype
              (mm2-ir-inv-evidence-id $rid)
              (inv
                $pos
                (brpat
                  (mm2-ir-inv-fold-key-for-mode $mode $rid antecedent $fa)
                  (mm2-ir-inv-fold-key-for-mode $mode $rid consequent $fb)))
              $ptypes)
       (mm2-ir-inv-fold-support-for-mode $mode $rid antecedent $fa)
       (mm2-ir-inv-fold-support-for-mode $mode $rid consequent $fb)
       (mm2-ir-inv-materialization-goal $mode $rid $fb)))))

(= (mm2-ir-emit-rule $_rid $ctype $ptypes (unsupported-tail $tail))
   (notsupported-ir (rule-tail $ctype $tail)))

(= (mm2-ir-contribution-dirty-marker $g)
   (contribution-dirty (copy_term $g)))

(= (mm2-ir-emit-fact $g $prf ($s $c))
   (case $g
     ((($_scope (Member $_obj $_concept))
       ; Member types are monotonic proof sets. Let the harness install the
       ; first proof as the canonical fact and route later proofs through the
       ; ordinary revise-proofs sink before refreshing member-fold caches.
       (superpose (
         (mm2-member-source-proof
           $g ($s $c) $prf
           (pcons (fact-ev (proof-id $prf) $g) pnil))
         (mm2-ir-contribution-dirty-marker $g)
         (mm2-ir-superpose-list (mm2-ir-dist-atoms $g)))))
      ($_other
       (superpose (
         (fact $g ($s $c))
         (fact-evidence $g ($s $c) (pcons (fact-ev (proof-id $prf) $g) pnil))
         (proved $g ($s $c) $prf (pcons (fact-ev (proof-id $prf) $g) pnil))
         (mm2-ir-contribution-dirty-marker $g)
         (mm2-ir-superpose-list (mm2-ir-dist-atoms $g))))))))

; The TV is is-var-checked before structural matching: a case pattern
; (STV $s $c) would UNIFY with a free tv var (identity-query ctxatoms carry
; one) and emit a wildcard fact with unbound strength/confidence that then
; unifies with every premise lookup.
(= (mm2-ir-fact-stmt $g $prf $tv)
   (if (is-var $tv)
     (notsupported-ir (free-tv-fact $g))
     (case $tv
       (((STV $s $c)
         (if (or (is-var $s) (is-var $c))
           (notsupported-ir (free-tv-fact $g))
           (mm2-ir-emit-fact $g $prf ($s $c))))
        ((CTV (STV $ps $pc) (STV $ns $nc))
         (if (or (or (is-var $ps) (is-var $pc))
                 (or (is-var $ns) (is-var $nc)))
           (notsupported-ir (free-tv-fact $g))
           (mm2-ir-emit-fact $g $prf (ctvpair ($ps $pc) ($ns $nc)))))
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
(= (mm2-ir-query-goal $g $proof)
   (if (and (is-expr $proof)
            (== (car-atom $proof) inheritance-query-result))
     (mm2-query-result $g)
     $g))

(= (mm2-ir-list-to-pcons ()) pnil)
(= (mm2-ir-list-to-pcons (cons $item $rest))
   (pcons $item (mm2-ir-list-to-pcons $rest)))

; Publishing a contextual inheritance proof only needs to wake consequences
; for the same subject.  The complete forward-trigger relation also contains
; generated views for unrelated subjects; embedding those in a producer causes
; an unnecessary proof storm.  Keep ordinary concept chains (Raven -> Bird ->
; flies) as well as IntSet-valued rules (smokes -> cancerous), but not the
; producer's own goal.
(= (mm2-ir-query-downstream? $goal $downstream)
   (case ($goal $downstream)
     (((($goal-scope (Inheritance $goal-subject $_goal-concept))
        ($downstream-scope (Inheritance $downstream-subject $_downstream-concept)))
       (and (=alpha $goal-scope $downstream-scope)
            (and (=alpha $goal-subject $downstream-subject)
                 (not (=alpha $goal $downstream)))))
      ($_other false))))

(= (mm2-ir-filter-query-downstreams $_goal ()) ())
(= (mm2-ir-filter-query-downstreams $goal (cons $downstream $rest))
   (if (mm2-ir-query-downstream? $goal $downstream)
     (cons $downstream (mm2-ir-filter-query-downstreams $goal $rest))
     (mm2-ir-filter-query-downstreams $goal $rest)))

(= (mm2-ir-query-downstreams $goal)
   (mm2-ir-list-to-pcons
     (mm2-ir-filter-query-downstreams
       $goal
       (collapse
         (match &mork
           (forward-trigger $goal $downstream)
           $downstream)))))

(= (mm2-translate-rule-stmt $prems $ccl)
   (let* (((collected $ptypes $cpus) (mm2-ir-collect $prems))
          ((subgoal $ctype $ctv $cprf) (mm2-ir-item $ccl))
          ($kind (mm2-ir-refine-kind
                   (mm2-ir-classify (mm2-ir-drop-and $cpus))
                   $ctype
                   $ctv)))
     (superpose ((mm2-ir-emit-rule $cprf $ctype $ptypes $kind)
                 (mm2-ir-implication-queries $ptypes)))))

(= (mm2-ir-emit-query-rule $cprf $goal $ptypes $kind)
   (if (is-var $cprf)
     (mm2-ir-emit-rule $cprf $goal $ptypes $kind)
     (case $cprf
       ((((inheritance-rule-lift $_rule) $_source $_context)
          ; The proof shape alone is alpha-equivalent across all grounded
          ; applications of the same source rule. Include the premise
          ; signature so each lift owns a distinct private frontier goal,
          ; and capture its dependents so proof publication is a one-atom
          ; event rather than an order-sensitive relational join.
          (let $producer
            (mm2-query-producer
              $cprf $goal $ptypes (mm2-ir-query-downstreams $goal))
            (superpose (
              (mm2-ir-emit-rule $cprf $producer $ptypes $kind)
              (, (Goal $producer))))))
        ($_other (mm2-ir-emit-rule $cprf $goal $ptypes $kind))))))

(= (mm2-ir-inheritance-lift-proof? $proof)
   (and (is-expr $proof)
        (let $head (car-atom $proof)
          (and (is-expr $head)
               (== (car-atom $head) inheritance-rule-lift)))))

(= (mm2-ir-query-add-has-inheritance-lift? ()) false)
(= (mm2-ir-query-add-has-inheritance-lift? (cons $stmt $rest))
   (case $stmt
     (((rules ($_prems |- $ccl))
       (case (mm2-ir-item $ccl)
         (((subgoal $_goal $_tv $proof)
           (if (mm2-ir-inheritance-lift-proof? $proof)
             true
             (mm2-ir-query-add-has-inheritance-lift? $rest)))
          ($_other (mm2-ir-query-add-has-inheritance-lift? $rest)))))
      ($_other (mm2-ir-query-add-has-inheritance-lift? $rest)))))

(= (mm2-translate-query-rule-stmt $prems $ccl)
   (let* (((collected $ptypes $cpus) (mm2-ir-collect $prems))
          ((subgoal $ctype $ctv $cprf) (mm2-ir-item $ccl))
          ($goal (mm2-ir-query-goal $ctype $cprf))
          ($normal-kind (mm2-ir-refine-kind
                          (mm2-ir-classify (mm2-ir-drop-and $cpus))
                          $ctype
                          $ctv))
          ($kind
            (if (is-var $cprf)
              $normal-kind
              (case $cprf
                (((inheritance-query-result
                     (total-implication-frontier $_inner))
                  inheritance-query-result)
                 ($_other $normal-kind))))))
     (superpose ((mm2-ir-emit-query-rule $cprf $goal $ptypes $kind)
                 (mm2-ir-implication-queries $ptypes)))))

(= (mm2-translate-stmt $stmt)
   (case $stmt
      (((: $shape $prf $type $tv)
       (mm2-ir-fact-stmt ($shape $type) $prf $tv))
      ((rules ($prems |- $ccl))
       (mm2-translate-rule-stmt $prems $ccl))
      (($type $shape $prf $tv)
       (mm2-ir-fact-stmt ($shape $type) $prf $tv))
      ($other (notsupported-ir (stmt $other))))))

(= (mm2-translate-all ()) ())
(= (mm2-translate-all (cons $stmt $rest))
   (mm2-ir-append (collapse (mm2-translate-stmt $stmt))
                  (mm2-translate-all $rest)))

; --- query translation --------------------------------------------------------
; (compiled-query ($type $shape $prf $tv) $adds) -> goal atom + translated adds.

(= (mm2-translate-query-stmt $stmt)
   (case $stmt
      (((: $shape $prf $type $tv)
       (mm2-ir-fact-stmt
         (mm2-ir-query-goal ($shape $type) $prf) $prf $tv))
      ((rules ($prems |- $ccl))
       (mm2-translate-query-rule-stmt $prems $ccl))
      (($type $shape $prf $tv)
       (mm2-ir-fact-stmt
         (mm2-ir-query-goal ($shape $type) $prf) $prf $tv))
      ($other (notsupported-ir (query-stmt $other))))))

(= (mm2-translate-query-all ()) ())
(= (mm2-translate-query-all (cons $stmt $rest))
   (mm2-ir-append (collapse (mm2-translate-query-stmt $stmt))
                  (mm2-translate-query-all $rest)))

(= (mm2-translate-query $cq)
   (case $cq
     (((compiled-query $goal-item $adds)
       (let (subgoal $g $tv $prf) (mm2-ir-item $goal-item)
         (let $query-goal (mm2-ir-query-goal $g $prf)
           (cons (, (Goal $query-goal)) (mm2-translate-query-all $adds)))))
      ($other (cons (notsupported-ir (query $other)) ())))))
