;;;; run-coverage.lisp
;;;;
;;;; Compile cl-cc-ast under SB-COVER instrumentation, run the cl-weave test
;;;; suite, and enforce a coverage floor on src/. Driven by `checks.coverage`
;;;; in flake.nix.
;;;;
;;;; cl-weave is loaded before the SB-COVER proclaim so the framework itself
;;;; is not instrumented; only cl-cc-ast is force-recompiled underneath it.
;;;;
;;;; The gate excludes ast.lisp and package.lisp from the *threshold* (both
;;;; still appear in the HTML report). ast.lisp is ~40 DEFSTRUCT forms with no
;;;; branching logic; SB-COVER instruments each slot's default-value form as
;;;; a coverable expression, but DEFSTRUCT's macroexpansion evaluates that
;;;; form only at the ORIGINAL struct's own construction with the slot
;;;; omitted — verified empirically that calling every constructor with zero
;;;; arguments (see t/ast-analysis-test.lisp) does not move the number, and
;;;; that (optimize (debug 3)) does not either. package.lisp is a single
;;;; DEFPACKAGE form with the same one-shot-at-load-time nature. Gating on
;;;; these would make the threshold permanently unsatisfiable regardless of
;;;; test quality. The remaining logic files (ast-functions.lisp,
;;;; ast-roundtrip.lisp, closure.lisp) are held to a near-100% floor; what's
;;;; left there after closing every real gap is the same one-shot-form
;;;; artifact: IN-PACKAGE, DEFGENERIC, DEFPARAMETER, and every &OPTIONAL/&KEY
;;;; default-value form — including the #'IDENTITY defaults CLOSURE.LISP's
;;;; CPS-style traversals (FIND-MUTATED-VARIABLES, MUTATED-VARS-OF-LIST,
;;;; FIND-CAPTURED-IN-CHILDREN, %CAPTURED-IN-FORM) use so a direct-style call
;;;; with no continuation still returns a value. Verified empirically the same
;;;; way: landing those CPS conversions moved expression coverage from 99.05%
;;;; to 98.98% with no missing test case behind the drop, purely from four new
;;;; one-shot default-value forms. MINIMUM is calibrated to that ceiling, not
;;;; to a round number.

(require :asdf)

(defconstant +coverage-timeout-seconds+ 240
  "Kept below flake.nix's `timeout 300` wrapper (checks.coverage) so a hang in
the instrumented run fails here, with a named condition and a non-zero exit,
rather than being killed by the shell — see run-tests.lisp's matching note.")

(defun script-directory ()
  (make-pathname :name nil
                 :type nil
                 :defaults (or *load-truename*
                               *compile-file-truename*
                               (error "Unable to determine the script location"))))

(defun call-in-package (package-name symbol-name &rest arguments)
  (apply (symbol-function (find-symbol (string symbol-name) package-name))
         arguments))

(let* ((root (script-directory))
       (src-root (merge-pathnames "src/" root))
       (report-directory (merge-pathnames "cl-cc-ast-coverage-report/" root))
       (output-file (merge-pathnames "cl-cc-ast.coverage" root))
       ;; Only the files that carry branching logic are gated; see the header.
       (gated-files (list (merge-pathnames "src/ast-functions.lisp" root)
                          (merge-pathnames "src/ast-roundtrip.lisp" root)
                          (merge-pathnames "src/closure.lisp" root)))
       (minimum 98.9))
  (asdf:initialize-source-registry
   `(:source-registry
     (:tree ,root)
     :inherit-configuration))

  (asdf:load-system "cl-weave")

  (require :sb-cover)
  (proclaim `(optimize (,(find-symbol "STORE-COVERAGE-DATA" "SB-COVER") 3) (debug 3)))
  (asdf:load-system "cl-cc-ast" :force t)
  (asdf:load-system "cl-cc-ast/test" :force t)

  (handler-case
      (sb-ext:with-timeout +coverage-timeout-seconds+
        (unless (call-in-package
                 "CL-WEAVE" "RUN-ALL"
                 :reporter :spec
                 :pass-with-no-tests nil
                 :coverage t
                 :coverage-output output-file
                 :coverage-report-directory report-directory
                 :coverage-include-pathnames (list src-root))
          (error "cl-cc-ast test suite failed"))
        (let* ((stats (call-in-package "CL-WEAVE" "COVERAGE-STATISTICS"
                                       :include-pathnames gated-files))
               (expression-pct (* 100.0 (/ (getf stats :expression-covered)
                                           (getf stats :expression-total))))
               (branch-pct (* 100.0 (/ (getf stats :branch-covered)
                                       (getf stats :branch-total)))))
          (format t "~&Gated coverage (ast-functions.lisp, ast-roundtrip.lisp, closure.lisp): ~
                     expression ~,2F%, branch ~,2F%~%"
                  expression-pct branch-pct)
          (when (or (< expression-pct minimum) (< branch-pct minimum))
            (error "Gated coverage below ~,2F%: expression ~,2F%, branch ~,2F%"
                   minimum expression-pct branch-pct))))
    (sb-ext:timeout ()
      (format t "~&FAIL cl-cc-ast coverage: exceeded ~D second timeout~%" +coverage-timeout-seconds+)
      (finish-output)
      (uiop:quit 1))
    (error (condition)
      (format t "~&FAIL cl-cc-ast coverage: ~A~%" condition)
      (finish-output)
      (uiop:quit 1))))
