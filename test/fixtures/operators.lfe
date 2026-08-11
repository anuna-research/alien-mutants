(defmodule operators-fixture)

(defun arithmetic (a b) (+ a b))
(defun comparison (a b) (== a b))
(defun boolean (a b) (and a b))
(defun constant (value) 0)
(defun guarded
  ((value) (when (is_integer value)) value))
