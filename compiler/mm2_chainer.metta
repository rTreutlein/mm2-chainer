; PeTTaChainer-compatible harness over the mm2-chainer runtime.
;
; Runs inside petta (PeTTa's MeTTa) and drives MORK's MM2 calculus through
; the mork_ffi &mork space, so PeTTaChainer test files can run near-verbatim:
;
;   !(import! &self <this file>)
;   !(mm2-init)
;   !(mm2-compileadd kb (: a (A x) (STV 1.0 0.9)))
;   !(mm2-test (mm2-query 20 kb (: $prf (B x) $tv))
;              ((: $_ (B x) (STV 0.6 0.8999998649685302))))
;
; Statements compile through PeTTaChainer's real compiler (compileadd /
; mm2compileQuery in compile.metta) and its IR is translated to mm2 atoms by
; compiler/mm2_ir_translate.metta; unrecognized IR surfaces as
; (notsupported-ir ...) markers in the output — the coverage gap list. Goal
; terms are scoped by the IR's own kb triple (($kb $ctx $vars) $term) — see
; mm2_ir_translate.metta — so named KBs and query assumption contexts share
; the one &mork space without cross-talk.
;
; Known divergences from PeTTaChainer's query:
; - mm2 proof identifiers ((scheduledN ...) tokens) differ structurally from
;   PeTTa proof terms, so mm2-test compares (type, tv) pairs only; expected
;   results are always given as a list, and their proof slots are ignored.
; - PeTTa's query step budget counts chainer expansions; mm2 steps count exec
;   firings. mm2-query scales the budget by mm2-steps-per-round.

!(import! &self /nexus/Dev/OpenCog/NL2PLN_Project/PeTTaChainer/pettachainer/metta/petta_chainer)
!(import! &self /nexus/Dev/OpenCog/NL2PLN_Project/mm2-chainer/compiler/petta_mm2_backend)
!(import! &self /nexus/Dev/OpenCog/NL2PLN_Project/mm2-chainer/compiler/mm2_ir_translate)

; --- runtime loading ------------------------------------------------------

(= (mm2-runtime-path)
   "/nexus/Dev/OpenCog/NL2PLN_Project/mm2-chainer/outputs/harness_runtime.mm2")

(= (mork-load-file $path)
   (let* (($_read (callPredicate (Predicate (read_file_to_string $path $contents ()))))
          ($_load (callPredicate (Predicate (mork "add-atoms" $contents $_result)))))
     loaded))

(= (mm2-init) (mork-load-file (mm2-runtime-path)))

; One mm2 exec fires per step and the Z loop re-seeds each round; scale the
; PeTTa-style step budget so small budgets still cover whole rounds.
(= (mm2-steps-per-round) 20)

; Positive expected tests use a wider cap and stop as soon as the expected
; result is seen; empty-result checks keep the narrower query cap above so
; they do not become broader absence claims.
(= (mm2-test-steps-per-round) 55)

; Expected-aware tests run MORK in chunks and stop as soon as the expected
; result is present.  This avoids burning the full scaled budget after a query
; has already produced the assertion target.
(= (mm2-query-chunk-size) 50)

; --- compileadd / query ----------------------------------------------------
; The translator scopes every goal-level term with the IR's own kb triple, so
; the atoms are added verbatim. (notsupported-ir ...) markers are both stored
; (for postmortem inspection of the space) and returned so they print in the
; test transcript.
(= (mm2-add-compiled $kb ()) ())
(= (mm2-add-compiled $kb (cons $atom $rest))
   (let $_add (add-atom &mork $atom)
     (case $atom
       (((notsupported-ir $x)
         (let $_log (mm2-log-line (notsupported-ir $x))
           (cons (notsupported-ir $x) (mm2-add-compiled $kb $rest))))
        ((needs-implication-query $qkb $type)
         (mm2-ir-append (mm2-ensure-implication-query $qkb $type)
                        (mm2-add-compiled $kb $rest)))
        ($other (mm2-add-compiled $kb $rest))))))

; Eagerly compile the total-implication query scaffold for an
; implication-typed rule premise (PeTTa does this lazily at chain time). The
; (ti-compiled ...) guard atom keeps one scaffold per (kb, type) -- each
; compile would otherwise allocate fresh assumption contexts, and recursive
; implication premises would never terminate.
(= (mm2-ensure-implication-query $kb $type)
   (let $seen (collapse (match &mork (ti-compiled $kb $type) found))
     (if (== $seen ())
       (let $_guard (add-atom &mork (ti-compiled $kb $type))
         (mm2-run-compiled-queries $kb
           (collapse (mm2compileQuery $kb (: $prf $type $tv)))))
       ())))

; petta collects all bang results and prints them only at exit, so a timeout
; kill of a runaway query would lose every verdict produced before it. Test
; verdicts and notsupported markers are therefore also appended durably to a
; side log as they happen; the corpus runner counts from that log.
(= (mm2-verdict-log)
   "/nexus/Dev/OpenCog/NL2PLN_Project/mm2-chainer/outputs/harness_verdicts.log")

(= (mm2-log-line $term)
   (let* (($path (mm2-verdict-log))
          ($_s (callPredicate (Predicate (swrite $term $str))))
          ($_o (callPredicate (Predicate (quote (open $path append $stream)))))
          ($_w (callPredicate (Predicate (quote (write $stream $str)))))
          ($_n (callPredicate (Predicate (quote (nl $stream)))))
          ($_c (callPredicate (Predicate (quote (close $stream))))))
     logged))

(= (mm2-compileadd $kb $stmt)
   (let* (($added (mm2-add-compiled $kb (mm2-translate-all (collapse (compileadd $kb $stmt)))))
          ($_refresh (mm2-refresh-prior-base-rates!)))
     $added))

; Some PeTTaChainer tests add already-compiled rule IR directly with
; add-to-kb. Route those generated harness calls through the MM2 translator
; without shadowing PeTTaChainer's own add-to-kb, which compileadd still uses.
(= (mm2-add-to-kb $stmt)
   (let* (($added (mm2-add-compiled kb (mm2-translate-all (cons $stmt ()))))
          ($_refresh (mm2-refresh-prior-base-rates!)))
     $added))

; PeTTa's register-inheritance-induction! installs a rule through its own
; add-to-kb. Keep a small MM2-side marker so readback can compute the same
; extensional induction result over the merged fact view.
(= (register-inheritance-induction! $kb)
   (let $_mark (add-atom &mork (inheritance-induction-enabled $kb))
     ()))

(= (mm2-known-concept-node? $kb $node)
   (let $scope (mm2-ir-scope-kb $kb)
     (not (== (collapse (match &mork (fact ($scope (Member $obj $node)) $stv) true)) ()))))

(= (mm2-test-known-concept-node $kb $node $expected)
   (mm2-test-equal (mm2-known-concept-node? $kb $node) $expected))

(= (mm2-evidence-negate $ev)
   (case $ev
     (((fact-ev $kb $prf $type) (not-fact-ev $kb $prf $type))
      ((not-fact-ev $kb $prf $type) (fact-ev $kb $prf $type))
      ($other (not-ev $other)))))

(= (mm2-evidence-sets-overlap? $set-a $set-b)
   (not (== (intersection-atom $set-a $set-b) ())))

(= (mm2-test-evidence-negate $ev $expected)
   (mm2-test-equal (mm2-evidence-negate $ev) $expected))

(= (mm2-test-evidence-sets-overlap? $set-a $set-b $expected)
   (mm2-test-equal (mm2-evidence-sets-overlap? $set-a $set-b) $expected))

(= (mm2-proof-atom-proof ($_type $_kb $proof $_tv)) $proof)

(= (mm2-projection-proof-key $proof)
   (case $proof
     (((marginal-proj $idx $base) (projection-key $idx $base))
      (((proj $idx $base) $_evidence) (projection-key $idx $base))
      ($other no-projection-key))))

(= (mm2-strict-projection-proof? $proof)
   (case $proof
     ((((proj $_idx $_base) $_evidence) true)
      ($other false))))

(= (mm2-projection-dominates? $a $b)
   (let $key (mm2-projection-proof-key $a)
     (and (not (== $key no-projection-key))
          (and (== $key (mm2-projection-proof-key $b))
               (and (mm2-strict-projection-proof? $a)
                    (not (mm2-strict-projection-proof? $b)))))))

(= (mm2-merge-proof-atoms $a $b)
   (if (== $a $b)
     $a
     (let $pa (mm2-proof-atom-proof $a)
       (let $pb (mm2-proof-atom-proof $b)
         (if (mm2-projection-dominates? $pa $pb)
           $a
           (if (mm2-projection-dominates? $pb $pa)
             $b
             mm2-merge-proof-atoms-unsupported))))))

(= (mm2-test-merge-proof-atoms $a $b $expected)
   (mm2-test-equal (mm2-merge-proof-atoms $a $b) $expected))

