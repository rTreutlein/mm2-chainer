!(import! &self /nexus/Dev/OpenCog/NL2PLN_Project/mm2-chainer/compiler/mm2_chainer)
!(mm2-init)

!(mm2-compileadd flyingRavenKb (: samRaven (Inheritance Sam Raven) (STV 0.99 0.9)))
!(mm2-compileadd flyingRavenKb (: pinguPenguin (Inheritance Pingu Penguin) (STV 0.99 0.9)))

!(mm2-compileadd flyingRavenKb
   (: penguinsDoNotFly
      (Implication
         (Premises (Inheritance $x Penguin))
         (Conclusions (Not (Inheritance $x (IntSet flies)))))
      (CTV (STV 1.0 0.9) (STV 0.0 1.0))))

!(mm2-compileadd flyingRavenKb (: ravenBird (Inheritance Raven Bird) (STV 0.99 0.9)))
!(mm2-compileadd flyingRavenKb (: penguinBird (Inheritance Penguin Bird) (STV 0.99 0.9)))
!(mm2-compileadd flyingRavenKb (: birdFlies (Inheritance Bird (IntSet flies)) (STV 0.99 0.9)))

; MM2 admits each application-local inheritance proof row once while excluding
; self-dependent evidence. Its stable estimates therefore differ slightly from
; PeTTaChainer's current population snapshot.
!(mm2-test-query-proofs 40 flyingRavenKb
   (: $prf (Inheritance Sam (IntSet flies)) $tv)
   ((: (mm2-proof
          ((inheritance-implication samRaven)
           (inheritance-implication birdFlies)
           (inheritance-implication ravenBird)
           negated
           (ctx proof 0)
           (derived-inheritance Pingu Penguin)))
       (Inheritance Sam (IntSet flies))
       (STV 0.9579792391250098 0.8722887806330414))))

!(mm2-test-query-proofs 40 flyingRavenKb
   (: $prf (Inheritance Pingu (IntSet flies)) $tv)
   ((: (mm2-proof
          ((inheritance-implication birdFlies)
           (inheritance-implication penguinBird)
           (inheritance-implication pinguPenguin)
           negated
           (ctx proof 2)
           (inverted-inheritance Bird Penguin)))
       (Inheritance Pingu (IntSet flies))
       (STV 0.4231076631730837 0.9400246915390111))))

!(mm2-test-query-proofs 40 flyingRavenKb
   (: $prf (Inheritance Pingu (IntSet flies)) $tv)
   ((: (mm2-proof
          ((inheritance-implication birdFlies)
           (inheritance-implication penguinBird)
           (inheritance-implication pinguPenguin)
           negated
           (ctx proof 4)
           (inverted-inheritance Bird Penguin)))
       (Inheritance Pingu (IntSet flies))
       (STV 0.4231076631730837 0.9400246915390111))))
