;;;; run-tests.lisp
;;;;
;;;; Test entry point: register this checkout with ASDF, inherit the caller's
;;;; configuration for everything else, and run the test system.
;;;;
;;;; cl-weave arrives through CL_SOURCE_REGISTRY, which flake.nix sets for
;;;; `nix flake check`, `nix run .#test` and `nix develop` alike. That is why
;;;; there is no dependency-locating machinery here any more: the old
;;;; scripts/bootstrap.lisp parsed .asd files by hand and loaded cl-weave's
;;;; sources one by one, because cl-weave used to be pulled in as a bare
;;;; source tree under CL_CC_AST_CL_WEAVE_ROOT rather than as a flake input.
;;;;
;;;; An empty suite still fails: cl-cc-ast/test's :perform passes
;;;; :pass-with-no-tests nil to cl-weave, so a run that registers zero tests
;;;; is an error rather than a pass.
;;;;
;;;; TEST-TIMEOUT-SECONDS is enforced in-process via SB-EXT:WITH-TIMEOUT, not
;;;; only by the shell `timeout` wrapper flake.nix's checks/apps run this
;;;; script under. A bare `sbcl --script run-tests.lisp` invocation outside
;;;; Nix — the "Outside Nix" path documented in README.md — has no such
;;;; wrapper, so a hang (an infinite loop reached by a future node kind, say)
;;;; would otherwise block forever instead of failing loudly.

(require :asdf)

(defconstant +test-timeout-seconds+ 100
  "Kept below flake.nix's `timeout 120` wrapper so a hang fails here, with a
named condition and a non-zero exit, rather than being killed by the shell.")

(defun script-directory ()
  (make-pathname :name nil
                 :type nil
                 :defaults (or *load-truename*
                               *compile-file-truename*
                               (error "Unable to determine the script location"))))

(defun configure-local-source-registry (root)
  (asdf:initialize-source-registry
   `(:source-registry
     (:tree ,root)
     :inherit-configuration)))

(let ((root (script-directory)))
  (configure-local-source-registry root)
  (handler-case
      (sb-ext:with-timeout +test-timeout-seconds+
        (asdf:test-system "cl-cc-ast"))
    (sb-ext:timeout ()
      (format t "~&FAIL cl-cc-ast tests: exceeded ~D second timeout~%" +test-timeout-seconds+)
      (finish-output)
      (uiop:quit 1)))
  (uiop:quit 0))