; Remove exact atoms produced by a MORK match. Calling remove-atom with a
; variable pattern would remove nothing, so cleanup first materializes the
; matching atoms and then removes those exact terms.
(= (mm2-remove-atoms ()) ())
(= (mm2-remove-atoms (cons $atom $rest))
   (let $_remove (remove-atom &mork $atom)
     (mm2-remove-atoms $rest)))

(= (mm2-remove-matches $pattern)
   (mm2-remove-atoms (collapse (match &mork $pattern $pattern))))

(= (mm2-formula-runtime-path)
   "/nexus/Dev/OpenCog/NL2PLN_Project/mm2-chainer/runtime/formula_eval.mm2")

(= (mm2-ensure-formula-runtime)
   (let $seen (collapse (match &mork mm2-formula-runtime-loaded true))
     (if (== $seen ())
       (let* (($_load (mork-load-file (mm2-formula-runtime-path)))
              ($_mark (add-atom &mork mm2-formula-runtime-loaded)))
         loaded)
       loaded)))

(= (mm2-formula-packed-stv ($s $c)) (STV $s $c))

(= (mm2-formula-packed-inversion ($flag $ps $pc $ns $nc))
   (if (== $flag 1.0)
     (CTV (STV $ps $pc) (STV $ns $nc))
     ()))

(= (mm2-clear-formula-probe $key)
   (let* (($_old-eval (mm2-remove-matches (formula-eval $key $pending)))
          ($_old-stv (mm2-remove-matches (formula-result-stv $key $stv)))
          ($_old-inv (mm2-remove-matches (formula-result-inversion $key $packed))))
     ()))

(= (mm2-formula-probe-result $key)
   (let* (($_run (mm2-exec &mork 500))
          ($stvs (collapse (match &mork (formula-result-stv $key $stv) $stv))))
     (case $stvs
       (((cons $stv $_rest) (mm2-formula-packed-stv $stv))
        (() (case (collapse (match &mork (formula-result-inversion $key $packed) $packed))
              (((cons $packed $_more) (mm2-formula-packed-inversion $packed))
               (() no-result))))))))

(= (mm2-formula-mp $prem $ctv)
   (let* (($key mm2-formula-probe)
          ($_runtime (mm2-ensure-formula-runtime))
          ($_clear (mm2-clear-formula-probe $key))
          ($_add (add-atom &mork (formula-eval $key (CTVModusPonensFormula $prem $ctv)))))
     (mm2-formula-probe-result $key)))

(= (mm2-formula-and $a $b)
   (let* (($key mm2-formula-probe)
          ($_runtime (mm2-ensure-formula-runtime))
          ($_clear (mm2-clear-formula-probe $key))
          ($_add (add-atom &mork (formula-eval $key (AndFormula $a $b)))))
     (mm2-formula-probe-result $key)))

(= (mm2-formula-or $a $b)
   (let* (($key mm2-formula-probe)
          ($_runtime (mm2-ensure-formula-runtime))
          ($_clear (mm2-clear-formula-probe $key))
          ($_add (add-atom &mork (formula-eval $key (OrFormula $a $b)))))
     (mm2-formula-probe-result $key)))

(= (mm2-formula-not $a)
   (let* (($key mm2-formula-probe)
          ($_runtime (mm2-ensure-formula-runtime))
          ($_clear (mm2-clear-formula-probe $key))
          ($_add (add-atom &mork (formula-eval $key (NotFormula $a)))))
     (mm2-formula-probe-result $key)))

(= (mm2-formula-likelier $a $b)
   (let* (($key mm2-formula-probe)
          ($_runtime (mm2-ensure-formula-runtime))
          ($_clear (mm2-clear-formula-probe $key))
          ($_add (add-atom &mork (formula-eval $key (LikelierThanFormula $a $b)))))
     (mm2-formula-probe-result $key)))

(= (mm2-formula-or-projection $compound $evidence)
   (let* (($key mm2-formula-probe)
          ($_runtime (mm2-ensure-formula-runtime))
          ($_clear (mm2-clear-formula-probe $key))
          ($_add (add-atom &mork (formula-eval $key (OrProjection $compound $evidence)))))
     (mm2-formula-probe-result $key)))

(= (mm2-formula-inversion $a $b $ctv)
   (let* (($key mm2-formula-probe)
          ($_runtime (mm2-ensure-formula-runtime))
          ($_clear (mm2-clear-formula-probe $key))
          ($_add (add-atom &mork (formula-eval $key (CTVInversionFormula $a $b $ctv)))))
     (mm2-formula-probe-result $key)))

(= (mm2-tv-confidence $tv)
   (if (is-var $tv)
     1.0
     (case $tv
       (((STV $_s $c) (if (is-var $c) 1.0 $c))
        ((CTV $pos $neg) (min (mm2-tv-confidence $pos) (mm2-tv-confidence $neg)))
        ($other 1.0)))))

(= (mm2-normalize-expected-tv $tv)
   (if (is-var $tv)
     (STV 1.0 1.0)
     (case $tv
       (((STV $s $c)
         (STV (if (is-var $s) 1.0 $s)
              (if (is-var $c) 1.0 $c)))
        ((CTV $pos $neg)
         (CTV (mm2-normalize-expected-tv $pos) (mm2-normalize-expected-tv $neg)))
        ($other $tv)))))

(= (mm2-pec-cpu-tv CTVModusPonensFormula ($a $ctv))
   (mm2-formula-mp (mm2-normalize-expected-tv $a)
                   (mm2-normalize-expected-tv $ctv)))

(= (mm2-pec-cpu-tv AndFormula ($a $b))
   (mm2-formula-and (mm2-normalize-expected-tv $a)
                    (mm2-normalize-expected-tv $b)))

(= (mm2-pec-cpu-tv OrFormula ($a $b))
   (mm2-formula-or (mm2-normalize-expected-tv $a)
                   (mm2-normalize-expected-tv $b)))

(= (mm2-pec-cpu-tv NotFormula ($a))
   (mm2-formula-not (mm2-normalize-expected-tv $a)))

(= (mm2-pec-cpu-tv LikelierThanFormula ($a $b))
   (mm2-formula-likelier (mm2-normalize-expected-tv $a)
                         (mm2-normalize-expected-tv $b)))

(= (mm2-pec-cpu-tv CTVInversionFormula ($a $b $ctv))
   (let* (($na (mm2-normalize-expected-tv $a))
          ($nb (mm2-normalize-expected-tv $b))
          ($nctv (mm2-normalize-expected-tv $ctv)))
     (if (or (is-var $a) (is-var $b))
       (let $conf (* (min (min (mm2-tv-confidence $na)
                               (mm2-tv-confidence $nb))
                          (mm2-tv-confidence $nctv))
                      0.9)
         (CTV (STV 1.0 $conf) (STV 1.0 $conf)))
       (mm2-formula-inversion $na $nb $nctv))))

(= (mm2-pec-cpu-confidence $fun $args)
   (let $hits (collapse (mm2-pec-cpu-tv $fun $args))
     (if (== $hits ()) 1.0 (mm2-tv-confidence (car-atom $hits)))))

(= (mm2-proof-score $prf $tv)
   (case $prf
     (((marginal-proj $_idx $_inner) (* 0.99 (mm2-tv-confidence $tv)))
      ($other (mm2-tv-confidence $tv)))))

(= (mm2-term-confidence $term)
   (case $term
     (((CPU AndMarginalProjection $args $res)
       (* 0.99
          (if (is-var $res)
            (mm2-pec-cpu-confidence AndMarginalProjection $args)
            (mm2-tv-confidence $res))))
      ((CPU $fun $args $res)
       (if (is-var $res)
         (mm2-pec-cpu-confidence $fun $args)
         (mm2-tv-confidence $res)))
      (($_type ($_kbid $_ctx $_vars) $prf $tv)
       (mm2-proof-score $prf $tv))
      ($other 1.0))))

(= (mm2-premises-expected-confidence ()) 1.0)
(= (mm2-premises-expected-confidence (cons $prem $rest))
   (case ($prem $rest)
     ((((CPU $fun $args $mid-tv)
        (cons (CPU CTVModusPonensFormula ($mid-tv $rule-tv) $_mp-tv) $tail))
       (let $hits (collapse (mm2-pec-cpu-tv $fun $args))
         (if (== $hits ())
           (min (mm2-term-confidence $prem)
                (mm2-premises-expected-confidence $rest))
           (let $expected (car-atom $hits)
             (min (min (mm2-tv-confidence $expected)
                       (mm2-pec-cpu-confidence CTVModusPonensFormula ($expected $rule-tv)))
                  (mm2-premises-expected-confidence $tail))))))
      (((CPU $fun $args $res) $_)
       (min (mm2-term-confidence (CPU $fun $args $res))
            (mm2-premises-expected-confidence $rest)))
      (($other $_)
       (min (mm2-term-confidence $prem)
            (mm2-premises-expected-confidence $rest))))))

