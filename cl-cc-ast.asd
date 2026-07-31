;;;; cl-cc-ast.asd — the AST node types and protocol extracted from cl-cc.
;;;;
;;;; Both systems live in this one file. The org does not use a separate
;;;; cl-cc-ast-test.asd: a second .asd is a second place for the version and
;;;; the metadata to drift out of step with this one.
;;;;
;;;; NOTE: the Lisp package these systems define is :cl-cc/ast, not
;;;; :cl-cc-ast. GLOSSARY.md calls for cl-cc-<area> everywhere, because `/`
;;;; already means "ASDF secondary system" — cl-cc-ast/test right below is
;;;; exactly that. Renaming the package breaks cl-cc-type and cl-cc, so it is
;;;; deliberately left for its own change.

;;; This form comes first, before any defsystem. ASDF binds *package* to
;;; ASDF-USER only for a file it loads itself; read any other way -- a REPL
;;; `load`, an editor evaluating the buffer, flake.nix parsing :version -- the
;;; file is read in whatever package happens to be current. Saying it makes the
;;; file self-contained.
(in-package #:asdf-user)

(asdf:defsystem "cl-cc-ast"
  :description "cl-cc AST node types and protocol (ast-children, ast-bound-names)"
  :long-description "The dependency-free leaf of the cl-cc compiler: AST node
structures and their accessors, the ast-children / ast-bound-names data
protocol, closure and free-variable analysis helpers, and S-expression
round-trip (unparse) support. Downstream systems depend on the public API
only."
  :author "takeokunn <bararararatty@gmail.com>"
  :maintainer "takeokunn <bararararatty@gmail.com>"
  :license "MIT"
  ;; Single source of truth for the version: flake.nix reads this form and
  ;; release.yml refuses to publish a tag that disagrees with it.
  :version "0.2.0"
  :homepage "https://github.com/nerima-lisp/cl-cc-ast"
  :bug-tracker "https://github.com/nerima-lisp/cl-cc-ast/issues"
  :source-control (:git "https://github.com/nerima-lisp/cl-cc-ast.git")
  :depends-on ()
  :pathname "src"
  :serial t
  :components ((:file "package")
               (:file "ast")
               (:file "ast-functions")
               (:file "closure")
               (:file "ast-roundtrip"))
  :in-order-to ((test-op (test-op "cl-cc-ast/test"))))

(asdf:defsystem "cl-cc-ast/test"
  :description "Test system for cl-cc-ast."
  :author "takeokunn <bararararatty@gmail.com>"
  :maintainer "takeokunn <bararararatty@gmail.com>"
  :license "MIT"
  :version "0.2.0"
  :homepage "https://github.com/nerima-lisp/cl-cc-ast"
  :bug-tracker "https://github.com/nerima-lisp/cl-cc-ast/issues"
  :source-control (:git "https://github.com/nerima-lisp/cl-cc-ast.git")
  :depends-on ("cl-cc-ast" "cl-weave")
  :pathname "t"
  :serial t
  :components ((:file "package")
               (:file "helpers-cases")
               (:file "ast-test")
               (:file "ast-analysis-test")
               (:file "ast-roundtrip-test")
               (:file "closure-test"))
  :perform (asdf:test-op (op system)
             (declare (ignore op system))
             (unless (uiop:symbol-call :cl-weave
                                       :run-all
                                       :reporter :spec
                                       :pass-with-no-tests nil)
               (error "cl-cc-ast test suite failed"))))
