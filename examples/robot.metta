!(import! &self /nexus/Dev/OpenCog/NL2PLN_Project/mm2-chainer/compiler/mm2_chainer)
!(mm2-init)

!(mm2-set-base-rate robotKb (Inheritance $x toy) (STV 0.5 0.9))
!(mm2-set-base-rate robotKb (Inheritance $x see) (STV 0.5 0.9))
!(mm2-set-base-rate robotKb (Inheritance $x bring) (STV 0.5 0.9))
!(mm2-set-base-rate robotKb (Inheritance $x round) (STV 0.5 0.9))
!(mm2-set-base-rate robotKb (And (Inheritance $x toy) (Inheritance $x see)) (STV 0.25 0.9))
!(mm2-set-base-rate robotKb
   (And
      (Inheritance $obj $property)
      (Inheritance $prototype $property)
      (Inheritance $prototype $category))
   (STV 0.125 0.9))
!(mm2-set-base-rate robotKb
   (And
      (Inheritance $obj $property)
      (Inheritance $prototype $property)
      (Inheritance $prototype toy)
      (Inheritance $obj see))
   (STV 0.0625 0.9))

!(mm2-compileadd robotKb
   (: toySeenBring
      (Implication
         (Premises (Inheritance $x toy) (Inheritance $x see))
         (Conclusions (Inheritance $x bring)))
      (STV 0.99 0.99)))

!(mm2-compileadd robotKb (: frisbeeToy (Inheritance frisbee toy) (STV 0.99 0.99)))
!(mm2-compileadd robotKb (: sportsballToy (Inheritance sportsball toy) (STV 0.99 0.99)))
!(mm2-compileadd robotKb (: orangeRound (Inheritance orange round) (STV 0.99 0.99)))
!(mm2-compileadd robotKb (: sportsballRound (Inheritance sportsball round) (STV 0.99 0.99)))

; The detector has one known category prototype. Specializing it at compile
; time preserves the generic source rule while avoiding a runtime search over
; arbitrary objects as potential prototypes.
!(set-specializing-predicate Prototype)
!(mm2-compileadd robotKb (: sportsballPrototype (Prototype sportsball) (STV 1.0 1.0)))

; These bridge rules express classification policy rather than observations,
; so the shared compiler must not register their names as evidence.
!(mark-logic-rule sharedPropertyCategory)
!(mm2-compileadd robotKb
   (: sharedPropertyCategory
      (Implication
         (Premises
            (Prototype $prototype)
            (Inheritance $obj $property)
            (Inheritance $prototype $property)
            (Inheritance $prototype $category))
         (Conclusions (Inheritance $obj $category)))
      (STV 0.99 0.99)))

!(mark-logic-rule sharedPropertySeenBring)
!(mm2-compileadd robotKb
   (: sharedPropertySeenBring
      (Implication
         (Premises
            (Prototype $prototype)
            (Inheritance $obj $property)
            (Inheritance $prototype $property)
            (Inheritance $prototype toy)
            (Inheritance $obj see))
         (Conclusions (Inheritance $obj bring)))
      (STV 0.99 0.99)))

!(mm2-compileadd robotKb (: seenFrisbee (Inheritance frisbee see) (STV 0.99 0.99)))
!(mm2-compileadd robotKb (: seenSelfRobot (Inheritance selfRobot see) (STV 0.99 0.99)))
!(mm2-compileadd robotKb (: seenPerson (Inheritance person see) (STV 0.99 0.99)))
!(mm2-compileadd robotKb (: seenOrange (Inheritance orange see) (STV 0.99 0.99)))

; Put the current detector frame into the KB so the query binds a finite label
; before evaluating the inheritance classification.
!(mm2-compileadd robotKb (: detectionFrisbee (Detection frisbee someCoords1) (STV 1.0 1.0)))
!(mm2-compileadd robotKb (: detectionSelfRobot (Detection selfRobot someCoords2) (STV 1.0 1.0)))
!(mm2-compileadd robotKb (: detectionPerson (Detection person someCoords3) (STV 1.0 1.0)))
!(mm2-compileadd robotKb (: detectionOrange (Detection orange someCoords4) (STV 1.0 1.0)))

(= (robot-high-confidence-label? $label $category $results)
   (case $results (
      (() false)
      ((cons
         (: (mm2-proof $_evidence)
            (And
               (Detection $found $_coord)
               (Inheritance $found $found-category))
            (STV $s $c))
         $rest)
       (if (and (== $label $found)
                (and (== $category $found-category)
                     (and (> $s 0.8) (> $c 0.8))))
         true
         (robot-high-confidence-label? $label $category $rest)))
      ((cons $_other $rest)
       (robot-high-confidence-label? $label $category $rest)))))

(= (PLNobjectsOfCategoryHelper () $_category $_results) ())
(= (PLNobjectsOfCategoryHelper
      (cons (detection $label $coord) $rest)
      $category
      $results)
   (if (robot-high-confidence-label? $label $category $results)
      (cons (detection $label $coord)
         (PLNobjectsOfCategoryHelper $rest $category $results))
      (PLNobjectsOfCategoryHelper $rest $category $results)))

(= (PLNobjectsOfCategory $objects $category)
   (let $results
      (mm2-query 80 robotKb
         (: $proof
            (And
               (Detection $label $coord)
               (Inheritance $label $category))
            $_tv))
      (PLNobjectsOfCategoryHelper $objects $category $results)))

!(mm2-test-equal
   (PLNobjectsOfCategory
      (cons (detection frisbee someCoords1)
        (cons (detection selfRobot someCoords2)
          (cons (detection person someCoords3)
            (cons (detection orange someCoords4) ()))))
      bring)
   ((detection frisbee someCoords1) (detection orange someCoords4)))