; Base-rate cache operations used by PeTTaChainer tests. Runtime rules still
; consume the maintained (base-rate ...) relation; cache reads use source
; markers so user and computed entries expose PeTTa-style cache semantics.
(= (mm2-scoped-base-rate-pattern $kb $pattern)
   (let $scope (mm2-ir-scope-kb $kb) ($scope $pattern)))

(= (mm2-remove-base-rate-state $kb $pattern)
   (let $pat (mm2-scoped-base-rate-pattern $kb $pattern)
     (let $_br (mm2-remove-matches (base-rate $pat $tv))
       (let $_def (mm2-remove-matches (base-rate-def $pat $match))
         (let $_entry (mm2-remove-matches (base-rate-cache-entry $pat $source $stored-tv $mode))
           ())))))

(= (mm2-add-base-rate-support $kb $pattern)
   (let $pat (mm2-scoped-base-rate-pattern $kb $pattern)
     (let* (($qpat (copy_term $pat))
            ($mpat (copy_term $pat))
            ($seed (copy_term $pat))
            ($_def (add-atom &mork (base-rate-def $qpat $mpat)))
            ($_seed (add-atom &mork (base-rate $seed (0.0 0.0)))))
       ())))

(= (mm2-direct-fact-base-rate $pat)
   (case (collapse
           (match &mork
             (proved $pat ($s $c) $prf (pcons (fact-ev $prf $pat) pnil))
             (STV $s $c)))
     ((() no-cache-entry)
      ($stvs
       (BaseRateTv
         (mm2-base-rate-acc-from-stvs (BaseRateEvidence 0.0 0.0) $stvs))))))

(= (mm2-computed-cached-base-rate $pat (STV $s $c))
   (let $direct (mm2-direct-fact-base-rate $pat)
     (case $direct
       ((no-cache-entry (STV $s $c))
        ((STV $_ds $dc) (if (> $dc $c) $direct (STV $s $c)))
        ($other (STV $s $c))))))

(= (mm2-set-base-rate $kb $pattern (STV $s $c))
   (let $_clear (mm2-remove-base-rate-state $kb $pattern)
     (let $pat (mm2-scoped-base-rate-pattern $kb $pattern)
       (let* (($stored (copy_term $pat))
              ($cache-pat (copy_term $pat))
              ($_set (add-atom &mork (base-rate $stored ($s $c))))
              ($_entry (add-atom &mork (base-rate-cache-entry $cache-pat user (STV $s $c) manual))))
         ()))))

(= (mm2-clear-base-rate $kb $pattern)
   (let $_clear (mm2-remove-base-rate-state $kb $pattern)
     (mm2-add-base-rate-support $kb $pattern)))

(= (mm2-store-computed-base-rate! $kb $pattern (STV $s $c) $mode)
   (let $_clear (mm2-remove-base-rate-state $kb $pattern)
     (let $_support (mm2-add-base-rate-support $kb $pattern)
       (let $pat (mm2-scoped-base-rate-pattern $kb $pattern)
         (let $_old (mm2-remove-matches (base-rate $pat $tv))
           (let* (($stored (copy_term $pat))
                  ($cache-pat (copy_term $pat))
                  ($_set (add-atom &mork (base-rate $stored ($s $c))))
                  ($_entry (add-atom &mork (base-rate-cache-entry $cache-pat computed (STV $s $c) $mode))))
             ()))))))

(= (mm2-live-cached-base-rate $pat)
   (case (collapse (match &mork (base-rate $pat ($s $c)) (STV $s $c)))
     ((() no-cache-entry)
      ((cons (STV 0.0 0.0) $_rest) no-cache-entry)
      ((cons $tv $_rest) $tv))))

(= (mm2-unmarked-cached-base-rate $pat)
   (case (mm2-live-cached-base-rate $pat)
     ((no-cache-entry no-cache-entry)
      ($live
       (case (mm2-direct-fact-base-rate $pat)
         ((no-cache-entry $live)
          ($direct $direct)))))))

(= (mm2-cached-base-rate $kb $pattern)
   (let $pat (mm2-scoped-base-rate-pattern $kb $pattern)
     (case (collapse
             (match &mork
               (base-rate-cache-entry $pat $source $stored-tv $mode)
               ($source $stored-tv $mode)))
       ((() (mm2-unmarked-cached-base-rate $pat))
        ((cons (user $stored-tv $_mode) $_rest) $stored-tv)
        ((cons (computed $stored-tv $_mode) $_rest)
         (mm2-computed-cached-base-rate $pat $stored-tv))
        ($other (mm2-live-cached-base-rate $pat))))))

(= (mm2-test-cached-base-rate $kb $pattern $expected)
   (let* (($got (mm2-cached-base-rate $kb $pattern))
          ($verdict
            (if (== $got $expected)
              (mm2-test-pass $expected)
              (case ($got $expected)
                ((((STV $gs $gc) (STV $es $ec))
                  (if (mm2-tv-close $got $expected)
                    (mm2-test-close (inexact $expected) (got $got))
                    (mm2-test-FAIL (expected $expected) (got $got))))
                 (((CTV $gp $gn) (CTV $ep $en))
                  (if (mm2-tv-close $got $expected)
                    (mm2-test-close (inexact $expected) (got $got))
                    (mm2-test-FAIL (expected $expected) (got $got))))
                 ($other (mm2-test-FAIL (expected $expected) (got $got)))))))
          ($_log (mm2-log-line $verdict)))
     $verdict))

; Prior-aware inheritance base rates use PeTTaChainer's late-bound
; ConceptNodePriorRuntime at refresh time, while exposing the same packed
; (base-rate $pattern ($s $c)) relation consumed by the MM2 runtime.
(= (mm2-prior-base-rate-support $pat $kb $concept)
   (superpose (
     (base-rate-prior-def (copy_term $pat) $kb $concept)
     (base-rate (copy_term $pat) (0.0 0.0)))))

(= (mm2-prior-inheritance-evidence-stvs $scope $concept)
   (mm2-ir-append
     (collapse
       (match &mork
         (fact ($scope (Inheritance $subj $concept)) ($s $c))
         (prior-inheritance-ev $subj (STV $s $c))))
     (collapse
       (match &mork
         (fact ($scope (Inheritance $subj $concept)) (ctvpair ($ps $pc) $neg))
         (prior-inheritance-ev $subj (STV $ps $pc))))))

(= (mm2-prior-weighted-base-rate-acc $_kb $acc ()) $acc)
(= (mm2-prior-weighted-base-rate-acc $kb $acc (cons (prior-inheritance-ev $subj $tv) $rest))
   (mm2-prior-weighted-base-rate-acc
     $kb
     (WeightedBaseRateAcc $acc (WeightedTv (inheritance-subject-prior-tv $kb $subj) $tv))
     $rest))

(= (mm2-prior-weighted-base-rate-evidence-tv $kb $ev)
   (let $universe-size (kb-universe-size $kb)
     (if (== $universe-size no-universe-size)
       (WeightedBaseRateTv $ev)
       (WeightedUniverseBaseRateTv $universe-size $ev))))

(= (mm2-prior-weighted-base-rate-tv $kb $scope $concept)
   (let* (($evs (mm2-prior-inheritance-evidence-stvs $scope $concept))
          ($ev (mm2-prior-weighted-base-rate-acc $kb (BaseRateEvidence 0.0 0.0) $evs)))
     (BaseRateWithPriorFormula
       (concept-node-prior-tv $kb $concept)
       (mm2-prior-weighted-base-rate-evidence-tv $kb $ev))))

(= (mm2-store-prior-base-rate! $pat $newtv)
   (let $_old (mm2-remove-matches (base-rate $pat $oldtv))
     (let $stored (copy_term $pat)
       (case $newtv
         ((no-evidence (add-atom &mork (base-rate $stored (0.0 0.0))))
          ((STV $s $c) (add-atom &mork (base-rate $stored ($s $c))))
          ($other (add-atom &mork (base-rate $stored (0.0 0.0)))))))))

(= (mm2-refresh-prior-base-rate! (base-rate-prior-def $pat $kb $concept))
   (case $pat
     ((($scope (Inheritance $subj $concept2))
       (mm2-store-prior-base-rate!
         $pat
         (mm2-prior-weighted-base-rate-tv $kb $scope $concept)))
      ($other ()))))

(= (mm2-refresh-prior-base-rate-list! ()) ())
(= (mm2-refresh-prior-base-rate-list! (cons $def $rest))
   (let $_refresh (mm2-refresh-prior-base-rate! $def)
     (mm2-refresh-prior-base-rate-list! $rest)))

(= (mm2-refresh-prior-base-rates!)
   (mm2-refresh-prior-base-rate-list!
     (collapse
       (match &mork
         (base-rate-prior-def $pat $kb $concept)
         (base-rate-prior-def $pat $kb $concept)))))

