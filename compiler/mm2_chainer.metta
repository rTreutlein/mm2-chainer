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
; (notsupported-ir ...) markers in the output — the coverage gap list. Every
; compiled goal term is wrapped as ($kb $term) so multiple named KBs share
; the one &mork space without cross-talk, mirroring PeTTaChainer's named-KB
; scoping.
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

; --- kb scoping -----------------------------------------------------------
; Wrap each goal-level term as ($kb $term). All runtime relations are generic
; over goal terms, so wrapping at the compile boundary scopes facts, rules,
; base rates, and goals to their KB with no runtime changes.

(= (mm2-wrap-premises $kb pnil) pnil)
(= (mm2-wrap-premises $kb (pcons $p $rest))
   (pcons ($kb $p) (mm2-wrap-premises $kb $rest)))

(= (mm2-wrap-rule-tv $kb (ctv $pos $neg)) (ctv $pos $neg))
(= (mm2-wrap-rule-tv $kb (stv $pos (brpat $ante $cons)))
   (stv $pos (brpat ($kb $ante) ($kb $cons))))
(= (mm2-wrap-rule-tv $kb (inv $pos (brpat $ante $cons)))
   (inv $pos (brpat ($kb $ante) ($kb $cons))))

(= (mm2-wrap-atom $kb (fact $t $tv)) (fact ($kb $t) $tv))
(= (mm2-wrap-atom $kb (fact-evidence $t $tv (pcons (fact-ev $e) pnil)))
   (fact-evidence ($kb $t) $tv (pcons (fact-ev ($kb $e)) pnil)))
(= (mm2-wrap-atom $kb (ruleN $c $rule-tv $premises))
   (ruleN ($kb $c) (mm2-wrap-rule-tv $kb $rule-tv) (mm2-wrap-premises $kb $premises)))
(= (mm2-wrap-atom $kb (adapterN $c $premises))
   (adapterN ($kb $c) (mm2-wrap-premises $kb $premises)))
(= (mm2-wrap-atom $kb (base-rate-def $q $m)) (base-rate-def ($kb $q) ($kb $m)))
(= (mm2-wrap-atom $kb (base-rate $q $tv)) (base-rate ($kb $q) $tv))
(= (mm2-wrap-atom $kb (, (Goal $t))) (, (Goal ($kb $t))))
(= (mm2-wrap-atom $kb (notsupported-ir $x)) (notsupported-ir $kb $x))

; --- compileadd / query ----------------------------------------------------

; add-atom stores its argument unevaluated, so the wrap is forced via let
; before the add. (notsupported-ir ...) markers are both stored (wrapped, for
; postmortem inspection of the space) and returned so they print in the test
; transcript.
(= (mm2-add-compiled $kb ()) ())
(= (mm2-add-compiled $kb (cons $atom $rest))
   (let* (($wrapped (mm2-wrap-atom $kb $atom))
          ($_add (add-atom &mork $wrapped)))
     (case $atom
       (((notsupported-ir $x)
         (let $_log (mm2-log-line (notsupported-ir $x))
           (cons (notsupported-ir $x) (mm2-add-compiled $kb $rest))))
        ($other (mm2-add-compiled $kb $rest))))))

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

(= (mm2-query-readback $kb $type)
   (collapse
     (match &mork (fact ($kb $type) ($s $c))
       (: mm2-merged $type (STV $s $c)))))

(= (mm2-run-compiled-queries $kb ()) ())
(= (mm2-run-compiled-queries $kb (cons $cq $rest))
   (mm2-ir-append (mm2-add-compiled $kb (mm2-translate-query $cq))
                  (mm2-run-compiled-queries $kb $rest)))

(= (mm2-query $steps $kb (: $prf $type $tv))
   (let* (($notsup (mm2-run-compiled-queries $kb (collapse (mm2compileQuery $kb (: $prf $type $tv)))))
          ($_run (mm2-exec &mork (* $steps (mm2-steps-per-round)))))
     (mm2-ir-append $notsup (mm2-query-readback $kb $type))))

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

; Non-result entries (notsupported-ir markers) are skipped for comparison;
; they surface in the transcript instead.
(= (mm2-result-keys $list)
   (case $list
     ((() ())
      ((cons (: $prf $type $tv) $rest) (cons ($type $tv) (mm2-result-keys $rest)))
      ((cons $other $rest) (mm2-result-keys $rest)))))

(= (mm2-contains-key () $key) false)
(= (mm2-contains-key (cons $x $rest) $key)
   (if (== $x $key) true (mm2-contains-key $rest $key)))

(= (mm2-contains-close () $key) false)
(= (mm2-contains-close (cons ($type $tv) $rest) ($wtype $wtv))
   (if (and (== $type $wtype) (mm2-tv-close $tv $wtv))
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

(= (mm2-test $results $expected)
   (let* (($got (mm2-result-keys $results))
          ($want (mm2-result-keys $expected))
          ($missing (mm2-missing-keys $want $got))
          ($verdict
            (if (== $missing ())
              (mm2-test-pass $want)
              (let $far (mm2-far-keys $missing $got)
                (if (== $far ())
                  (mm2-test-close (inexact $missing) (got $got))
                  (mm2-test-FAIL (missing $far) (got $got))))))
          ($_log (mm2-log-line $verdict)))
     $verdict))
