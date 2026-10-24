;;;; cl-cc-ast.asd — the AST node types and protocol extracted from cl-cc.
;;;;
;;;; Keep both ASDF system definitions together so runtime and test metadata
;;;; are maintained in one manifest.
;;;;
;;;; The runtime ASDF system loads the :cl-cc/ast/nodes and
;;;; :cl-cc/ast/closure-analysis packages, then defines :cl-cc/ast to
;;;; re-export the existing public API.

;;; Keep this form first so direct LOAD reads the system forms in ASDF-USER.
;;; ASDF loads .asd files with *package* set to ASDF-USER, but a direct Lisp
;;; LOAD starts in the caller's current package.
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
  ;; flake.nix and the release workflow read the first :version field here.
  ;; Keep the test-system :version below in sync with this package version.
  :version "0.2.2"
  :homepage "https://github.com/nerima-lisp/cl-cc-ast"
  :bug-tracker "https://github.com/nerima-lisp/cl-cc-ast/issues"
  :source-control (:git "https://github.com/nerima-lisp/cl-cc-ast.git")
  :depends-on ()
  :pathname "src"
  :serial t
  :components ((:module "nodes"
                :serial t
                :components ((:file "package")
                             (:file "ast")
                             (:file "ast-functions")
                             (:file "ast-roundtrip")))
               (:module "closure-analysis"
                :serial t
                :depends-on ("nodes")
                :components ((:file "package")
                             (:file "closure")))
               (:file "package"))
  :in-order-to ((test-op (test-op "cl-cc-ast/test"))))

(asdf:defsystem "cl-cc-ast/test"
  :description "Test system for cl-cc-ast."
  :author "takeokunn <bararararatty@gmail.com>"
  :maintainer "takeokunn <bararararatty@gmail.com>"
  :license "MIT"
  :version "0.2.2"
  :homepage "https://github.com/nerima-lisp/cl-cc-ast"
  :bug-tracker "https://github.com/nerima-lisp/cl-cc-ast/issues"
  :source-control (:git "https://github.com/nerima-lisp/cl-cc-ast.git")
  :depends-on ("cl-cc-ast" "cl-weave")
  :pathname "t"
  :serial t
  :components ((:module "nodes"
                :serial t
                :components ((:file "package")
                             (:file "helpers-cases")
                             (:file "nodes-support")
                             (:file "ast-test")))
               (:module "closure-analysis"
                :serial t
                :components ((:file "package")
                             (:file "helpers-cases")
                             (:file "closure-test"))))
  :perform (asdf:test-op (op system)
             (declare (ignore op system))
             (unless (uiop:symbol-call :cl-weave
                                       :run-all
                                       :reporter :spec
                                       :pass-with-no-tests nil)
               (error "cl-cc-ast test suite failed"))))