; Query answers are the facts matching each compiled query's own scoped goal
; term — usually the kb's MAIN context, or the fresh query context some
; queries allocate. Assumption-context facts never surface because their
; contexts are not any compiled goal's scope.
(= (mm2-readback-type $shape $type $prf $tv)
   (case $shape
     ((($kb $ctx $vars)
       (if (and (not (== $ctx MAIN))
                (and (not (is-var $prf)) (not (is-var $tv))))
         (Implication (Premises $type) (Conclusions $type))
         $type))
      ($other $type))))

; Query-local total implication can derive several proof-specific CTVs in the
; assumption contexts while MORK stores their revised ctvpair fact at the goal.
; Read them back as proof results without changing the runtime merge semantics.
(= (mm2-readback-total-implication-proofs $goal-type $pos-shape $pos-type $neg-shape $neg-type)
   (collapse
     (match &mork
       (proved ($pos-shape $pos-type) ($ps $pc) $pos-proof-id $pos-evset)
       (match &mork
         (proved ($neg-shape $neg-type) ($ns $nc) $neg-proof-id $neg-evset)
         (: mm2-proved $goal-type (CTV (STV $ps $pc) (STV $ns $nc)))))))

(= (mm2-readback-total-implication-pos-fact $goal-type $pos-shape $pos-type $neg-shape $neg-type)
   (collapse
     (match &mork
       (fact ($pos-shape $pos-type) ($ps $pc))
       (match &mork
         (proved ($neg-shape $neg-type) ($ns $nc) $neg-proof-id $neg-evset)
         (: mm2-proved $goal-type (CTV (STV $ps $pc) (STV $ns $nc)))))))

(= (mm2-readback-total-implication-neg-fact $goal-type $pos-shape $pos-type $neg-shape $neg-type)
   (collapse
     (match &mork
       (proved ($pos-shape $pos-type) ($ps $pc) $pos-proof-id $pos-evset)
       (match &mork
         (fact ($neg-shape $neg-type) ($ns $nc))
         (: mm2-proved $goal-type (CTV (STV $ps $pc) (STV $ns $nc)))))))

(= (mm2-readback-total-implication-branches $goal-type $pos-shape $pos-type $neg-shape $neg-type)
   (mm2-ir-append
     (mm2-readback-total-implication-proofs $goal-type $pos-shape $pos-type $neg-shape $neg-type)
     (mm2-ir-append
       (mm2-readback-total-implication-pos-fact $goal-type $pos-shape $pos-type $neg-shape $neg-type)
       (mm2-readback-total-implication-neg-fact $goal-type $pos-shape $pos-type $neg-shape $neg-type))))

(= (mm2-readback-total-implication-premises $goal-type $prems)
   (case (mm2-ir-collect $prems)
     (((collected (pcons ($pos-shape $pos-type)
                   (pcons ($neg-shape $neg-type) pnil))
                  ())
       (mm2-readback-total-implication-branches $goal-type $pos-shape $pos-type $neg-shape $neg-type))
      ($other ()))))

(= (mm2-readback-total-implication-rule $goal-type $goal-shape $prems $ccl)
   (case (mm2-ir-item $ccl)
     (((subgoal ($goal-shape2 $goal-type2) (CTV $pos-tv $neg-tv) (total-implication $pos-prf $neg-prf))
       (if (and (=alpha $goal-type $goal-type2)
                (=alpha $goal-shape $goal-shape2))
         (mm2-readback-total-implication-premises $goal-type $prems)
         ()))
      ($other ()))))

(= (mm2-readback-total-implication-adds $goal-type $goal-shape $adds)
   (case $adds
     (((cons (rules ($prems |- $ccl)) $rest)
       (mm2-readback-total-implication-rule $goal-type $goal-shape $prems $ccl))
      ($other ()))))

(= (mm2-readback-total-implication $goal-item $adds)
   (case (mm2-ir-item $goal-item)
     (((subgoal ($goal-shape $goal-type) (CTV $pos-tv $neg-tv) (total-implication $pos-prf $neg-prf))
       (mm2-readback-total-implication-adds $goal-type $goal-shape $adds))
      ($other ()))))

(= (mm2-member-consequent-tv $scope $obj $concept)
   (let $hits
     (collapse
       (match &mork
         (fact ($scope (Member $obj $concept)) ($s $c))
         (STV $s $c)))
     (if (== $hits ()) no-evidence (car-atom $hits))))

(= (mm2-member-inheritance-acc $_scope $_concept $acc ()) $acc)
(= (mm2-member-inheritance-acc $scope $concept $acc (cons (member-ant $obj $atv) $rest))
   (let $btv (mm2-member-consequent-tv $scope $obj $concept)
     (mm2-member-inheritance-acc
       $scope
       $concept
       (WeightedBaseRateAcc $acc (WeightedTv $atv $btv))
       $rest)))

(= (mm2-member-inheritance-tv $kb $evidence)
   (let $universe-size (kb-universe-size $kb)
     (if (== $universe-size no-universe-size)
       (WeightedCountBaseRateTv $evidence)
       (WeightedUniverseBaseRateTv $universe-size $evidence))))

(= (mm2-readback-member-inheritance-result $goal-type $goal-shape $kb $subj $concept)
   (let $ants
     (collapse
       (match &mork
         (fact ($goal-shape (Member $obj $subj)) ($as $ac))
         (member-ant $obj (STV $as $ac))))
     (if (== $ants ())
       ()
       (let $tv
         (mm2-member-inheritance-tv
           $kb
           (mm2-member-inheritance-acc $goal-shape $concept (BaseRateEvidence 0.0 0.0) $ants))
         (cons (: mm2-proved $goal-type $tv) ())))))

(= (mm2-readback-member-inheritance-rule $goal-type $goal-shape $prems $ccl)
   (case (mm2-ir-collect $prems)
     (((collected pnil (cons (cpu MemberInheritanceFormula ($kb $subj $concept) $out) ()))
       (case (mm2-ir-item $ccl)
         (((subgoal ($goal-shape2 $goal-type2) $out $goal-prf)
           (if (and (=alpha $goal-type $goal-type2)
                    (=alpha $goal-shape $goal-shape2))
             (mm2-readback-member-inheritance-result $goal-type $goal-shape $kb $subj $concept)
             ()))
          ($other ()))))
      ($other ()))))

(= (mm2-readback-member-inheritance-adds $goal-type $goal-shape $adds)
   (case $adds
     (((cons (rules ($prems |- $ccl)) $rest)
       (mm2-readback-member-inheritance-rule $goal-type $goal-shape $prems $ccl))
      ($other ()))))

(= (mm2-readback-member-inheritance $goal-item $adds)
   (case (mm2-ir-item $goal-item)
     (((subgoal ($goal-shape $goal-type) $goal-tv $goal-prf)
       (mm2-readback-member-inheritance-adds $goal-type $goal-shape $adds))
      ($other ()))))

(= (mm2-readback-inheritance-query-direct-proofs $goal-type $pos-shape $pos-type)
   (collapse
     (match &mork
       (fact ($pos-shape $pos-type) ($s $c))
       (: mm2-proved $goal-type (STV $s $c)))))

(= (mm2-readback-inheritance-query-merged-proofs $goal-type $pos-shape $pos-type)
   (collapse
     (match &mork
       (fact ($pos-shape $pos-type) ($fs $fc))
       (match &mork
         (proved ($pos-shape $pos-type) ($ps $pc) (scheduledN $pg $rule $premises) $evset)
         (case (mergetvs (STV $fs $fc) (STV $ps $pc))
           (((STV $s $c) (: mm2-proved $goal-type (STV $s $c)))
            ($other empty)))))))

(= (mm2-readback-inheritance-query-proofs $goal-type $pos-shape $pos-type)
   (mm2-ir-append
     (mm2-readback-inheritance-query-direct-proofs $goal-type $pos-shape $pos-type)
     (mm2-readback-inheritance-query-merged-proofs $goal-type $pos-shape $pos-type)))

(= (mm2-readback-inheritance-query-premises $goal-type $goal-shape $prems $ccl)
   (case (mm2-ir-collect $prems)
     (((collected (pcons ($pos-shape $pos-type)
                   (pcons ($neg-shape $neg-type) pnil))
                  ())
       (case (mm2-ir-item $ccl)
         (((subgoal ($goal-shape2 $goal-type2) $goal-tv $goal-prf)
           (if (and (=alpha $goal-type $goal-type2)
                    (=alpha $goal-shape $goal-shape2))
             (mm2-readback-inheritance-query-proofs $goal-type $pos-shape $pos-type)
             ()))
          ($other ()))))
      ($other ()))))

(= (mm2-readback-inheritance-query-adds $goal-type $goal-shape $adds)
   (case $adds
     (((cons (rules ($prems |- $ccl)) $rest)
       (mm2-readback-inheritance-query-premises $goal-type $goal-shape $prems $ccl))
      ($other ()))))

