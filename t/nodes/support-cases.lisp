(in-package :cl-cc/ast/nodes/test)
(defmacro define-cases (&body cases)
  "Register one IT-SEQUENTIAL case per (CALL-FORM EXPECTED-FORM) pair in
CASES, each asserting CALL-FORM :TO-EQUAL EXPECTED-FORM. Case names are
derived from CALL-FORM's printed form, so the table reads as a plain list of
inputs and outputs instead of one hand-written IT-SEQUENTIAL per row."
  `(progn
     ,@(loop for (call-form expected-form) in cases
             collect `(it-sequential ,(format nil "~(~A~)" (write-to-string call-form :pretty nil))
                        (expect ,call-form :to-equal ,expected-form)))))
