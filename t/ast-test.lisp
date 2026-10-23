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

(describe-concurrent "cl-cc-ast unit tests"

(describe "ast-location-string"
  (it-sequential "formats file:line:column"
    (expect (ast-location-string
             (make-ast-int :value 1 :source-file "foo.lisp" :source-line 10 :source-column 5))
            :to-equal "foo.lisp:10:5"))

  (it-sequential "formats file:line when column is absent"
    (expect (ast-location-string
             (make-ast-int :value 1 :source-file "foo.lisp" :source-line 3))
            :to-equal "foo.lisp:3"))

  (it-sequential "reports unknown location without metadata"
    (expect (ast-location-string (make-ast-int :value 1))
            :to-equal "<unknown location>"))

  (it-sequential "formats a bare file when line is absent"
    (expect (ast-location-string (make-ast-int :value 1 :source-file "foo.lisp"))
            :to-equal "foo.lisp")))

(describe "ast-error"
  (it-sequential "signals ast-compilation-error with location from node"
    (let ((node (make-ast-int :value 1 :source-file "t.lisp" :source-line 1))
          (signaled nil))
      (handler-case (ast-error node "test error ~A" 42)
        (ast-compilation-error () (setf signaled t)))
      (expect signaled :to-be-truthy)))

  (it-sequential "condition report formats location and message"
    (let ((node (make-ast-int :value 1 :source-file "t.lisp" :source-line 1))
          (report nil))
      (handler-case (ast-error node "bad thing: ~A" 42)
        (ast-compilation-error (condition) (setf report (princ-to-string condition))))
      (expect (search "t.lisp:1" report) :to-be-truthy)
      (expect (search "bad thing: 42" report) :to-be-truthy))))

(describe "test runner failure control"
  (it-sequential "reports a failing assertion"
    (expect nil :to-be-truthy)))

(describe "namespace / imports node metadata"
  (it-sequential "AST nodes store and update optional namespace/imports metadata"
    (let ((node (make-ast-int :value 1
                              :namespace "App\\Example"
                              :imports '("Vendor\\Library"))))
      (expect (ast-namespace node) :to-equal "App\\Example")
      (expect (ast-imports node) :to-equal '("Vendor\\Library"))
      (setf (ast-namespace node) "App\\Updated"
            (ast-imports node) '("Vendor\\Other"))
      (expect (ast-namespace node) :to-equal "App\\Updated")
      (expect (ast-imports node) :to-equal '("Vendor\\Other")))))

(describe "strict DEFUN function names"
  (it-sequential "DEFUN constructor retains ordinary symbol names"
    (dolist (name (list 'foo nil (make-symbol "LOCAL-NAME")))
      (expect (eq (ast-defun-name (make-ast-defun :name name)) name) :to-be-truthy)))

  (it-sequential "DEFUN setter retains ordinary symbol names"
    (let ((node (make-ast-defun :name 'foo))
          (name (make-symbol "REPLACEMENT")))
      (setf (ast-defun-name node) name)
      (expect (eq (ast-defun-name node) name) :to-be-truthy)
      (setf (ast-defun-name node) nil)
      (expect (null (ast-defun-name node)) :to-be-truthy)))

  (it-sequential "DEFUN constructor retains exact SETF name identity"
    (dolist (symbol (list 'foo nil (make-symbol "ACCESSOR")))
      (let* ((name (list 'cl:setf symbol))
             (node (funcall (fdefinition 'make-ast-defun) :name name)))
        (expect (eq (ast-defun-name node) name) :to-be-truthy)
        (expect (eq (car (ast-defun-name node)) 'cl:setf) :to-be-truthy)
        (expect (eq (cadr (ast-defun-name node)) symbol) :to-be-truthy))))

  (it-sequential "DEFUN setter accepts exact SETF names and returns to symbols"
    (let* ((node (make-ast-defun :name 'foo))
           (symbol (make-symbol "ACCESSOR"))
           (name (list 'cl:setf symbol)))
      (expect (eq (funcall (fdefinition '(setf ast-defun-name)) name node) name)
              :to-be-truthy)
      (expect (eq (ast-defun-name node) name) :to-be-truthy)
      (expect (eq (cadr (ast-defun-name node)) symbol) :to-be-truthy)
      (setf (ast-defun-name node) 'foo)
      (expect (eq (ast-defun-name node) 'foo) :to-be-truthy)))

  (it-sequential "DEFUN constructor and setter reject malformed or aliased names"
    (let ((node (make-ast-defun :name 'foo)))
      (dolist (name (list 42 "FOO" '(cl:setf) '(cl:setf foo bar)
                         '(cl:setf 42) '(cl:setf . foo)
                         '(cl:setf foo . bar) '(function foo)
                         (list (make-symbol "SETF") 'foo)))
        (let ((constructor-rejected nil) (setter-rejected nil))
          (handler-case (make-ast-defun :name name)
            (type-error () (setf constructor-rejected t)))
          (handler-case (setf (ast-defun-name node) name)
            (type-error () (setf setter-rejected t)))
          (expect constructor-rejected :to-be-truthy)
          (expect setter-rejected :to-be-truthy)
          (expect (eq (ast-defun-name node) 'foo) :to-be-truthy)))))))
