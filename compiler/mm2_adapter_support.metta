; MM2-owned support for the PeTTa compiler adapter.
;
; PeTTaChainer's compiler is deliberately the only upstream module used by
; the production harness.  Runtime metadata lives in &mork, and the few
; adapter-side reductions below are namespaced MM2 implementations.

; --- list/control helpers -------------------------------------------------

(= (mm2-foreach-flat $_f ()) ())
(= (mm2-foreach-flat $f (cons $x $xs))
   (progn ($f $x) (mm2-foreach-flat $f $xs)))

(= (mm2-list-len ()) 0)
(= (mm2-list-len (cons $_x $tail)) (+ 1 (mm2-list-len $tail)))

; --- MORK-authoritative KB metadata --------------------------------------

(= (mm2-config-remove-atoms ()) ())
(= (mm2-config-remove-atoms (cons $atom $rest))
   (let $_remove (remove-atom &mork $atom)
     (mm2-config-remove-atoms $rest)))

(= (mm2-config-remove-matches $pattern)
   (mm2-config-remove-atoms (collapse (match &mork $pattern $pattern))))

(= (mm2-config-invalidate-base-rate-entry!
      (base-rate-cache-entry $_pattern user $_tv $_mode))
   ())
(= (mm2-config-invalidate-base-rate-entry!
      (base-rate-cache-entry $pattern $source $tv $mode))
   (let* (($_entry
            (mm2-config-remove-atoms
              ((base-rate-cache-entry $pattern $source $tv $mode))))
          ($_value (mm2-config-remove-matches (base-rate $pattern $old-tv)))
          ($stored (copy_term $pattern))
          ($_seed (add-atom &mork (base-rate $stored (0.0 0.0)))))
     ()))

(= (mm2-config-invalidate-derived-base-rates! $kb)
   (let $entries
     (collapse
       (match &mork
         (base-rate-cache-entry (($kb $ctx $vars) $pattern) $source $tv $mode)
         (base-rate-cache-entry (($kb $ctx $vars) $pattern) $source $tv $mode)))
     (mm2-foreach-flat mm2-config-invalidate-base-rate-entry! $entries)))

(= (mm2-record-concept-node! $kb $node)
   (if (is-var $node)
     ()
     (let $seen (collapse (match &mork (mm2-concept-node $kb $node) true))
       (if (== $seen ()) (add-atom &mork (mm2-concept-node $kb $node)) ()))))

(= (mm2-record-inheritance-nodes! $kb $subj $concept)
   (progn
     (mm2-record-concept-node! $kb $subj)
     (mm2-record-concept-node! $kb $concept)))

(= (mm2-record-inheritance-subject! $kb $subj)
   (if (is-var $subj)
     ()
     (let $seen (collapse (match &mork (mm2-inheritance-subject $kb $subj) true))
       (if (== $seen ())
         (add-atom &mork (mm2-inheritance-subject $kb $subj))
         ()))))

(= (mm2-universe-size-entries $kb)
   (collapse
     (match &mork (mm2-universe-size $kb $n) (mm2-universe-size $kb $n))))

(= (mm2-clear-universe-size $kb)
   (let* (($_old (mm2-config-remove-matches (mm2-universe-size $kb $old)))
          ($_invalidate (mm2-config-invalidate-derived-base-rates! $kb)))
     ()))

(= (mm2-set-universe-size $kb $n)
   (let $_old (mm2-clear-universe-size $kb)
     (add-atom &mork (mm2-universe-size $kb $n))))

(= (mm2-kb-universe-size $kb)
   (case (mm2-universe-size-entries $kb)
     ((() no-universe-size)
      ((cons (mm2-universe-size $_kb $n) $_rest) $n))))

(= (mm2-default-concept-prior-confidence) 0.000001)

(= (mm2-concept-prior-confidence-entries $kb)
   (collapse
     (match &mork
       (mm2-concept-prior-confidence $kb $c)
       (mm2-concept-prior-confidence $kb $c))))

