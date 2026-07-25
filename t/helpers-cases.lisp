;;;; t/helpers-cases.lisp — shared table-test macro (cl-weave).
;;;;
;;;; CL-WEAVE's IT-EACH binds its row data literally, without evaluation — a
;;;; good fit for plain numbers, but not for the constructor calls this
;;;; project's tests need to build AST nodes. DEFINE-CASES is the shared
;;;; alternative used across the test suite: each row is an ordinary
;;;; (CALL-FORM EXPECTED-FORM) pair, evaluated when its case runs.

(in-package :cl-cc-ast/test)

(defmacro define-cases (&body cases)
  "Register one IT-SEQUENTIAL case per (CALL-FORM EXPECTED-FORM) pair in
CASES, each asserting CALL-FORM :TO-EQUAL EXPECTED-FORM. Case names are
derived from CALL-FORM's printed form, so the table reads as a plain list of
inputs and outputs instead of one hand-written IT-SEQUENTIAL per row."
  `(progn
     ,@(loop for (call-form expected-form) in cases
             collect `(it-sequential ,(format nil "~(~A~)" (write-to-string call-form :pretty nil))
                        (expect ,call-form :to-equal ,expected-form)))))
