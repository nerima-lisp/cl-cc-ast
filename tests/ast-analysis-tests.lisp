;;;; tests/ast-analysis-tests.lisp — ast-children / ast-bound-names (cl-weave).
;;;;
;;;; The structural (ast-children) and scoping (ast-bound-names) data layers,
;;;; which are pure cl-cc-ast API.

(in-package :cl-cc-ast/test)

;;; ─────────────────────────────────────────────────────────────────────────
;;; ast-children — structural data layer
;;; ─────────────────────────────────────────────────────────────────────────

(it-sequential "ast-children: int leaf has no children"
  (expect (ast-children (make-ast-int :value 42)) :to-be-null))

(it-sequential "ast-children: var leaf has no children"
  (expect (ast-children (make-ast-var :name 'x)) :to-be-null))

(it-sequential "ast-children: hole leaf has no children"
  (expect (ast-children (make-ast-hole)) :to-be-null))

(it-sequential "ast-children: quote leaf has no children"
  (expect (ast-children (make-ast-quote :value 'hello)) :to-be-null))

(it-sequential "ast-children: function leaf has no children"
  (expect (ast-children (make-ast-function :name 'foo)) :to-be-null))

(it-sequential "ast-children: go leaf has no children"
  (expect (ast-children (make-ast-go :tag 'start)) :to-be-null))

(it-sequential "ast-children returns the correct child sub-expressions per node type"
  ;; binop: (lhs rhs)
  (let* ((lhs (make-ast-int :value 1))
         (rhs (make-ast-int :value 2))
         (node (make-ast-binop :op '+ :lhs lhs :rhs rhs))
         (children (ast-children node)))
    (expect (length children) :to-equal 2)
    (expect (first children) :to-be lhs)
    (expect (second children) :to-be rhs))
  ;; if: (cond then else)
  (let* ((c (make-ast-int :value 1))
         (th (make-ast-int :value 2))
         (el (make-ast-int :value 3))
         (node (make-ast-if :cond c :then th :else el)))
    (expect (length (ast-children node)) :to-equal 3))
  ;; progn: forms
  (let* ((f1 (make-ast-int :value 1))
         (f2 (make-ast-int :value 2))
         (node (make-ast-progn :forms (list f1 f2))))
    (expect (length (ast-children node)) :to-equal 2))
  ;; let: init-exprs + body
  (let* ((init (make-ast-int :value 1))
         (body (make-ast-var :name 'x))
         (node (make-ast-let :bindings (list (cons 'x init))
                             :body (list body)))
         (children (ast-children node)))
    (expect (length children) :to-equal 2)
    (expect (member init children :test #'eq) :to-be-truthy)
    (expect (member body children :test #'eq) :to-be-truthy))
  ;; lambda: body forms
  (let* ((body (make-ast-var :name 'x))
         (node (make-ast-lambda :params '(x) :body (list body))))
    (expect (length (ast-children node)) :to-equal 1))
  ;; setq: value expression
  (let* ((val (make-ast-int :value 42))
         (node (make-ast-setq :var 'x :value val)))
    (expect (length (ast-children node)) :to-equal 1)
    (expect (first (ast-children node)) :to-be val))
  ;; call with symbol func: args only
  (let* ((arg1 (make-ast-int :value 1))
         (arg2 (make-ast-int :value 2))
         (node (make-ast-call :func 'foo :args (list arg1 arg2))))
    (expect (length (ast-children node)) :to-equal 2))
  ;; call with AST func: func + args
  (let* ((func (make-ast-var :name 'f))
         (arg1 (make-ast-int :value 1))
         (node (make-ast-call :func func :args (list arg1))))
    (expect (length (ast-children node)) :to-equal 2)
    (expect (first (ast-children node)) :to-be func))
  ;; block: body forms
  (let* ((body (make-ast-int :value 1))
         (node (make-ast-block :name 'b :body (list body))))
    (expect (length (ast-children node)) :to-equal 1))
  ;; catch: tag + body
  (let* ((tag (make-ast-var :name 'tag))
         (body (make-ast-int :value 1))
         (node (make-ast-catch :tag tag :body (list body))))
    (expect (length (ast-children node)) :to-equal 2)
    (expect (first (ast-children node)) :to-be tag))
  ;; throw: (tag value)
  (let* ((tag (make-ast-var :name 'tag))
         (val (make-ast-int :value 42))
         (node (make-ast-throw :tag tag :value val)))
    (expect (length (ast-children node)) :to-equal 2))
  ;; the: value expression
  (let* ((val (make-ast-int :value 1))
         (node (make-ast-the :type 'fixnum :value val)))
    (expect (length (ast-children node)) :to-equal 1)
    (expect (first (ast-children node)) :to-be val))
  ;; defvar with value: one child
  (let* ((val (make-ast-int :value 0))
         (node (make-ast-defvar :name '*x* :value val)))
    (expect (length (ast-children node)) :to-equal 1))
  ;; defvar without value: no children
  (let ((node (make-ast-defvar :name '*x*)))
    (expect (ast-children node) :to-be-null)))

;;; ─────────────────────────────────────────────────────────────────────────
;;; ast-bound-names — scoping data layer
;;; ─────────────────────────────────────────────────────────────────────────

(it-sequential "ast-bound-names: let binds its variable names"
  (expect (ast-bound-names
           (make-ast-let :bindings (list (cons 'x (make-ast-int :value 1))
                                         (cons 'y (make-ast-int :value 2)))
                         :body (list (make-ast-var :name 'x))))
          :to-equal '(x y)))

(it-sequential "ast-bound-names: lambda required params"
  (expect (ast-bound-names
           (make-ast-lambda :params '(a b) :body (list (make-ast-var :name 'a))))
          :to-equal '(a b)))

(it-sequential "ast-bound-names: lambda optional params"
  (expect (ast-bound-names
           (make-ast-lambda :params '(a)
                            :optional-params '((b nil))
                            :body (list (make-ast-var :name 'a))))
          :to-equal '(a b)))

(it-sequential "ast-bound-names: lambda rest param"
  (expect (ast-bound-names
           (make-ast-lambda :params '(a)
                            :rest-param 'rest
                            :body (list (make-ast-var :name 'a))))
          :to-equal '(a rest)))

(it-sequential "ast-bound-names: defun params"
  (expect (ast-bound-names
           (make-ast-defun :name 'foo :params '(x y)
                           :body (list (make-ast-var :name 'x))))
          :to-equal '(x y)))

(it-sequential "ast-bound-names: flet binds function names"
  (expect (ast-bound-names
           (make-ast-flet :bindings (list (list 'f '(x) (make-ast-var :name 'x)))
                          :body (list (make-ast-int :value 1))))
          :to-equal '(f)))

(it-sequential "ast-bound-names: labels binds function names"
  (expect (ast-bound-names
           (make-ast-labels :bindings (list (list 'g '(x) (make-ast-var :name 'x)))
                            :body (list (make-ast-int :value 1))))
          :to-equal '(g)))

(it-sequential "ast-bound-names: multiple-value-bind binds its vars"
  (expect (ast-bound-names
           (make-ast-multiple-value-bind
            :vars '(a b c)
            :values-form (make-ast-values :forms (list (make-ast-int :value 1)))
            :body (list (make-ast-var :name 'a))))
          :to-equal '(a b c)))

(it-sequential "ast-bound-names: non-binding nodes return nil"
  (expect (ast-bound-names (make-ast-int :value 42)) :to-be-null)
  (expect (ast-bound-names (make-ast-if
                            :cond (make-ast-int :value 1)
                            :then (make-ast-int :value 2)
                            :else (make-ast-int :value 3)))
          :to-be-null))
