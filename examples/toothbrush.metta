!(import! &self /nexus/Dev/OpenCog/NL2PLN_Project/mm2-chainer/compiler/mm2_chainer)
!(mm2-init)

!(mm2-set-base-rate toothbrushKb (Inheritance $x madeOfPlastic) (STV 0.5 0.9))
!(mm2-set-base-rate toothbrushKb (Inheritance $x heated) (STV 0.5 0.9))
!(mm2-set-base-rate toothbrushKb (Inheritance $x melted) (STV 0.5 0.9))
!(mm2-set-base-rate toothbrushKb (Inheritance $x pliable) (STV 0.5 0.9))
!(mm2-set-base-rate toothbrushKb (Inheritance $x screwlike) (STV 0.5 0.9))
!(mm2-set-base-rate toothbrushKb (Inheritance $x hardened) (STV 0.5 0.9))
!(mm2-set-base-rate toothbrushKb (Inheritance $x removed) (STV 0.5 0.9))
!(mm2-set-base-rate toothbrushKb (Operation $x opLighter) (STV 0.5 0.9))
!(mm2-set-base-rate toothbrushKb (Operation $x opReshape) (STV 0.5 0.9))
!(mm2-set-base-rate toothbrushKb (Operation $x opWait) (STV 0.5 0.9))
!(mm2-set-base-rate toothbrushKb (Operation $x opUnscrew) (STV 0.5 0.9))
!(mm2-set-base-rate toothbrushKb (And (Inheritance $x madeOfPlastic) (Operation $x opLighter)) (STV 0.25 0.9))
!(mm2-set-base-rate toothbrushKb (And (Inheritance $x pliable) (Operation $x opReshape)) (STV 0.25 0.9))
!(mm2-set-base-rate toothbrushKb (And (Inheritance $x screwlike) (Operation $x opWait)) (STV 0.25 0.9))
!(mm2-set-base-rate toothbrushKb (And (Inheritance $x hardened) (Operation $x opUnscrew)) (STV 0.25 0.9))

!(mm2-compileadd toothbrushKb
   (: lighterHeatsPlastic
      (Implication
         (Premises (Inheritance $x madeOfPlastic) (Operation $x opLighter))
         (Conclusions (Inheritance $x heated)))
      (STV 0.99 0.99)))
!(mm2-compileadd toothbrushKb
   (: heatedMelts
      (Implication
         (Premises (Inheritance $x heated))
         (Conclusions (Inheritance $x melted)))
      (STV 0.99 0.99)))
!(mm2-compileadd toothbrushKb
   (: meltedPliable
      (Implication
         (Premises (Inheritance $x melted))
         (Conclusions (Inheritance $x pliable)))
      (STV 0.99 0.99)))
!(mm2-compileadd toothbrushKb
   (: reshapePliableScrewlike
      (Implication
         (Premises (Inheritance $x pliable) (Operation $x opReshape))
         (Conclusions (Inheritance $x screwlike)))
      (STV 0.99 0.99)))
!(mm2-compileadd toothbrushKb
   (: waitHardensScrewlike
      (Implication
         (Premises (Inheritance $x screwlike) (Operation $x opWait))
         (Conclusions (Inheritance $x hardened)))
      (STV 0.99 0.99)))
!(mm2-compileadd toothbrushKb
   (: unscrewRemovesHardened
      (Implication
         (Premises (Inheritance $x hardened) (Operation $x opUnscrew))
         (Conclusions (Inheritance $x removed)))
      (STV 0.99 0.99)))

!(mm2-compileadd toothbrushKb (: xPlastic (Inheritance X madeOfPlastic) (STV 0.99 0.99)))
!(mm2-compileadd toothbrushKb (: xLighter (Operation X opLighter) (STV 0.99 0.99)))
!(mm2-compileadd toothbrushKb (: xReshape (Operation X opReshape) (STV 0.99 0.99)))
!(mm2-compileadd toothbrushKb (: xWait (Operation X opWait) (STV 0.99 0.99)))
!(mm2-compileadd toothbrushKb (: xUnscrew (Operation X opUnscrew) (STV 0.99 0.99)))

; MM2 revises the same successful operation chain with a slightly stronger
; confidence estimate than PeTTaChainer's current population snapshot.
!(mm2-test-query-proofs 200 toothbrushKb
   (: $prf (Inheritance X removed) $tv)
   ((: (mm2-proof
          ((inheritance-rule-lift waitHardensScrewlike)
           xUnscrew
           (inheritance-rule-lift unscrewRemovesHardened)))
       (Inheritance X removed)
       (STV 0.8953382542587163 0.9934873383312783))))
