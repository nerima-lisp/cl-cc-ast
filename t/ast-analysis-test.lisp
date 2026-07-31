;;;; t/ast-analysis-test.lisp — ast-children / ast-bound-names (cl-weave).
;;;;
;;;; The structural (ast-children) and scoping (ast-bound-names) data layers,
;;;; which are pure cl-cc-ast API.

(in-package :cl-cc-ast/test)

(defparameter *all-ast-node-constructors*
  (list #'make-ast-node #'make-ast-callable #'make-ast-local-fns
        #'make-ast-int #'make-ast-var #'make-ast-hole #'make-ast-binop #'make-ast-if
        #'make-ast-progn #'make-ast-print #'make-ast-let
        #'make-ast-lambda #'make-ast-function #'make-ast-flet #'make-ast-labels
        #'make-ast-defun #'make-ast-defvar #'make-ast-defmacro
        #'make-ast-block #'make-ast-return-from #'make-ast-tagbody #'make-ast-go
        #'make-ast-setq
        #'make-ast-multiple-value-call #'make-ast-multiple-value-prog1 #'make-ast-values
        #'make-ast-multiple-value-bind #'make-ast-apply
        #'make-ast-catch #'make-ast-throw #'make-ast-unwind-protect #'make-ast-handler-case
        #'make-ast-call #'make-ast-quote #'make-ast-list #'make-ast-the
        #'make-ast-slot-def #'make-ast-defclass #'make-ast-defgeneric #'make-ast-defmethod
        #'make-ast-make-instance #'make-ast-slot-value #'make-ast-set-slot-value
        #'make-ast-set-gethash)
  "Every constructor exported by :cl-cc/ast, in package.lisp export order.")

(describe-concurrent "ast-children / ast-bound-names / cps traversal"

(describe "struct construction"
  (it-sequential "every AST node struct constructs from its declared slot defaults"
    (dolist (constructor *all-ast-node-constructors*)
      (expect (typep (funcall constructor) 'ast-node) :to-be-truthy))))

(describe "ast-children — structural data layer"
  (it-sequential "int leaf has no children"
    (expect (ast-children (make-ast-int :value 42)) :to-be-null))

  (it-sequential "var leaf has no children"
    (expect (ast-children (make-ast-var :name 'x)) :to-be-null))

  (it-sequential "hole leaf has no children"
    (expect (ast-children (make-ast-hole)) :to-be-null))

  (it-sequential "quote leaf has no children"
    (expect (ast-children (make-ast-quote :value 'hello)) :to-be-null))

  (it-sequential "function leaf has no children"
    (expect (ast-children (make-ast-function :name 'foo)) :to-be-null))

  (it-sequential "go leaf has no children"
    (expect (ast-children (make-ast-go :tag 'start)) :to-be-null))

  (it-sequential "binop returns lhs and rhs in order"
    (let* ((lhs (make-ast-int :value 1))
           (rhs (make-ast-int :value 2))
           (node (make-ast-binop :op '+ :lhs lhs :rhs rhs))
           (children (ast-children node)))
      (expect (length children) :to-equal 2)
      (expect (first children) :to-be lhs)
      (expect (second children) :to-be rhs)))

  (it-sequential "if returns cond, then, and else"
    (let* ((c (make-ast-int :value 1))
           (th (make-ast-int :value 2))
           (el (make-ast-int :value 3))
           (node (make-ast-if :cond c :then th :else el)))
      (expect (length (ast-children node)) :to-equal 3)))

  (it-sequential "progn returns its forms"
    (let* ((f1 (make-ast-int :value 1))
           (f2 (make-ast-int :value 2))
           (node (make-ast-progn :forms (list f1 f2))))
      (expect (length (ast-children node)) :to-equal 2)))

  (it-sequential "let returns binding init-exprs and body"
    (let* ((init (make-ast-int :value 1))
           (body (make-ast-var :name 'x))
           (node (make-ast-let :bindings (list (cons 'x init))
                               :body (list body)))
           (children (ast-children node)))
      (expect (length children) :to-equal 2)
      (expect (member init children :test #'eq) :to-be-truthy)
      (expect (member body children :test #'eq) :to-be-truthy)))

  (it-sequential "lambda returns its body forms"
    (let* ((body (make-ast-var :name 'x))
           (node (make-ast-lambda :params '(x) :body (list body))))
      (expect (length (ast-children node)) :to-equal 1)))

  (it-sequential "setq returns its value expression"
    (let* ((val (make-ast-int :value 42))
           (node (make-ast-setq :var 'x :value val)))
      (expect (length (ast-children node)) :to-equal 1)
      (expect (first (ast-children node)) :to-be val)))

  (it-sequential "call with a symbol func returns args only"
    (let* ((arg1 (make-ast-int :value 1))
           (arg2 (make-ast-int :value 2))
           (node (make-ast-call :func 'foo :args (list arg1 arg2))))
      (expect (length (ast-children node)) :to-equal 2)))

  (it-sequential "call with an AST func returns func and args"
    (let* ((func (make-ast-var :name 'f))
           (arg1 (make-ast-int :value 1))
           (node (make-ast-call :func func :args (list arg1))))
      (expect (length (ast-children node)) :to-equal 2)
      (expect (first (ast-children node)) :to-be func)))

  (it-sequential "block returns its body forms"
    (let* ((body (make-ast-int :value 1))
           (node (make-ast-block :name 'b :body (list body))))
      (expect (length (ast-children node)) :to-equal 1)))

  (it-sequential "catch returns tag and body"
    (let* ((tag (make-ast-var :name 'tag))
           (body (make-ast-int :value 1))
           (node (make-ast-catch :tag tag :body (list body))))
      (expect (length (ast-children node)) :to-equal 2)
      (expect (first (ast-children node)) :to-be tag)))

  (it-sequential "throw returns tag and value"
    (let* ((tag (make-ast-var :name 'tag))
           (val (make-ast-int :value 42))
           (node (make-ast-throw :tag tag :value val)))
      (expect (length (ast-children node)) :to-equal 2)))

  (it-sequential "the returns its value expression"
    (let* ((val (make-ast-int :value 1))
           (node (make-ast-the :type 'fixnum :value val)))
      (expect (length (ast-children node)) :to-equal 1)
      (expect (first (ast-children node)) :to-be val)))

  (it-sequential "defvar with a value has one child"
    (let* ((val (make-ast-int :value 0))
           (node (make-ast-defvar :name '*x* :value val)))
      (expect (length (ast-children node)) :to-equal 1)))

  (it-sequential "defvar without a value has no children"
    (let ((node (make-ast-defvar :name '*x*)))
      (expect (ast-children node) :to-be-null)))

  (it-sequential "list returns its elements"
    (let* ((el (make-ast-int :value 1))
           (node (make-ast-list :elements (list el))))
      (expect (ast-children node) :to-equal (list el))))

  (it-sequential "values returns its forms"
    (let* ((f (make-ast-int :value 1))
           (node (make-ast-values :forms (list f))))
      (expect (ast-children node) :to-equal (list f))))

  (it-sequential "print returns its expr"
    (let* ((expr (make-ast-int :value 1))
           (node (make-ast-print :expr expr)))
      (expect (ast-children node) :to-equal (list expr))))

  (it-sequential "return-from returns its value"
    (let* ((val (make-ast-int :value 1))
           (node (make-ast-return-from :name 'b :value val)))
      (expect (ast-children node) :to-equal (list val))))

  (it-sequential "defun returns body plus optional/key default exprs"
    (let* ((body (make-ast-var :name 'a))
           (opt-default (make-ast-int :value 1))
           (key-default (make-ast-int :value 2))
           (node (make-ast-defun :name 'foo :params '(a)
                                 :optional-params (list (list 'b opt-default nil))
                                 :key-params (list (list 'c key-default nil))
                                 :body (list body))))
      (expect (ast-children node) :to-equal (list body opt-default key-default))))

  (it-sequential "defmethod returns its body"
    (let* ((body (make-ast-int :value 1))
           (node (make-ast-defmethod :name 'foo :params '(x) :body (list body))))
      (expect (ast-children node) :to-equal (list body))))

  (it-sequential "defmacro returns its body as raw sexps, not descended into"
    (let ((node (make-ast-defmacro :name 'my-macro :lambda-list '(a) :body '((list a)))))
      (expect (ast-children node) :to-equal '((list a)))))

  (it-sequential "flet returns every binding body plus the outer body"
    (let* ((binding-body (make-ast-var :name 'x))
           (outer-body (make-ast-int :value 1))
           (node (make-ast-flet :bindings (list (list 'f '(x) binding-body))
                                :body (list outer-body))))
      (expect (ast-children node) :to-equal (list binding-body outer-body))))

  (it-sequential "apply returns func and args"
    (let* ((func (make-ast-function :name '+))
           (arg (make-ast-int :value 1))
           (node (make-ast-apply :func func :args (list arg))))
      (expect (ast-children node) :to-equal (list func arg))))

  (it-sequential "tagbody returns forms across every tag"
    (let* ((form (make-ast-int :value 1))
           (node (make-ast-tagbody :tags (list (list 'start form) (list 'end)))))
      (expect (ast-children node) :to-equal (list form))))

  (it-sequential "unwind-protect returns the protected form and cleanup forms"
    (let* ((protected (make-ast-int :value 1))
           (cleanup (make-ast-int :value 2))
           (node (make-ast-unwind-protect :protected protected :cleanup (list cleanup))))
      (expect (ast-children node) :to-equal (list protected cleanup))))

  (it-sequential "handler-case returns the form and every clause body"
    (let* ((form (make-ast-int :value 1))
           (clause-body (make-ast-int :value 2))
           (node (make-ast-handler-case
                  :form form
                  :clauses (list (list 'error 'e clause-body)))))
      (expect (ast-children node) :to-equal (list form clause-body))))

  (it-sequential "multiple-value-call returns func and args"
    (let* ((func (make-ast-function :name '+))
           (arg (make-ast-int :value 1))
           (node (make-ast-multiple-value-call :func func :args (list arg))))
      (expect (ast-children node) :to-equal (list func arg))))

  (it-sequential "multiple-value-prog1 returns first and forms"
    (let* ((first (make-ast-int :value 1))
           (form (make-ast-int :value 2))
           (node (make-ast-multiple-value-prog1 :first first :forms (list form))))
      (expect (ast-children node) :to-equal (list first form))))

  (it-sequential "multiple-value-bind returns the values-form and body"
    (let* ((values-form (make-ast-var :name 'source))
           (body (make-ast-var :name 'a))
           (node (make-ast-multiple-value-bind :vars '(a) :values-form values-form
                                               :body (list body))))
      (expect (ast-children node) :to-equal (list values-form body))))

  (it-sequential "defclass returns slot initforms, default-initarg values, and metaclass"
    (let* ((initform (make-ast-int :value 0))
           (initarg-value (make-ast-int :value 1))
           (metaclass (make-ast-quote :value 'standard-class))
           (node (make-ast-defclass
                  :name 'widget :superclasses '(object)
                  :slots (list (make-ast-slot-def :name 'size :initform initform))
                  :default-initargs (list (cons :size initarg-value))
                  :metaclass metaclass)))
      (expect (ast-children node) :to-equal (list initform initarg-value metaclass))))

  (it-sequential "defclass without a metaclass omits it from the children"
    (let* ((initform (make-ast-int :value 0))
           (node (make-ast-defclass
                  :name 'widget :superclasses '(object)
                  :slots (list (make-ast-slot-def :name 'size :initform initform)))))
      (expect (ast-children node) :to-equal (list initform))))

  (it-sequential "defgeneric has no children"
    (expect (ast-children (make-ast-defgeneric :name 'area :params '(shape))) :to-be-null))

  (it-sequential "make-instance returns initarg values only"
    (let* ((val (make-ast-int :value 1))
           (node (make-ast-make-instance :class (make-ast-quote :value 'widget)
                                         :initargs (list (cons :size val)))))
      (expect (ast-children node) :to-equal (list val))))

  (it-sequential "slot-value returns its object"
    (let* ((obj (make-ast-var :name 'obj))
           (node (make-ast-slot-value :object obj :slot 'size)))
      (expect (ast-children node) :to-equal (list obj))))

  (it-sequential "set-slot-value returns object and value"
    (let* ((obj (make-ast-var :name 'obj))
           (val (make-ast-int :value 1))
           (node (make-ast-set-slot-value :object obj :slot 'size :value val)))
      (expect (ast-children node) :to-equal (list obj val))))

  (it-sequential "set-gethash returns key, table, and value"
    (let* ((key (make-ast-quote :value :k))
           (table (make-ast-var :name 'h))
           (val (make-ast-int :value 1))
           (node (make-ast-set-gethash :key key :table table :value val)))
      (expect (ast-children node) :to-equal (list key table val))))

  (it-sequential "an unrecognized object has no children"
    (expect (ast-children 42) :to-be-null)))

(describe "ast-bound-names — scoping data layer"
  (define-cases
    ((ast-bound-names
      (make-ast-let :bindings (list (cons 'x (make-ast-int :value 1))
                                    (cons 'y (make-ast-int :value 2)))
                    :body (list (make-ast-var :name 'x))))
     '(x y))
    ((ast-bound-names (make-ast-lambda :params '(a b) :body (list (make-ast-var :name 'a))))
     '(a b))
    ((ast-bound-names
      (make-ast-lambda :params '(a)
                       :optional-params '((b nil))
                       :body (list (make-ast-var :name 'a))))
     '(a b))
    ((ast-bound-names
      (make-ast-lambda :params '(a)
                       :rest-param 'rest
                       :body (list (make-ast-var :name 'a))))
     '(a rest))
    ((ast-bound-names
      (make-ast-defun :name 'foo :params '(x y)
                      :body (list (make-ast-var :name 'x))))
     '(x y))
    ((ast-bound-names
      (make-ast-defun :name 'foo :params '(x) :rest-param 'rest
                      :body (list (make-ast-var :name 'x))))
     '(x rest))
    ((ast-bound-names
      (make-ast-flet :bindings (list (list 'f '(x) (make-ast-var :name 'x)))
                     :body (list (make-ast-int :value 1))))
     '(f))
    ((ast-bound-names
      (make-ast-labels :bindings (list (list 'g '(x) (make-ast-var :name 'x)))
                       :body (list (make-ast-int :value 1))))
     '(g))
    ((ast-bound-names
      (make-ast-multiple-value-bind
       :vars '(a b c)
       :values-form (make-ast-values :forms (list (make-ast-int :value 1)))
       :body (list (make-ast-var :name 'a))))
     '(a b c))
    ((ast-bound-names (make-ast-int :value 42))
     nil)
    ((ast-bound-names (make-ast-if :cond (make-ast-int :value 1)
                                   :then (make-ast-int :value 2)
                                   :else (make-ast-int :value 3)))
     nil)))

(describe "ast-search-cps — CPS tree search"
  (it-sequential "drives its result through a continuation"
    ;; Exercises cl-weave's canonical CPS testing idiom: bind (result
    ;; continuation-name called-p) around a form that receives the
    ;; continuation, then assert on both the call and its argument.
    (let* ((target (make-ast-var :name 'needle))
           (root (make-ast-if :cond (make-ast-int :value 1)
                              :then target
                              :else (make-ast-int :value 0))))
      (with-continuation-result (found next calledp)
          (ast-search-cps root (lambda (n) (eq n target)) #'next (lambda () nil))
        (expect calledp :to-be-truthy)
        (expect found :to-be target))))

  (it-sequential "matches the root node itself without descending"
    (let ((root (make-ast-var :name 'x)))
      (expect (ast-search-cps root
                              (lambda (n) (typep n 'ast-var))
                              (lambda (n) n)
                              (lambda () :not-found))
              :to-be root)))

  (it-sequential "calls FAILURE once every descendant has been tried"
    (expect (ast-search-cps (make-ast-if :cond (make-ast-int :value 1)
                                         :then (make-ast-int :value 2)
                                         :else (make-ast-int :value 3))
                            (lambda (n) (typep n 'ast-var))
                            (lambda (n) (declare (ignore n)) :found)
                            (lambda () :not-found))
            :to-equal :not-found))

  (it-sequential "finds a match nested several levels deep"
    (let ((target (make-ast-var :name 'deep)))
      (expect (ast-search-cps
               (make-ast-progn
                :forms (list (make-ast-int :value 1)
                            (make-ast-if :cond (make-ast-int :value 0)
                                        :then (make-ast-progn :forms (list target))
                                        :else (make-ast-int :value 0))))
               (lambda (n) (typep n 'ast-var))
               (lambda (n) n)
               (lambda () nil))
              :to-be target)))

  (it-property "finds the leaf a generated target value names, via CPS backtracking across generated siblings"
      ((values (gen-list (gen-integer :min -1000 :max 1000) :min-length 1 :max-length 12)))
    ;; The target is the first generated leaf, so this holds regardless of
    ;; duplicate values elsewhere in the list: AST-SEARCH-CPS visits
    ;; AST-PROGN's forms left to right, and the first leaf is always the
    ;; first match its own value could produce.
    (let* ((leaves (mapcar (lambda (v) (make-ast-int :value v)) values))
           (root (make-ast-progn :forms leaves))
           (target-leaf (first leaves))
           (target-value (ast-int-value target-leaf)))
      (expect (ast-search-cps root
                              (lambda (n) (and (ast-int-p n) (= (ast-int-value n) target-value)))
                              #'identity
                              (constantly nil))
              :to-be target-leaf))))

(describe "ast-find-first — direct-style convenience over ast-search-cps"
  (it-sequential "returns the first matching node"
    (let ((target (make-ast-var :name 'needle)))
      (expect (ast-find-first
               (make-ast-if :cond (make-ast-int :value 1) :then target :else (make-ast-int :value 0))
               (lambda (n) (typep n 'ast-var)))
              :to-be target)))

  (it-sequential "returns nil when nothing matches"
    (expect (ast-find-first (make-ast-int :value 1) (lambda (n) (typep n 'ast-var)))
            :to-be-null))))
