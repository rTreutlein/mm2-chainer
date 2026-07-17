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
!(mm2-test-query 40 flyingRavenKb
   (: $prf (Inheritance Sam (IntSet flies)) $tv)
   ((: $_proof
       (Inheritance Sam (IntSet flies))
       (STV 0.9733353514140296 0.9015950434779885))))

!(mm2-test-query 40 flyingRavenKb
   (: $prf (Inheritance Pingu (IntSet flies)) $tv)
   ((: $_proof
       (Inheritance Pingu (IntSet flies))
       (STV 0.50019449149775 0.9473834682549807))))

!(mm2-test-query 40 flyingRavenKb
   (: $prf (Inheritance Pingu (IntSet flies)) $tv)
   ((: $_proof
       (Inheritance Pingu (IntSet flies))
       (STV 0.50019449149775 0.9473834682549807))))
