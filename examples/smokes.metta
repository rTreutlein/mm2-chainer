!(import! &self /nexus/Dev/OpenCog/NL2PLN_Project/mm2-chainer/compiler/mm2_chainer)
!(mm2-init)

!(mm2-compileadd smokesKb
   (: friendSmokingRule
      (Implication
         (Premises (Inheritance (Product $x $y) friend) (Inheritance $x (IntSet smokes)))
         (Conclusions (Inheritance $y (IntSet smokes))))
      (STV 0.4 0.9)))

!(mm2-compileadd smokesKb
   (: smokingCancerRule
      (Implication
         (Premises (Inheritance $x (IntSet smokes)))
         (Conclusions (Inheritance $x (IntSet cancerous))))
      (STV 0.6 0.9)))

!(mm2-compileadd smokesKb (: friendAnnaBob (Inheritance (Product Anna Bob) friend) (STV 1.0 0.9)))
!(mm2-compileadd smokesKb (: friendAnnaEdward (Inheritance (Product Anna Edward) friend) (STV 1.0 0.9)))
!(mm2-compileadd smokesKb (: friendAnnaFrank (Inheritance (Product Anna Frank) friend) (STV 1.0 0.9)))
!(mm2-compileadd smokesKb (: friendEdwardFrank (Inheritance (Product Edward Frank) friend) (STV 1.0 0.9)))
!(mm2-compileadd smokesKb (: friendGaryHelen (Inheritance (Product Gary Helen) friend) (STV 1.0 0.9)))
!(mm2-compileadd smokesKb (: notFriendGaryFrank (Inheritance (Product Gary Frank) friend) (STV 0.0 0.9)))
!(mm2-compileadd smokesKb (: smokesAnna (Inheritance Anna (IntSet smokes)) (STV 1.0 0.9)))
!(mm2-compileadd smokesKb (: smokesEdward (Inheritance Edward (IntSet smokes)) (STV 1.0 0.9)))

!(mm2-test-query-proofs 20 smokesKb
   (: $prf (Inheritance Edward (IntSet cancerous)) $tv)
   ((: (mm2-proof
          ((inheritance-implication smokesEdward)
           smokingCancerRule
           (inheritance-rule-lift friendSmokingRule)
           (ctx proof 0)
           friendAnnaEdward
           smokesAnna))
       (Inheritance Edward (IntSet cancerous))
       (STV 0.4200001194564362 0.9335532708555526))))