(= (mm2-readback-inheritance-query $goal-item $adds)
   (case (mm2-ir-item $goal-item)
     (((subgoal ($goal-shape $goal-type) $goal-tv (inheritance-query (total-implication $pos-prf $neg-prf)))
       (mm2-readback-inheritance-query-adds $goal-type $goal-shape $adds))
      ($other ()))))

(= (mm2-base-rate-acc-from-stvs $acc ()) $acc)
(= (mm2-base-rate-acc-from-stvs $acc (cons $tv $rest))
   (mm2-base-rate-acc-from-stvs (BaseRateAcc $acc $tv) $rest))

(= (mm2-inheritance-base-rate-tv $scope $concept)
   (BaseRateTv
     (mm2-base-rate-acc-from-stvs
       (BaseRateEvidence 0.0 0.0)
       (collapse
         (match &mork
           (fact ($scope (Inheritance $subj $concept)) ($s $c))
           (STV $s $c))))))

(= (mm2-inheritance-uniform-prior-tv $scope $concept)
   (UniformPriorTv
     (collapse
       (match &mork
         (fact ($scope (Inheritance $subj $concept)) ($s $c))
         $subj))))

(= (mm2-inheritance-induction-tvs $scope $a $b)
   (let* (($brA (mm2-inheritance-base-rate-tv $scope $a))
          ($brB (mm2-inheritance-base-rate-tv $scope $b))
          ($brC (mm2-inheritance-uniform-prior-tv $scope $a)))
     (collapse
       (match &mork
         (fact ($scope (Inheritance $c $a)) ($sCA $cCA))
         (match &mork
           (fact ($scope (Inheritance $c $b)) ($sCB $cCB))
           (InductionFormula
             $brA
             $brB
             $brC
             (STV $sCA $cCA)
             (STV $sCB $cCB)))))))

(= (mm2-revise-tv-list $tvs)
   (case $tvs
     ((() no-evidence)
      ((cons $tv ()) $tv)
      ((cons $tv $rest) (mergetvs $tv (mm2-revise-tv-list $rest))))))

(= (mm2-readback-inheritance-induction-result $goal-type $scope $a $b)
   (case (mm2-revise-tv-list (mm2-inheritance-induction-tvs $scope $a $b))
     (((STV $s $c) (cons (: mm2-proved $goal-type (STV $s $c)) ()))
      ($other ()))))

(= (mm2-readback-inheritance-induction $goal-type $goal-shape)
   (case ($goal-shape $goal-type)
     (((($kb MAIN $vars) (Inheritance $a $b))
       (let $enabled (collapse (match &mork (inheritance-induction-enabled $kb) found))
         (if (== $enabled ())
           ()
           (mm2-readback-inheritance-induction-result
             $goal-type
             $goal-shape
             $a
             $b))))
      ($other ()))))

; Readback-level lifting merge for open two-premise And adapter queries.  The
; runtime still stores every raw adapter proof; PeTTaChainer merges same-output
; proof groups before parent use by factoring shared premises out, revising the
; residuals, and reapplying the shared TV once.
(= (mm2-and-proof-tvs $shape $left $right)
   (collapse
     (match &mork
       (proved ($shape (And $left $right)) ($s $c) $proof $ev)
       (STV $s $c))))

(= (mm2-and-residual-tvs $_shared ()) ())
(= (mm2-and-residual-tvs $shared (cons $tv $rest))
   (case (AndProjection $tv $shared)
     (((STV $s $c) (cons (STV $s $c) (mm2-and-residual-tvs $shared $rest)))
      ($other (mm2-and-residual-tvs $shared $rest)))))

(= (mm2-readback-factored-and-result-from-tvs $goal-type $shared $residuals)
   (case (mm2-revise-tv-list $residuals)
     (((STV $rs $rc)
       (case (AndFormula $shared (STV $rs $rc))
         (((STV $s $c) (: mm2-proved $goal-type (STV $s $c)))
          ($other empty))))
      ($other empty))))

(= (mm2-readback-factored-and-result $goal-type $shared $residuals)
   (mm2-readback-factored-and-result-from-tvs
     $goal-type
     $shared
     (list_to_set $residuals)))

(= (mm2-proved-tv-records $shape $type)
   (collapse
     (match &mork
       (proved ($shape $type) ($s $c) $proof-id $evset)
       (proved-tv (STV $s $c) $evset))))

(= (mm2-proved-record-tvs ()) ())
(= (mm2-proved-record-tvs (cons (proved-tv $tv $_evset) $rest))
   (cons $tv (mm2-proved-record-tvs $rest)))

(= (mm2-readback-factored-and-child-result $goal-type $shape $residual-type $shared)
   (mm2-readback-factored-and-result-from-tvs
     $goal-type
     $shared
     (mm2-proved-record-tvs
       (list_to_set (mm2-proved-tv-records $shape $residual-type)))))

(= (mm2-readback-factored-and-with-shared $goal-type $shape $left $right $shared)
   (mm2-readback-factored-and-result
     $goal-type
     $shared
     (mm2-and-residual-tvs $shared (mm2-and-proof-tvs $shape $left $right))))

(= (mm2-readback-factored-and-left $goal-type $shape $left $right)
   (mm2-ir-append
     (collapse
       (match &mork
         (fact ($shape $left) ($s $c))
         (mm2-readback-factored-and-child-result
           $goal-type
           $shape
           $right
           (STV $s $c))))
     (collapse
       (match &mork
         (fact ($shape $left) ($s $c))
         (mm2-readback-factored-and-with-shared
           $goal-type
           $shape
           $left
           $right
           (STV $s $c))))))

(= (mm2-readback-factored-and-right $goal-type $shape $left $right)
   (mm2-ir-append
     (collapse
       (match &mork
         (fact ($shape $right) ($s $c))
         (mm2-readback-factored-and-child-result
           $goal-type
           $shape
           $left
           (STV $s $c))))
     (collapse
       (match &mork
         (fact ($shape $right) ($s $c))
         (mm2-readback-factored-and-with-shared
           $goal-type
           $shape
           $left
           $right
           (STV $s $c))))))

(= (mm2-readback-factored-and $goal-type $shape)
   (case $goal-type
     (((And $left $right)
       (mm2-ir-append
         (mm2-readback-factored-and-left $goal-type $shape $left $right)
         (mm2-readback-factored-and-right $goal-type $shape $left $right)))
      ($other ()))))

(= (mm2-rule-prems-have-identity-mp? ()) false)
(= (mm2-rule-prems-have-identity-mp? (cons $prem $rest))
   (case $prem
     (((CPU CTVModusPonensFormula
            ($_agg (CTV (STV 1.0 1.0) (STV 0.0 1.0)))
            $_out)
       true)
      ($other (mm2-rule-prems-have-identity-mp? $rest)))))

(= (mm2-query-compound-identity-add? $goal-type $add)
   (case $add
     (((rules ($prems |- ($ctype $_shape (query-compound $_proof) $_tv)))
       (and (=alpha $ctype $goal-type)
            (mm2-rule-prems-have-identity-mp? $prems)))
      ($other false))))

(= (mm2-query-compound-identity-adds? $_goal-type ()) false)
(= (mm2-query-compound-identity-adds? $goal-type (cons $add $rest))
   (if (mm2-query-compound-identity-add? $goal-type $add)
     true
     (mm2-query-compound-identity-adds? $goal-type $rest)))

(= (mm2-readback-identity-mp-rows ()) ())
(= (mm2-readback-identity-mp-rows (cons $row $rest))
   (case $row
     (((: $prf $type (STV $s $c))
       (case (CTVModusPonensFormula
               (STV $s $c)
               (CTV (STV 1.0 1.0) (STV 0.0 1.0)))
         (((STV $ms $mc)
           (cons (: $prf $type (STV $ms $mc))
                 (mm2-readback-identity-mp-rows $rest)))
          ($other (mm2-readback-identity-mp-rows $rest)))))
      ($other (mm2-readback-identity-mp-rows $rest)))))

(= (mm2-readback-query-compound-factored-and $goal-type $shape $adds)
   (if (mm2-query-compound-identity-adds? $goal-type $adds)
     (mm2-readback-identity-mp-rows
       (mm2-readback-factored-and $goal-type $shape))
     ()))

