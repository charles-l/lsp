(cons (quote a) (quote b))
(def a 2)
(cons (quote b) a)
(cons (quote b) (quote a))
(def y (lam (x) x))
(y (quote 1))