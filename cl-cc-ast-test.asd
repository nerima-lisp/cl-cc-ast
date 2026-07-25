(asdf:defsystem "cl-cc-ast-test"
  :description "Tests for cl-cc-ast (cl-weave)."
  :version "0.1.0"
  :author "takeokunn"
  :license "MIT"
  :homepage "https://github.com/nerima-lisp/cl-cc-ast"
  :depends-on ("cl-cc-ast" "cl-weave")
  :pathname "tests"
  :serial t
  :components ((:file "package")
               (:file "test-support")
               (:file "ast-tests")
               (:file "ast-analysis-tests")
               (:file "ast-roundtrip-tests")
               (:file "closure-tests"))
  :perform (asdf:test-op (op system)
             (declare (ignore op system))
             (unless (uiop:symbol-call :cl-weave
                                       :run-all
                                       :reporter :spec
                                       :pass-with-no-tests nil)
               (error "cl-cc-ast tests failed"))))