(= (mm2-clear-concept-prior-confidence $kb)
   (let* (($_old
            (mm2-config-remove-matches
              (mm2-concept-prior-confidence $kb $old)))
          ($_invalidate (mm2-config-invalidate-derived-base-rates! $kb)))
     ()))

(= (mm2-set-concept-prior-confidence $kb $c)
   (let $_old (mm2-clear-concept-prior-confidence $kb)
     (add-atom &mork (mm2-concept-prior-confidence $kb $c))))

(= (mm2-kb-concept-prior-confidence $kb)
   (case (mm2-concept-prior-confidence-entries $kb)
     ((() (mm2-default-concept-prior-confidence))
      ((cons (mm2-concept-prior-confidence $_kb $c) $_rest) $c))))

(= (mm2-known-concept-node? $kb $node)
   (not (== (collapse (match &mork (mm2-concept-node $kb $node) true)) ())))

(= (mm2-concept-nodes $kb)
   (list_to_set
     (collapse (match &mork (mm2-concept-node $kb $node) $node))))

(= (mm2-concept-node-prior-tv $kb $node)
   (if (mm2-known-concept-node? $kb $node)
     (let $n (mm2-list-len (mm2-concept-nodes $kb))
       (if (<= $n 0)
         no-evidence
         (STV (/ 1.0 $n) (mm2-kb-concept-prior-confidence $kb))))
     no-evidence))

(= (mm2-observed-inheritance-subject? $kb $subj)
   (not
     (== (collapse (match &mork (mm2-inheritance-subject $kb $subj) true)) ())))

(= (mm2-inheritance-subjects $kb)
   (list_to_set
     (collapse (match &mork (mm2-inheritance-subject $kb $subj) $subj))))

(= (mm2-inheritance-subject-prior-tv $kb $subj)
   (if (mm2-observed-inheritance-subject? $kb $subj)
     (let $universe-size (mm2-kb-universe-size $kb)
       (if (== $universe-size no-universe-size)
         (let $n (mm2-list-len (mm2-inheritance-subjects $kb))
           (if (<= $n 0) no-evidence (STV (/ 1.0 $n) 1.0)))
         (if (<= $universe-size 0.0)
           no-evidence
           (STV (/ 1.0 $universe-size) 1.0))))
     no-evidence))

; --- adapter-side TV reductions -----------------------------------------

(= (mm2-confidence-to-count $confidence)
   (/ (* $confidence 800.0) (- 1.0 (min $confidence 0.9999))))

(= (mm2-count-confidence $count)
   (/ $count (+ $count 800.0)))

(= (mm2-merge-tvs (STV $s1 $c1) (STV $s2 $c2))
   (let* (($n1 (mm2-confidence-to-count $c1))
          ($n2 (mm2-confidence-to-count $c2))
          ($n (+ $n1 $n2)))
     (if (<= $n 0.0)
       (STV (/ (+ $s1 $s2) 2.0) 0.0)
       (STV (/ (+ (* $s1 $n1) (* $s2 $n2)) $n)
            (/ $n (+ $n 800.0))))))

(= (mm2-base-rate-acc (BaseRateEvidence $weighted-sum $confidence-sum)
                       (STV $s $c))
   (BaseRateEvidence
     (+ $weighted-sum (* $s $c))
     (+ $confidence-sum $c)))
(= (mm2-base-rate-acc (BaseRateEvidence $weighted-sum $confidence-sum)
                       (CTV $positive $_negative))
   (mm2-base-rate-acc
     (BaseRateEvidence $weighted-sum $confidence-sum)
     $positive))

(= (mm2-base-rate-tv (BaseRateEvidence $weighted-sum $confidence-sum))
   (if (<= $confidence-sum 0.0)
     no-evidence
     (STV (/ $weighted-sum $confidence-sum)
          (mm2-count-confidence $confidence-sum))))

