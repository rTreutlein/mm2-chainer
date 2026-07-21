!(import! &self /nexus/Dev/OpenCog/NL2PLN_Project/mm2-chainer/compiler/mm2_chainer)
!(mm2-init)

(= (batch-test-result $_id ()) ())
(= (batch-test-result $id (cons (query-result $candidate $results) $rest))
   (if (== $id $candidate)
     $results
     (batch-test-result $id $rest)))

; Later statements in one insertion batch must see compiler IR installed by
; earlier statements. This rule specializes Symmetric to Friend only if the
; tag and fact preceding it were made compiler-visible in order.
!(mm2-test-equal
   (mm2-compileadd-many batchKb
     (cons
       (: tag (Symmetric Friend) (STV 1.0 1.0))
       (cons
         (: fact (Friend bob alice) (STV 1.0 1.0))
         (cons
           (: rule
              (Implication
                (Premises (Symmetric $r) ($r $x $y))
                (Conclusions ($r $y $x)))
              (STV 0.9 0.9))
           ()))))
   ())

!(mm2-test-equal
   (match &mork
     (mm2-compiler-fact-ir ((Symmetric $x) (batchKb MAIN Nil) $proof $tv))
     ($x $proof))
   (Friend tag))

!(mm2-test-query 100 batchKb
   (: $proof (Friend alice bob) $tv)
   ((: $_ (Friend alice bob) (STV 0.9 0.8999999985415723))))

; Results stay grouped by caller-provided tags. Identical queries are retained
; as two result groups instead of being flattened and deduplicated together.
!(let $batch
   (mm2-query-many 40 batchKb
     (cons
       (query original (: $proof (Friend bob alice) $tv))
       (cons
         (query derived (: $proof (Friend alice bob) $tv))
         (cons
           (query derived-copy (: $proof (Friend alice bob) $tv))
           ()))))
   (let $_count (mm2-test-equal (length $batch) 3)
     (let $_original
       (mm2-test
         (batch-test-result original $batch)
         ((: $_ (Friend bob alice) (STV 1.0 1.0))))
       (let $_derived
         (mm2-test
           (batch-test-result derived $batch)
           ((: $_ (Friend alice bob) (STV 0.9 0.8999999985415723))))
         (mm2-test
           (batch-test-result derived-copy $batch)
           ((: $_ (Friend alice bob) (STV 0.9 0.8999999985415723))))))))

; Total-implication query assumptions use private contexts. Preparing and
; executing that query beside a public A query must not make A true publicly.
!(let $batch
   (mm2-query-many 40 isolatedKb
     (cons
       (query implication
         (: $proof
            (Implication (Premises (A)) (Conclusions (A)))
            $tv))
       (cons
         (query public (: $proof (A) $tv))
         ())))
   (let $_count (mm2-test-equal (length $batch) 2)
     (let $_implication
       (mm2-test
         (batch-test-result implication $batch)
         ((: $_
             (Implication (Premises (A)) (Conclusions (A)))
             (CTV (STV 1.0 1.0) (STV 0.0 1.0)))))
       (mm2-test (batch-test-result public $batch) ()))))

; Batch cleanup runs only after every result group has been read and removes
; the private query scaffolds without leaking their assumptions.
!(add-atom &mork (, (Goal (durable-goal))))
!(mm2-test-query 10 isolatedKb (: $proof (A) $tv) ())

; Query cleanup removes premise/subgoal Goals created while executing a batch,
; while preserving Goals that existed before the query session.
!(mm2-test-equal
   (collapse (match &mork (, (Goal $goal)) $goal))
   ((durable-goal)))

; The controller owns and removes the translated batch, finite scheduler state,
; and saved loop.  Results from the previous batch are also discarded when the
; next request starts, while the latest tagged responses remain readable.
!(mm2-test-equal
   (collapse (match &mork (mm2-query-owned $session $atom) ($session $atom)))
   ())
!(mm2-test-equal
   (collapse (match &mork (mm2-query-run $session $rounds $partial)
                           ($session $rounds $partial)))
   ())
!(mm2-test-equal
   (collapse (match &mork (mm2-query-session-loop $session $loop)
                           ($session $loop)))
   ())
!(mm2-test-equal
   (collapse (match &mork
               (mm2-query-response $session original $payload)
               ($session $payload)))
   ())
!(remove-atom &mork (, (Goal (durable-goal))))
