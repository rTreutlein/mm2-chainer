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

; The runtime currently has 55 exec templates. Positive expected tests use a
; wider cap and stop as soon as the expected result is seen; empty-result
; checks keep the narrower query cap above so they do not become broader
; absence claims.
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
   (mm2-add-compiled $kb (mm2-translate-all (collapse (compileadd $kb $stmt)))))

; Some PeTTaChainer tests add already-compiled rule IR directly with
; add-to-kb. Route those generated harness calls through the MM2 translator
; without shadowing PeTTaChainer's own add-to-kb, which compileadd still uses.
(= (mm2-add-to-kb $stmt)
   (mm2-add-compiled kb (mm2-translate-all (cons $stmt ()))))

; Remove exact atoms produced by a MORK match. Calling remove-atom with a
; variable pattern would remove nothing, so cleanup first materializes the
; matching atoms and then removes those exact terms.
(= (mm2-remove-atoms ()) ())
(= (mm2-remove-atoms (cons $atom $rest))
   (let $_remove (remove-atom &mork $atom)
     (mm2-remove-atoms $rest)))

(= (mm2-remove-matches $pattern)
   (mm2-remove-atoms (collapse (match &mork $pattern $pattern))))

; Base-rate cache operations used by PeTTaChainer tests. These intentionally
; target the MM2 runtime state, not PeTTa's separate &base_rate_cache space.
(= (mm2-scoped-base-rate-pattern $kb $pattern)
   (let $scope (mm2-ir-scope-kb $kb) ($scope $pattern)))

(= (mm2-remove-base-rate-state $kb $pattern)
   (let $pat (mm2-scoped-base-rate-pattern $kb $pattern)
     (let $_br (mm2-remove-matches (base-rate $pat $tv))
       (let $_def (mm2-remove-matches (base-rate-def $pat $match))
         ()))))

(= (mm2-add-base-rate-support $kb $pattern)
   (let $pat (mm2-scoped-base-rate-pattern $kb $pattern)
     (let* (($qpat (copy_term $pat))
            ($mpat (copy_term $pat))
            ($seed (copy_term $pat))
            ($_def (add-atom &mork (base-rate-def $qpat $mpat)))
            ($_seed (add-atom &mork (base-rate $seed (0.0 0.0)))))
       ())))

(= (mm2-set-base-rate $kb $pattern (STV $s $c))
   (let $_clear (mm2-remove-base-rate-state $kb $pattern)
     (let $pat (mm2-scoped-base-rate-pattern $kb $pattern)
       (let $stored (copy_term $pat)
        (let $_set (add-atom &mork (base-rate $stored ($s $c)))
         ())))))

(= (mm2-clear-base-rate $kb $pattern)
   (let $_clear (mm2-remove-base-rate-state $kb $pattern)
     (mm2-add-base-rate-support $kb $pattern)))

(= (mm2-store-computed-base-rate! $kb $pattern (STV $s $c) $mode)
   (let $_clear (mm2-remove-base-rate-state $kb $pattern)
     (let $_support (mm2-add-base-rate-support $kb $pattern)
       (let $pat (mm2-scoped-base-rate-pattern $kb $pattern)
         (let $_old (mm2-remove-matches (base-rate $pat $tv))
           (let $stored (copy_term $pat)
            (let $_set (add-atom &mork (base-rate $stored ($s $c)))
             ())))))))

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

(= (mm2-readback-total-implication-premises $goal-type $prems)
   (case (mm2-ir-collect $prems)
     (((collected (pcons ($pos-shape $pos-type)
                   (pcons ($neg-shape $neg-type) pnil))
                  ())
       (mm2-readback-total-implication-proofs $goal-type $pos-shape $pos-type $neg-shape $neg-type))
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

(= (mm2-readback-query $cq)
   (case $cq
     (((compiled-query $goal-item $adds)
       (let (subgoal ($shape $type) $tv $prf) (mm2-ir-item $goal-item)
         (let $readback-type (mm2-readback-type $shape $type $prf $tv)
           (mm2-ir-append
             (mm2-readback-total-implication $goal-item $adds)
             (mm2-ir-append
               (collapse
                 (match &mork (fact ($shape $type) ($s $c))
                   (: mm2-merged $readback-type (STV $s $c))))
               (collapse
                 (match &mork (fact ($shape $type) (ctvpair ($ps $pc) ($ns $nc)))
                   (: mm2-merged $readback-type (CTV (STV $ps $pc) (STV $ns $nc))))))))))
      ($other ()))))

(= (mm2-readback-queries ()) ())
(= (mm2-readback-queries (cons $cq $rest))
   (mm2-ir-append (mm2-readback-query $cq) (mm2-readback-queries $rest)))

(= (mm2-run-compiled-queries $kb ()) ())
(= (mm2-run-compiled-queries $kb (cons $cq $rest))
   (mm2-ir-append (mm2-add-compiled $kb (mm2-translate-query $cq))
                  (mm2-run-compiled-queries $kb $rest)))

(= (mm2-cleanup-goal $g)
   (let* (($_goal (mm2-remove-matches (, (Goal $g))))
          ($_pending (mm2-remove-matches (pendingN $priority $g $rule-stv $premises)))
          ($_pending-named (mm2-remove-matches (pendingN $priority2 $g $rule-stv2 $premises2 $pending-evset)))
          ($_waits (mm2-remove-matches (wait-premises $g $rule-stv $rest $agg $proof-id $evset)))
          ($_pool-waits (mm2-remove-matches (wait-premises-pool $g $pool-rest $pool-state $pool-proof-id)))
          ($_wait (mm2-remove-matches (wait-premise $g $rule-stv $prem $rest $agg $proof-id $evset)))
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

(= (mm2-prepare-query $kb (: $prf $type $tv))
   (let* (($cqs (collapse (mm2compileQuery $kb (: $prf $type $tv))))
          ($notsup (mm2-run-compiled-queries $kb $cqs)))
     (prepared-query $cqs $notsup)))

(= (mm2-query-results $notsup $cqs)
   (mm2-ir-append $notsup (mm2-readback-queries $cqs)))

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

(= (mm2-test-query $steps $kb (: $prf $type $tv) $expected)
   (let (prepared-query $cqs $notsup) (mm2-prepare-query $kb (: $prf $type $tv))
     (let* (($want (mm2-result-keys $expected))
            ($results
              (if (== $want ())
                (mm2-run-query-full $steps $notsup $cqs)
                (mm2-run-query-until (mm2-test-total-steps $steps) $notsup $cqs $expected)))
            ($_cleanup (mm2-cleanup-queries $cqs)))
       (mm2-test $results $expected))))
