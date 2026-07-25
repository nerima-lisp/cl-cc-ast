;;;; run-coverage.lisp
;;;;
;;;; Compile :cl-cc-ast under SB-COVER instrumentation, run the cl-weave test
;;;; suite, and enforce coverage on src/. Coverage requires real COMPILE-FILE
;;;; (unlike bootstrap.lisp's interpreted test loader), so this script drives
;;;; ASDF directly instead of reusing load-project-tests.
;;;;
;;;; The gate excludes ast.lisp and package.lisp from the *threshold* (both
;;;; still appear in the HTML report). ast.lisp is ~40 DEFSTRUCT forms with no
;;;; branching logic; SB-COVER instruments each slot's default-value form as
;;;; a coverable expression, but DEFSTRUCT's macroexpansion evaluates that
;;;; form only at the ORIGINAL struct's own construction with the slot
;;;; omitted — verified empirically that calling every constructor with zero
;;;; arguments (see ast-analysis-tests.lisp) does not move the number, and
;;;; that (optimize (debug 3)) does not either. package.lisp is a single
;;;; DEFPACKAGE form with the same one-shot-at-load-time nature. Gating on
;;;; these would make the threshold permanently unsatisfiable regardless of
;;;; test quality. The remaining logic files (ast-functions.lisp,
;;;; ast-roundtrip.lisp, closure.lisp) are held to a near-100% floor; what's
;;;; left there after closing every real gap is the same one-shot-form
;;;; artifact (IN-PACKAGE, DEFGENERIC, DEFPARAMETER, and &key NIL defaults).

(eval-when (:compile-toplevel :load-toplevel :execute)
  (load (merge-pathnames "bootstrap.lisp"
                         (make-pathname :name nil
                                        :type nil
                                        :version nil
                                        :defaults (or *load-pathname*
                                                      *compile-file-pathname*)))))

(let* ((project-root (current-project-root))
       (src-root (uiop:ensure-directory-pathname (project-file project-root "src/")))
       (report-directory (project-file project-root "cl-cc-ast-coverage-report/"))
       (output-file (project-file project-root "cl-cc-ast.coverage"))
       (gated-files (list (project-file project-root "src/ast-functions.lisp")
                          (project-file project-root "src/ast-roundtrip.lisp")
                          (project-file project-root "src/closure.lisp"))))
  (require :asdf)
  ;; cl-weave is resolved by path (CL_CC_AST_CL_WEAVE_ROOT), not the ASDF
  ;; registry, so its sources load directly rather than through
  ;; asdf:load-system — mirrors load-project-tests in this same file.
  (load-project-asd-definitions project-root)
  (load-test-dependency-sources project-root)

  (require :sb-cover)
  (proclaim `(optimize (,(find-symbol "STORE-COVERAGE-DATA" "SB-COVER") 3) (debug 3)))
  (asdf:load-system :cl-cc-ast :force t)
  (load-system-source-files (project-file project-root "cl-cc-ast-test.asd") "cl-cc-ast-test")

  (handler-case
      (progn
        (unless (package-symbol-call
                 "CL-WEAVE" "RUN-ALL"
                 :reporter :spec
                 :pass-with-no-tests nil
                 :coverage t
                 :coverage-output output-file
                 :coverage-report-directory report-directory
                 :coverage-include-pathnames (list src-root))
          (error "cl-cc-ast test suite failed"))
        (let* ((stats (package-symbol-call "CL-WEAVE" "COVERAGE-STATISTICS"
                                           :include-pathnames gated-files))
               (expression-pct (* 100.0 (/ (getf stats :expression-covered)
                                           (getf stats :expression-total))))
               (branch-pct (* 100.0 (/ (getf stats :branch-covered)
                                       (getf stats :branch-total))))
               (minimum 99.0))
          (format t "~&Gated coverage (ast-functions.lisp, ast-roundtrip.lisp, closure.lisp): ~
                     expression ~,2F%, branch ~,2F%~%"
                  expression-pct branch-pct)
          (when (or (< expression-pct minimum) (< branch-pct minimum))
            (error "Gated coverage below ~,2F%: expression ~,2F%, branch ~,2F%"
                   minimum expression-pct branch-pct))))
    (error (condition)
      (format t "~&FAIL cl-cc-ast coverage: ~A~%" condition)
      (finish-output)
      (uiop:quit 1))))