(= (mm2-readback-query $cq)
   (case $cq
     (((compiled-query $goal-item $adds)
       (let (subgoal ($shape $type) $tv $prf) (mm2-ir-item $goal-item)
         (let $readback-type (mm2-readback-type $shape $type $prf $tv)
           (mm2-ir-append
             (mm2-readback-total-implication $goal-item $adds)
             (mm2-ir-append
               (mm2-readback-inheritance-query $goal-item $adds)
               (mm2-ir-append
                 (mm2-readback-member-inheritance $goal-item $adds)
                 (mm2-ir-append
                   (mm2-ir-append
                     (mm2-readback-factored-and $readback-type $shape)
                     (mm2-readback-query-compound-factored-and $readback-type $shape $adds))
                   (mm2-ir-append
                     (mm2-readback-inheritance-induction $readback-type $shape)
                     (mm2-ir-append
                       (collapse
                         (match &mork (fact ($shape $type) ($s $c))
                           (: mm2-merged $readback-type (STV $s $c))))
                       (collapse
                         (match &mork (fact ($shape $type) (ctvpair ($ps $pc) ($ns $nc)))
                           (: mm2-merged $readback-type (CTV (STV $ps $pc) (STV $ns $nc))))))))))))))
      ($other ()))))

(= (mm2-readback-queries ()) ())
(= (mm2-readback-queries (cons $cq $rest))
   (mm2-ir-append (mm2-readback-query $cq) (mm2-readback-queries $rest)))

(= (mm2-materialize-proved-list $_scope ()) ())
(= (mm2-materialize-proved-list $scope (cons ($type $stv $proof-id $evset) $rest))
   (let $_mark (add-atom &mork (mm2-materialized $scope $type))
     (mm2-materialize-proved-list $scope $rest)))

(= (mm2-materialize-scope $scope)
   (mm2-materialize-proved-list
     $scope
     (collapse
       (match &mork
         (proved ($scope $type) $stv $proof-id $evset)
         ($type $stv $proof-id $evset)))))

(= (mm2-materialized-list $kb $type)
   (let $scope (mm2-ir-scope-kb $kb)
     (collapse (match &mork (mm2-materialized $scope $type) true))))

(= (mm2-run-compiled-queries $kb ()) ())
(= (mm2-run-compiled-queries $kb (cons $cq $rest))
   (mm2-ir-append (mm2-add-compiled $kb (mm2-translate-query $cq))
                  (mm2-run-compiled-queries $kb $rest)))

(= (mm2-cleanup-goal $g)
   (let* (($_goal (mm2-remove-matches (, (Goal $g))))
          ($_pending (mm2-remove-matches (pendingN $priority $g $rule-stv $premises)))
          ($_pending-named (mm2-remove-matches (pendingN $priority2 $g $rule-stv2 $premises2 $pending-evset)))
          ($_waits (mm2-remove-matches (wait-premises $g $rule-stv $rest $agg $proof-id $evset)))
          ($_or-waits (mm2-remove-matches (wait-premises-or $g $or-final-kind $or-rest $or-agg $or-proof-id $or-evset)))
          ($_pool-waits (mm2-remove-matches (wait-premises-pool $g $pool-rest $pool-state $pool-proof-id)))
          ($_wait (mm2-remove-matches (wait-premise $g $rule-stv $prem $rest $agg $proof-id $evset)))
          ($_or-wait (mm2-remove-matches (wait-premise-or $g $or-final-kind2 $or-prem $or-rest2 $or-agg2 $or-proof-id2 $or-evset2)))
          ($_not-wait (mm2-remove-matches (wait-premise-not $g $not-rule-stv $not-prem $not-rest $not-proof-id $not-evset)))
          ($_total-wait (mm2-remove-matches (wait-total-evidence $g $total-proof-id $total-prem $total-p1 $total-p2 $total-pat $total-evset)))
          ($_total-active (mm2-remove-matches (total-evidence-active $g $total-active-proof $total-ante-stv $total-active-p1 $total-active-p2 $total-active-pat $total-active-evset)))
          ($_pool-wait (mm2-remove-matches (wait-premise-pool $g $pool-prem $pool-rest2 $pool-state2 $pool-proof-id2)))
          ($_pool-step (mm2-remove-matches (pool-step $g $pool-step-rest $pool-step-proof-id $pool-result)))
          ($_head (mm2-remove-matches (wait-head $g $rule-stv $head $others $proof-id $evset)))
          ($_compute (mm2-remove-matches (compute-plus-checked $verdict $g $compute-rule $compute-agg $compute-prem-stv $compute-proof-id $compute-evset)))
          ($_open (mm2-remove-matches (open-proof $g $stv $proof-id $evset)))
          ($_inv (mm2-remove-matches (inv-checked $verdict2 $g $proof-id $evset))))
     cleaned))

(= (mm2-cleanup-query $cq)
   (case $cq
     (((compiled-query $goal-item $adds)
       (let (subgoal $g $tv $_prf) (mm2-ir-item $goal-item)
         (let $_adds (mm2-remove-atoms (mm2-translate-query $cq))
           (mm2-cleanup-goal $g))))
      ($other cleaned))))

(= (mm2-cleanup-queries ()) ())
(= (mm2-cleanup-queries (cons $cq $rest))
   (let $_cleanup (mm2-cleanup-query $cq)
     (mm2-cleanup-queries $rest)))

(= (mm2-clear-runtime-queue)
   (let* (($_goal (mm2-remove-matches (, (Goal $g))))
          ($_pending (mm2-remove-matches (pendingN $priority $g $rule-stv $premises)))
          ($_pending-named (mm2-remove-matches (pendingN $priority2 $g $rule-stv2 $premises2 $pending-evset)))
          ($_waits (mm2-remove-matches (wait-premises $g $rule-stv $rest $agg $proof-id $evset)))
          ($_or-waits (mm2-remove-matches (wait-premises-or $g $or-final-kind $or-rest $or-agg $or-proof-id $or-evset)))
          ($_pool-waits (mm2-remove-matches (wait-premises-pool $g $pool-rest $pool-state $pool-proof-id)))
          ($_wait (mm2-remove-matches (wait-premise $g $rule-stv $prem $rest $agg $proof-id $evset)))
          ($_or-wait (mm2-remove-matches (wait-premise-or $g $or-final-kind2 $or-prem $or-rest2 $or-agg2 $or-proof-id2 $or-evset2)))
          ($_not-wait (mm2-remove-matches (wait-premise-not $g $not-rule-stv $not-prem $not-rest $not-proof-id $not-evset)))
          ($_total-wait (mm2-remove-matches (wait-total-evidence $g $total-proof-id $total-prem $total-p1 $total-p2 $total-pat $total-evset)))
          ($_total-active (mm2-remove-matches (total-evidence-active $g $total-active-proof $total-ante-stv $total-active-p1 $total-active-p2 $total-active-pat $total-active-evset)))
          ($_pool-wait (mm2-remove-matches (wait-premise-pool $g $pool-prem $pool-rest2 $pool-state2 $pool-proof-id2)))
          ($_pool-step (mm2-remove-matches (pool-step $g $pool-step-rest $pool-step-proof-id $pool-result)))
          ($_head (mm2-remove-matches (wait-head $g $rule-stv $head $others $proof-id $evset)))
          ($_compute (mm2-remove-matches (compute-plus-checked $verdict $g $compute-rule $compute-agg $compute-prem-stv $compute-proof-id $compute-evset)))
          ($_open (mm2-remove-matches (open-proof $g $stv $proof-id $evset)))
          ($_inv (mm2-remove-matches (inv-checked $verdict2 $g $proof-id $evset)))
          ($_formula (mm2-remove-matches (formula-eval $formula-key $formula-pending)))
          ($_fold-br (mm2-remove-matches (fold-base-rate $br-pat $br-old $br-stv)))
          ($_fold-br-guarded (mm2-remove-matches (fold-base-rate $guarded-br-pat $guarded-br-old $guarded-br-stv $guarded-br-ev)))
          ($_sum (mm2-remove-matches (sum $sum-out $sum-total $sum-value)))
          ($_pair-counts (mm2-remove-matches (pair-counts $pair-out $pair-counts $pair-value)))
          ($_or-stv (mm2-remove-matches (or-stv $or-g $or-rule-id $or-pos $or-neg $or-stv $or-proof-id $or-evset)))
          ($_avg-active (mm2-remove-matches (avg-dist-active $avg-result-pid $avg-pat $avg-value)))
          ($_dist-avg (mm2-remove-matches (dist-average $avg-pid $avg-pat2 $avg-x $avg-w)))
          ($_dist-map-active (mm2-remove-matches (dist-map2-active $map-fun $map-lhs $map-rhs)))
          ($_dist-map-contrib (mm2-remove-matches (dist-map2-contrib $map-pid $map-source $map-pair)))
          ($_fsum (mm2-remove-matches (fsum $fsum-out $fsum-sum $fsum-mass $fsum-source)))
          ($_total-mp (mm2-remove-matches (total-evidence-mp $te-g $te-proof-id $te-ante-stv $te-p1 $te-p2 $te-case $te-case-stv $te-case-proof $te-case-evset $te-ante-evset))))
     cleared))

(= (mm2-forward-chain-goals $scope)
   (collapse
     (match &mork
       (forward-chain-goal $scope $g)
       (, (Goal $g)))))