(= (mm2-weighted-base-rate-acc
      (BaseRateEvidence $weighted-sum $mass-sum)
      (WeightedTv (STV $mass $mass-confidence) (STV $s $c)))
   (let $effective-mass (* (* $mass $mass-confidence) $c)
     (BaseRateEvidence
       (+ $weighted-sum (* $s $effective-mass))
       (+ $mass-sum $effective-mass))))
(= (mm2-weighted-base-rate-acc
      (BaseRateEvidence $weighted-sum $mass-sum)
      (WeightedTv $mass-tv (CTV $positive $_negative)))
   (mm2-weighted-base-rate-acc
     (BaseRateEvidence $weighted-sum $mass-sum)
     (WeightedTv $mass-tv $positive)))
(= (mm2-weighted-base-rate-acc $acc no-evidence) $acc)

(= (mm2-weighted-base-rate-tv (BaseRateEvidence $weighted-sum $mass-sum))
   (if (<= $mass-sum 0.0)
     no-evidence
     (STV (/ $weighted-sum $mass-sum) (min 1.0 $mass-sum))))

(= (mm2-weighted-count-base-rate-tv
      (BaseRateEvidence $weighted-sum $mass-sum))
   (if (<= $mass-sum 0.0)
     no-evidence
     (STV (/ $weighted-sum $mass-sum) (mm2-count-confidence $mass-sum))))

(= (mm2-weighted-universe-base-rate-tv
      $universe-size
      (BaseRateEvidence $weighted-sum $mass-sum))
   (if (or (<= $mass-sum 0.0) (<= $universe-size 0.0))
     no-evidence
     (STV (/ $weighted-sum $mass-sum)
          (min 1.0 (/ $mass-sum $universe-size)))))

(= (mm2-base-rate-with-prior $prior $evidence)
   (if (== $prior no-evidence)
     $evidence
     (if (== $evidence no-evidence)
       $prior
       (mm2-merge-tvs $prior $evidence))))

(= (mm2-uniform-prior-tv $subjects)
   (let $n (mm2-list-len (list_to_set $subjects))
     (if (<= $n 0)
       no-evidence
       (STV (/ 1.0 $n) (mm2-count-confidence $n)))))

(= (mm2-and-projection (STV $compound-s $compound-c)
                        (STV $evidence-s $evidence-c))
   (if (== $evidence-s 0.0)
     (STV 0.0 0.0)
     (STV (min 1.0 (/ $compound-s $evidence-s))
          (min $compound-c $evidence-c))))

(= (mm2-ideal-clip $s) (max 0.000001 (min 0.999999 $s)))

(= (mm2-ideal-var $s $c)
   (let $clipped (mm2-ideal-clip $s)
     (/ (* $clipped (- 1.0 $clipped))
        (+ (mm2-confidence-to-count $c) 1.0))))

(= (mm2-ideal-conf-from-var $s $variance)
   (if (<= $variance 0.0)
     0.9999
     (let* (($clipped (mm2-ideal-clip $s))
            ($max-variance (* $clipped (- 1.0 $clipped)))
            ($bounded-variance (min $variance $max-variance))
            ($count (- (/ $max-variance $bounded-variance) 1.0)))
       (max 0.000001 (/ $count (+ $count 800.0))))))

(= (mm2-ideal-product-confidence $s1 $variance1 $s2 $variance2 $product)
   (let $variance
     (+ (* $variance1 $variance2)
        (+ (* $variance1 (* $s2 $s2))
           (* (* $s1 $s1) $variance2)))
     (mm2-ideal-conf-from-var $product $variance)))

(= (mm2-and-formula (STV $s1 $c1) (STV $s2 $c2))
   (let $product (* $s1 $s2)
     (STV
       $product
       (if (or (<= $c1 0.0) (<= $c2 0.0))
         0.0
         (mm2-ideal-product-confidence
           $s1 (mm2-ideal-var $s1 $c1)
           $s2 (mm2-ideal-var $s2 $c2)
           $product)))))
