;;;; t/package.lisp — test package for cl-cc-ast (cl-weave based).

(defpackage :cl-cc-ast/test
  (:use :cl :cl-cc/ast :cl-weave)
  (:shadowing-import-from :cl-weave #:describe))