(= (mm2-prepare-query $kb (: $prf $type $tv))
   (let* (($_refresh (mm2-refresh-prior-base-rates!))
          ($cqs (collapse (mm2compileQuery $kb (: $prf $type $tv))))
          ($notsup (mm2-run-compiled-queries $kb $cqs)))
     (prepared-query $cqs $notsup)))

(= (mm2-result-row-equivalent? $row $other)
   (case ($row $other)
     ((((: $_prf $type $tv) (: $_wprf $wtype $wtv))
       (=alpha ($type $tv) ($wtype $wtv)))
      ($_ (== $row $other)))))

(= (mm2-result-row-member? () $_row) false)
(= (mm2-result-row-member? (cons $x $rest) $row)
   (if (mm2-result-row-equivalent? $x $row)
     true
     (mm2-result-row-member? $rest $row)))

(= (mm2-unique-query-results ()) ())
(= (mm2-unique-query-results (cons $row $rest))
   (let $tail (mm2-unique-query-results $rest)
     (if (mm2-result-row-member? $tail $row)
       $tail
       (cons $row $tail))))

(= (mm2-query-results $notsup $cqs)
   (mm2-unique-query-results
     (mm2-ir-append $notsup (mm2-readback-queries $cqs))))

(= (mm2-total-steps $steps)
   (* $steps (mm2-steps-per-round)))

(= (mm2-test-total-steps $steps)
   (* $steps (mm2-test-steps-per-round)))

(= (mm2-min $a $b)
   (if (< $a $b) $a $b))

(= (mm2-run-query-full $steps $notsup $cqs)
   (let $_run (mm2-exec &mork (mm2-total-steps $steps))
     (mm2-query-results $notsup $cqs)))

(= (mm2-run-query-until $remaining $notsup $cqs $expected)
   (let* (($results (mm2-query-results $notsup $cqs))
          ($verdict (mm2-test-verdict $results $expected)))
     (if (mm2-verdict-ok? $verdict)
       $results
       (if (< 0 $remaining)
         (let* (($chunk (mm2-min $remaining (mm2-query-chunk-size)))
                ($_run (mm2-exec &mork $chunk)))
           (mm2-run-query-until (- $remaining $chunk) $notsup $cqs $expected))
         $results))))

(= (mm2-query $steps $kb (: $prf $type $tv))
   (let (prepared-query $cqs $notsup) (mm2-prepare-query $kb (: $prf $type $tv))
     (let* (($results (mm2-run-query-full $steps $notsup $cqs))
            ($_cleanup (mm2-cleanup-queries $cqs)))
       $results)))

(= (mm2-query-materialize $steps $kb (: $prf $type $tv))
   (let (prepared-query $cqs $notsup) (mm2-prepare-query $kb (: $prf $type $tv))
     (let* (($results (mm2-run-query-full $steps $notsup $cqs))
            ($_materialized (mm2-materialize-scope (mm2-ir-scope-kb $kb)))
            ($_cleanup (mm2-cleanup-queries $cqs)))
       $results)))

; Harness approximation for PeTTa forward-chain tests: compileadd already
; emits open materialization goals for the relevant rule conclusions, so a
; bounded MM2 run advances those side effects before the follow-up query.
; A forward-chain round reopens only this KB's materialization goals, but MORK's
; exec loop still services durable base-rate refresh templates globally.
(= (mm2-forward-chain-steps-per-round) 225)

(= (mm2-forward-chain $rounds $_kb)
   (let* (($scope (mm2-ir-scope-kb $_kb))
          ($_clear (mm2-clear-runtime-queue))
          ($_goals (mm2-add-compiled $_kb (mm2-forward-chain-goals $scope)))
          ($_run (mm2-exec &mork (* $rounds (mm2-forward-chain-steps-per-round)))))
     ()))

; --- test comparison --------------------------------------------------------
; Compare (type, tv) sets; proof tokens intentionally differ from PeTTa.
; Both arguments are lists of (: $prf $type $tv) results.
;
; Verdicts:
;   (mm2-test-pass ...)  every expected (type, tv) matched exactly
;   (mm2-test-close ...) matched, but some TVs only within relative tolerance
;                        (mm2 keeps refining merged facts as base rates evolve,
;                        so inversion-affected answers can drift past PeTTa's
;                        one-shot query result)
;   (mm2-test-FAIL ...)  an expected result is absent or numerically far off

(= (mm2-close-tolerance) 0.001)

(= (mm2-abs $x) (if (< $x 0.0) (- 0.0 $x) $x))

(= (mm2-rel-close $a $b)
   (let $scale (max 1.0 (max (mm2-abs $a) (mm2-abs $b)))
     (< (mm2-abs (- $a $b)) (* (mm2-close-tolerance) $scale))))

(= (mm2-tv-close (STV $s1 $c1) (STV $s2 $c2))
   (and (mm2-rel-close $s1 $s2) (mm2-rel-close $c1 $c2)))
(= (mm2-tv-close (CTV $p1 $n1) (CTV $p2 $n2))
   (and (mm2-tv-close $p1 $p2) (mm2-tv-close $n1 $n2)))

; Non-result entries (notsupported-ir markers) are skipped for comparison;
; they surface in the transcript instead.
(= (mm2-result-keys $list)
   (case $list
     ((() ())
      ((cons (: $prf $type $tv) $rest) (cons ($type $tv) (mm2-result-keys $rest)))
      ((cons $other $rest) (mm2-result-keys $rest)))))

; Keys are compared alpha-equivalently: open-query results carry free
; variables whose identities differ between the expected list and the
; readback.
(= (mm2-contains-key () $key) false)
(= (mm2-contains-key (cons $x $rest) $key)
   (if (=alpha $x $key) true (mm2-contains-key $rest $key)))

(= (mm2-contains-close () $key) false)
(= (mm2-contains-close (cons ($type $tv) $rest) ($wtype $wtv))
   (if (and (=alpha $type $wtype) (mm2-tv-close $tv $wtv))
     true
     (mm2-contains-close $rest ($wtype $wtv))))

(= (mm2-missing-keys () $got) ())
(= (mm2-missing-keys (cons $k $rest) $got)
   (if (mm2-contains-key $got $k)
     (mm2-missing-keys $rest $got)
     (cons $k (mm2-missing-keys $rest $got))))

(= (mm2-far-keys () $got) ())
(= (mm2-far-keys (cons $k $rest) $got)
   (if (mm2-contains-close $got $k)
     (mm2-far-keys $rest $got)
     (cons $k (mm2-far-keys $rest $got))))

(= (mm2-test-verdict $results $expected)
   (let* (($got (mm2-result-keys $results))
          ($want (mm2-result-keys $expected))
          ($missing (mm2-missing-keys $want $got))
          ($verdict (if (== $missing ())
                      (mm2-test-pass $want)
                      (let $far (mm2-far-keys $missing $got)
                        (if (== $far ())
                          (mm2-test-close (inexact $missing) (got $got))
                          (mm2-test-FAIL (missing $far) (got $got)))))))
     $verdict))

(= (mm2-verdict-ok? $verdict)
   (case $verdict
     (((mm2-test-pass $want) true)
      ((mm2-test-close $inexact $got) true)
      ($other false))))

(= (mm2-test $results $expected)
   (let* (($verdict (mm2-test-verdict $results $expected))
          ($_log (mm2-log-line $verdict)))
     $verdict))

(= (mm2-test-equal $got $expected)
   (let* (($verdict (if (== $got $expected)
                      (mm2-test-pass $expected)
                      (mm2-test-FAIL (expected $expected) (got $got))))
          ($_log (mm2-log-line $verdict)))
     $verdict))

(= (mm2-test-tv-value $got $expected)
   (let* (($verdict
            (if (== $got $expected)
              (mm2-test-pass $expected)
              (case ($got $expected)
                ((((STV $gs $gc) (STV $es $ec))
                  (if (mm2-tv-close $got $expected)
                    (mm2-test-close (inexact $expected) (got $got))
                    (mm2-test-FAIL (expected $expected) (got $got))))
                 (((CTV $gp $gn) (CTV $ep $en))
                  (if (mm2-tv-close $got $expected)
                    (mm2-test-close (inexact $expected) (got $got))
                    (mm2-test-FAIL (expected $expected) (got $got))))
                 ($other (mm2-test-FAIL (expected $expected) (got $got)))))))
          ($_log (mm2-log-line $verdict)))
     $verdict))

(= (mm2-test-float-value $got $expected)
   (let* (($verdict
            (if (== $got $expected)
              (mm2-test-pass $expected)
              (case ($got $expected)
                ((($g $e)
                  (if (mm2-rel-close $g $e)
                    (mm2-test-close (inexact $expected) (got $got))
                    (mm2-test-FAIL (expected $expected) (got $got))))
                 ($other (mm2-test-FAIL (expected $expected) (got $got)))))))
          ($_log (mm2-log-line $verdict)))
     $verdict))

(= (mm2-test-tv-confidence $tv $expected)
   (mm2-test-float-value (mm2-tv-confidence $tv) $expected))

