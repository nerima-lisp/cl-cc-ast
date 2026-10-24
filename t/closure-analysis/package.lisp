(defpackage :cl-cc/ast/closure-analysis/test
  (:use #:cl #:cl-weave #:cl-cc/ast/closure-analysis)
  (:import-from #:cl-cc/ast/nodes
                #:ast-children
                #:make-ast-apply
                #:make-ast-call
                #:make-ast-defmethod
                #:make-ast-defun
                #:make-ast-flet
                #:make-ast-function
                #:make-ast-if
                #:make-ast-int
                #:make-ast-labels
                #:make-ast-lambda
                #:make-ast-let
                #:make-ast-multiple-value-bind
                #:make-ast-progn
                #:make-ast-setq
                #:make-ast-var)
  (:shadowing-import-from #:cl-weave #:describe))
