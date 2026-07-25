;;;; packages/ast/src/ast-functions.lisp — AST Data Layer, Source Utilities, and Error Reporting
;;;;
;;;; Contains:
;;;;   - ast-children    — flat list of child AST sub-expressions (single source of truth)
;;;;   - ast-bound-names — variable names newly bound by a binding form
;;;;   - ast-location-string — human-readable source location
;;;;   - ast-compilation-error condition type
;;;;   - ast-error — signal a compilation error with location context
;;;;
;;;; Depends on ast.lisp (all AST struct definitions, ast-source-* accessors).
;;;; Load order: immediately after ast.lisp.

(in-package :cl-cc/ast)

;;; ─── AST Data Layer ────────────────────────────────────────────────────────
;;;
;;; ast-children    — returns child sub-expressions (flat list of ast-nodes)
;;; ast-bound-names — returns names newly bound by a binding form
;;;
;;; These functions are the SINGLE SOURCE OF TRUTH for AST structure.
;;; Traversal algorithms (find-free-variables, find-mutated-variables, etc.)
;;; should use these instead of per-node typecase.

(defun ast-children (node)
  "Return a flat list of child AST sub-expressions for NODE.
All structural knowledge about AST shapes lives here."
  (typecase node
    ;; Leaves: no children
    ((or ast-int ast-var ast-hole ast-quote ast-function ast-go) nil)
    (ast-list (ast-list-elements node))
    ;; Binary operation
    (ast-binop (list (ast-binop-lhs node) (ast-binop-rhs node)))
    ;; Conditional
    (ast-if (list (ast-if-cond node) (ast-if-then node) (ast-if-else node)))
    ;; Sequences
    (ast-progn (ast-progn-forms node))
    (ast-values (ast-values-forms node))
    ;; Single child wrappers
    (ast-print (list (ast-print-expr node)))
    (ast-setq (list (ast-setq-value node)))
    (ast-return-from (list (ast-return-from-value node)))
    (ast-the (list (ast-the-value node)))
    ;; Let: init-exprs + body
    (ast-let (append (mapcar #'cdr (ast-let-bindings node))
                     (ast-let-body node)))
    ;; Callable forms: body + default exprs
    (ast-lambda (append (ast-lambda-body node)
                        (remove nil (mapcar #'second (ast-lambda-optional-params node)))
                        (remove nil (mapcar #'second (ast-lambda-key-params node)))))
    (ast-defun (append (ast-defun-body node)
                       (remove nil (mapcar #'second (ast-defun-optional-params node)))
                       (remove nil (mapcar #'second (ast-defun-key-params node)))))
    (ast-defmethod (ast-defmethod-body node))
    (ast-defmacro (ast-defmacro-body node))
    ;; Local function bindings: all binding bodies + outer body
    (ast-local-fns (append (loop for b in (ast-local-fns-bindings node)
                                 append (cddr b))
                           (ast-local-fns-body node)))
    ;; Function call: func (if AST) + args
    (ast-call (let ((f (ast-call-func node)))
                (if (typep f 'ast-node) (cons f (ast-call-args node)) (ast-call-args node))))
    (ast-apply (cons (ast-apply-func node) (ast-apply-args node)))
    ;; Block/control flow
    (ast-block (ast-block-body node))
    (ast-tagbody (loop for entry in (ast-tagbody-tags node) append (copy-list (cdr entry))))
    (ast-catch (cons (ast-catch-tag node) (copy-list (ast-catch-body node))))
    (ast-throw (list (ast-throw-tag node) (ast-throw-value node)))
    (ast-unwind-protect (cons (ast-unwind-protected node) (copy-list (ast-unwind-cleanup node))))
    (ast-handler-case (cons (ast-handler-case-form node)
                            (loop for c in (ast-handler-case-clauses node)
                                  append (copy-list (cddr c)))))
    ;; Multiple values
    (ast-multiple-value-call (cons (ast-mv-call-func node) (copy-list (ast-mv-call-args node))))
    (ast-multiple-value-prog1 (cons (ast-mv-prog1-first node) (copy-list (ast-mv-prog1-forms node))))
    (ast-multiple-value-bind (cons (ast-mvb-values-form node) (copy-list (ast-mvb-body node))))
    ;; Defvar: optional init-form
    (ast-defvar (when (ast-defvar-value node) (list (ast-defvar-value node))))
    ;; CLOS
    (ast-defclass (append (remove nil (mapcar #'ast-slot-initform (ast-defclass-slots node)))
                          (mapcar #'cdr (ast-defclass-default-initargs node))
                          (when (ast-defclass-metaclass node)
                            (list (ast-defclass-metaclass node)))))
    (ast-defgeneric nil)
    (ast-make-instance (mapcar #'cdr (ast-make-instance-initargs node)))
    (ast-slot-value (list (ast-slot-value-object node)))
    (ast-set-slot-value (list (ast-set-slot-value-object node) (ast-set-slot-value-value node)))
    (ast-set-gethash (list (ast-set-gethash-key node)
                           (ast-set-gethash-table node)
                           (ast-set-gethash-value node)))
    (t nil)))

(defun ast-bound-names (node)
  "Return the list of variable names newly bound by NODE.
Only meaningful for binding forms (let, lambda, defun, flet, labels, mvb)."
  (typecase node
    (ast-let (mapcar #'car (ast-let-bindings node)))
    (ast-lambda (append (ast-lambda-params node)
                        (mapcar #'first (ast-lambda-optional-params node))
                        (when (ast-lambda-rest-param node)
                          (list (ast-lambda-rest-param node)))
                        (mapcar #'first (ast-lambda-key-params node))))
    (ast-defun (append (ast-defun-params node)
                       (mapcar #'first (ast-defun-optional-params node))
                       (when (ast-defun-rest-param node)
                         (list (ast-defun-rest-param node)))
                       (mapcar #'first (ast-defun-key-params node))))
    (ast-local-fns (mapcar #'first (ast-local-fns-bindings node)))
    (ast-multiple-value-bind (ast-mvb-vars node))
    (t nil)))

;;; ─── CPS Tree Search ──────────────────────────────────────────────────────
;;;
;;; AST-SEARCH-CPS walks NODE via AST-CHILDREN and drives the outcome entirely
;;; through two continuations rather than a return value: SUCCESS receives
;;; the first matching node, FAILURE is invoked with no arguments when the
;;; whole subtree is exhausted. Each recursive step builds a new FAILURE
;;; continuation that resumes the search at the next sibling, so backtracking
;;; across the tree is ordinary function composition instead of a loop with
;;; mutable state. This is the traversal primitive closure.lisp's escape
;;; analysis is built on (see %ESCAPE-MENTIONS-NODE-P).

(defun ast-search-cps (node predicate success failure)
  "Search NODE and its AST-CHILDREN descendants, depth-first, for a node
satisfying PREDICATE.

Calls (SUCCESS matching-node) on the first match. Otherwise tries each child
of NODE in turn, passing SUCCESS through unchanged and wrapping FAILURE in a
continuation that advances to the next child. Calls (FAILURE) with no
arguments once every descendant has been tried without a match."
  (if (funcall predicate node)
      (funcall success node)
      (labels ((try-children (children)
                 (if (null children)
                     (funcall failure)
                     (ast-search-cps (first children) predicate
                                     success
                                     (lambda () (try-children (rest children)))))))
        (try-children (ast-children node)))))

(defun ast-find-first (node predicate)
  "Return the first node in NODE (including NODE itself) satisfying
PREDICATE via depth-first AST-CHILDREN traversal, or NIL if none matches.

A direct-style convenience built from AST-SEARCH-CPS: the SUCCESS
continuation is #'IDENTITY (return the match as-is) and the FAILURE
continuation is a function that always returns NIL, turning the
continuation-driven search back into an ordinary return value for callers
that just want an answer rather than control over what happens next."
  (ast-search-cps node predicate #'identity (constantly nil)))

;;; ─── Source Location Utilities ───────────────────────────────────────────────

(defun ast-location-string (node)
  "Return a human-readable string of the source location for NODE."
  (let ((file (ast-source-file node))
        (line (ast-source-line node))
        (col (ast-source-column node)))
    (cond
      ((and file line col)
       (format nil "~A:~D:~D" file line col))
      ((and file line)
       (format nil "~A:~D" file line))
      (file
       (format nil "~A" file))
      (t "<unknown location>"))))

(define-condition ast-compilation-error (error)
  ((location :initarg :location :reader ast-error-location)
   (format-control :initarg :format-control :reader ast-error-format-control)
   (format-arguments :initarg :format-arguments :reader ast-error-format-arguments))
  (:report (lambda (condition stream)
             (format stream "Compilation error at ~A: ~?"
                     (ast-error-location condition)
                     (ast-error-format-control condition)
                     (ast-error-format-arguments condition)))))

(defun ast-error (node format-control &rest format-args)
  "Signal an error with source location information from NODE."
  (error 'ast-compilation-error
         :location (ast-location-string node)
         :format-control format-control
         :format-arguments format-args))