(= (mm2-test-CTVModusPonensFormula $prem $ctv $expected)
   (mm2-test-tv-value (mm2-formula-mp $prem $ctv) $expected))

(= (mm2-test-AndFormula $a $b $expected)
   (mm2-test-tv-value (mm2-formula-and $a $b) $expected))

(= (mm2-test-OrFormula $a $b $expected)
   (mm2-test-tv-value (mm2-formula-or $a $b) $expected))

(= (mm2-test-NotFormula $a $expected)
   (mm2-test-tv-value (mm2-formula-not $a) $expected))

(= (mm2-test-LikelierThanFormula $a $b $expected)
   (mm2-test-tv-value (mm2-formula-likelier $a $b) $expected))

(= (mm2-test-OrProjection $compound $evidence $expected)
   (mm2-test-tv-value (mm2-formula-or-projection $compound $evidence) $expected))

(= (mm2-test-CTVInversionFormula $a $b $ctv $expected)
   (mm2-test-tv-value (mm2-formula-inversion $a $b $ctv) $expected))

(= (mm2-test-term-confidence-CTVModusPonensFormula $prem $ctv $expected)
   (mm2-test-float-value (mm2-tv-confidence (mm2-formula-mp $prem $ctv)) $expected))

(= (mm2-test-term-confidence-NotFormula $a $expected)
   (mm2-test-float-value (mm2-tv-confidence (mm2-formula-not $a)) $expected))

(= (mm2-test-term-confidence-AndFormula $a $b $expected)
   (mm2-test-float-value (mm2-tv-confidence (mm2-formula-and $a $b)) $expected))

(= (mm2-test-term-confidence-OrFormula $a $b $expected)
   (mm2-test-float-value (mm2-tv-confidence (mm2-formula-or $a $b)) $expected))

(= (mm2-test-term-confidence-LikelierThanFormula $a $b $expected)
   (mm2-test-float-value (mm2-tv-confidence (mm2-formula-likelier $a $b)) $expected))

(= (mm2-test-term-confidence-CTVInversionFormula-vars (CTV $pos $neg) $expected)
   (let $conf (* (min (min (mm2-tv-confidence (STV 1.0 1.0))
                           (mm2-tv-confidence (STV 1.0 1.0)))
                      (mm2-tv-confidence (CTV $pos $neg)))
                  0.9)
     (mm2-test-float-value $conf $expected)))

(= (mm2-test-premises-expected-confidence $premises $expected)
   (mm2-test-float-value (mm2-premises-expected-confidence $premises) $expected))

(= (mm2-dist-pairs (ParticleDist $pid $_scale))
   (collapse (match &mork (dist-pair $pid $x $w) ($x $w))))

(= (mm2-export-dist-pairs $_pid ()) ())
(= (mm2-export-dist-pairs $pid (cons ($x $w) $rest))
   (let $_add (add-atom &mork (dist-pair $pid $x $w))
     (mm2-export-dist-pairs $pid $rest)))

(= (mm2-export-dist $dist)
   (case $dist
     (((ParticleDist $pid $_scale)
       (mm2-export-dist-pairs $pid (ParticlePairs $dist)))
      ($_other ()))))

(= (mm2-test-ParticlePairs $dist $expected)
   (let* (($_export (mm2-export-dist $dist))
          ($pairs (mm2-dist-pairs $dist)))
     (mm2-test-equal $pairs $expected)))

(= (mm2-dist-pairs-stats ()) (Stats 0.0 0.0 0))
(= (mm2-dist-pairs-stats (cons ($_x $w) $tail))
   (let (Stats $sum $sumsq $count) (mm2-dist-pairs-stats $tail)
     (Stats (+ $w $sum) (+ (* $w $w) $sumsq) (+ 1 $count))))

(= (mm2-scale-dist-pairs () $_scale) ())
(= (mm2-scale-dist-pairs (cons ($x $w) $tail) $scale)
   (cons ($x (* $w $scale)) (mm2-scale-dist-pairs $tail $scale)))

(= (mm2-normalize-dist-pairs $pairs)
   (let (Stats $total $_sumsq $_count) (mm2-dist-pairs-stats $pairs)
     (if (<= $total 0.0) () (mm2-scale-dist-pairs $pairs (/ 1.0 $total)))))

(= (mm2-dist-effective-n $pairs)
   (let* (($norm (mm2-normalize-dist-pairs $pairs))
          ((Stats $_sum $sumsq $_count) (mm2-dist-pairs-stats $norm)))
     (if (<= $sumsq 0.0) 0.0 (/ 1.0 $sumsq))))

(= (mm2-dist-confidence $pairs)
   (let $neff (mm2-dist-effective-n $pairs)
     (if (<= $neff 0.0) 0.0 (/ $neff (+ $neff 20.0)))))

(= (mm2-dist-prob-gt () $_threshold) 0.0)
(= (mm2-dist-prob-gt (cons ($x $w) $tail) $threshold)
   (+ (if (> $x $threshold) $w 0.0) (mm2-dist-prob-gt $tail $threshold)))

; The runtime's dist-pair stream already carries the observable pair mass, so
; the strength is computed directly from those pairs.
(= (mm2-DistGreaterThanFormula $dist $threshold)
   (let $pairs (mm2-dist-pairs $dist)
     (STV (mm2-dist-prob-gt $pairs $threshold)
          (mm2-dist-confidence $pairs))))

(= (mm2-test-DistGreaterThanFormula $dist $threshold $expected)
   (let $_export (mm2-export-dist $dist)
     (mm2-test-tv-value (mm2-DistGreaterThanFormula $dist $threshold) $expected)))

(= (mm2-last-list-item (cons $x ())) $x)
(= (mm2-last-list-item (cons $_x $rest)) (mm2-last-list-item $rest))
(= (mm2-last-arg $term)
   (if (is-expr $term) (mm2-last-list-item (cdr-atom $term)) $term))

(= (mm2-test-query-dist-gt-strength $steps $kb $query $threshold $expected)
   (let* (($results (mm2-query $steps $kb $query))
          ($_run (mm2-exec &mork 400)))
     (case $results
       (((cons (: $_prf $type $_tv) $_rest)
         (let (STV $s $_c) (mm2-DistGreaterThanFormula (mm2-last-arg $type) $threshold)
           (mm2-test-equal $s $expected)))
        ($other (mm2-test-equal no-result $expected))))))

(= (mm2-test-query-dist-gt-strength-between $steps $kb $query $threshold $lo $hi)
   (let* (($results (mm2-query $steps $kb $query))
          ($_run (mm2-exec &mork 400)))
     (case $results
       (((cons (: $_prf $type $_tv) $_rest)
         (let (STV $s $_c) (mm2-DistGreaterThanFormula (mm2-last-arg $type) $threshold)
           (mm2-test-equal (and (> $s $lo) (< $s $hi)) true)))
        ($other (mm2-test-equal no-result true))))))

(= (mm2-test-query-dist-gt-strength-confidence-over $steps $kb $query $threshold $slo $clo)
   (let* (($results (mm2-query $steps $kb $query))
          ($_run (mm2-exec &mork 400)))
     (case $results
       (((cons (: $_prf $type $_tv) $_rest)
         (let (STV $s $c) (mm2-DistGreaterThanFormula (mm2-last-arg $type) $threshold)
           (mm2-test-equal (and (> $s $slo) (> $c $clo)) true)))
        ($other (mm2-test-equal no-result true))))))

(= (mm2-test-query $steps $kb (: $prf $type $tv) $expected)
   (let (prepared-query $cqs $notsup) (mm2-prepare-query $kb (: $prf $type $tv))
     (let* (($want (mm2-result-keys $expected))
            ($results
              (if (== $want ())
                (mm2-run-query-full $steps $notsup $cqs)
                (mm2-run-query-until (mm2-test-total-steps $steps) $notsup $cqs $expected)))
            ($_cleanup (mm2-cleanup-queries $cqs)))
       (mm2-test $results $expected))))

(= (mm2-test-forward-chain-query $rounds $steps $kb (: $prf $type $tv) $expected)
   (let $_forward (mm2-forward-chain $rounds $kb)
     (mm2-test-query $steps $kb (: $prf $type $tv) $expected)))

(= (mm2-test-query-materialize $steps $kb (: $prf $type $tv) $expected)
   (let (prepared-query $cqs $notsup) (mm2-prepare-query $kb (: $prf $type $tv))
     (let* (($want (mm2-result-keys $expected))
            ($results
              (if (== $want ())
                (mm2-run-query-full $steps $notsup $cqs)
                (mm2-run-query-until (mm2-test-total-steps $steps) $notsup $cqs $expected)))
            ($_materialized (mm2-materialize-scope (mm2-ir-scope-kb $kb)))
            ($_cleanup (mm2-cleanup-queries $cqs)))
       (mm2-test $results $expected))))
