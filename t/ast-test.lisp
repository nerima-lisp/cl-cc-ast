;;;; t/ast-test.lisp — cl-cc-ast unit tests (cl-weave).
;;;;
;;;; Covers cl-cc-ast's own public API: source-location formatting, the
;;;; ast-error condition, and optional namespace/imports node metadata.
;;;;
;;;; NOTE: the AST <-> sexp round-trip tests that previously lived here depend
;;;; on lower-sexp-to-ast, which belongs to cl-cc-parse (not cl-cc-ast). They
;;;; move to cl-cc-parse's suite when that package is extracted; testing them
;;;; here would require a parse dependency and no longer be a unit of cl-cc-ast.

(in-package :cl-cc-ast/test)

;;; ─────────────────────────────────────────────────────────────────────────
;;; ast-location-string
;;; ─────────────────────────────────────────────────────────────────────────

(it-sequential "ast-location-string formats file:line:column"
  (expect (ast-location-string
           (make-ast-int :value 1 :source-file "foo.lisp" :source-line 10 :source-column 5))
          :to-equal "foo.lisp:10:5"))

(it-sequential "ast-location-string formats file:line when column is absent"
  (expect (ast-location-string
           (make-ast-int :value 1 :source-file "foo.lisp" :source-line 3))
          :to-equal "foo.lisp:3"))

(it-sequential "ast-location-string reports unknown location without metadata"
  (expect (ast-location-string (make-ast-int :value 1))
          :to-equal "<unknown location>"))

(it-sequential "ast-location-string formats a bare file when line is absent"
  (expect (ast-location-string (make-ast-int :value 1 :source-file "foo.lisp"))
          :to-equal "foo.lisp"))

;;; ─────────────────────────────────────────────────────────────────────────
;;; ast-error
;;; ─────────────────────────────────────────────────────────────────────────

(it-sequential "ast-error signals ast-compilation-error with location from node"
  (let ((node (make-ast-int :value 1 :source-file "t.lisp" :source-line 1))
        (signaled nil))
    (handler-case (ast-error node "test error ~A" 42)
      (ast-compilation-error () (setf signaled t)))
    (expect signaled :to-be-truthy)))

(it-sequential "ast-error's condition report formats location and message"
  (let ((node (make-ast-int :value 1 :source-file "t.lisp" :source-line 1))
        (report nil))
    (handler-case (ast-error node "bad thing: ~A" 42)
      (ast-compilation-error (condition) (setf report (princ-to-string condition))))
    (expect (search "t.lisp:1" report) :to-be-truthy)
    (expect (search "bad thing: 42" report) :to-be-truthy)))

;;; ─────────────────────────────────────────────────────────────────────────
;;; namespace / imports node metadata
;;; ─────────────────────────────────────────────────────────────────────────

(it-sequential "AST nodes store and update optional namespace/imports metadata"
  (let ((node (make-ast-int :value 1
                            :namespace "App\\Example"
                            :imports '("Vendor\\Library"))))
    (expect (ast-namespace node) :to-equal "App\\Example")
    (expect (ast-imports node) :to-equal '("Vendor\\Library"))
    (setf (ast-namespace node) "App\\Updated"
          (ast-imports node) '("Vendor\\Other"))
    (expect (ast-namespace node) :to-equal "App\\Updated")
    (expect (ast-imports node) :to-equal '("Vendor\\Other"))))
