`(quoted (+ a b))
(defmodule report-with-quasiquote
  (export (add 2)))
(defun add (a b) (+ a b))
