(in-package :cl-cc/ast/nodes/test)

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

(describe "namespace / imports node metadata"
  (it-sequential "AST metadata and facade symbol identity remain stable"
    (let ((node (make-ast-int :value 1
                              :namespace "App\\Example"
                              :imports '("Vendor\\Library"))))
      (expect (ast-namespace node) :to-equal "App\\Example")
      (expect (ast-imports node) :to-equal '("Vendor\\Library"))
      (setf (ast-namespace node) "App\\Updated"
            (ast-imports node) '("Vendor\\Other"))
      (expect (ast-namespace node) :to-equal "App\\Updated")
      (expect (ast-imports node) :to-equal '("Vendor\\Other"))
      (progn
        (%assert-facade-export-surface)
        (let ((facade-package (find-package "CL-CC/AST"))
              (feature-package (find-package "CL-CC/AST/CLOSURE-ANALYSIS")))
          (dolist (name '("%ESCAPE-ADD-KIND"
                          "%ESCAPE-MERGE-KINDS"
                          "%COUNT-AST-CALLS"
                          "%ESCAPE-MENTIONS-NODE-P"
                          "%ESCAPE-MENTIONS-FORMS-P"
                          "%ESCAPE-CLASSIFY-CHILDREN"
                          "%ESCAPE-CAPTURE-KINDS"
                          "%ESCAPE-CLASSIFY"))
            (multiple-value-bind (facade-symbol facade-status)
                (find-symbol name facade-package)
              (multiple-value-bind (feature-symbol feature-status)
                  (find-symbol name feature-package)
                (expect facade-status :to-be :internal)
                (expect feature-status :to-be :internal)
                (expect (eq facade-symbol feature-symbol) :to-be-truthy)
                (expect (eq (symbol-package facade-symbol) feature-package)
                        :to-be-truthy)))))))))

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
          (expect (eq (ast-defun-name node) 'foo) :to-be-truthy)))))) (describe "struct construction"
  (it-sequential "every AST node struct constructs from its declared slot defaults"
    (dolist (constructor *all-ast-node-constructors*)
      (expect (typep (funcall constructor) 'ast-node) :to-be-truthy)))) (describe "ast-children — structural data layer"
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
      (let ((children (ast-children node)))
        (expect (length children) :to-equal 3)
        (expect (every #'eq children (list c th el)) :to-be-truthy))))

  (it-sequential "progn returns its forms"
    (let* ((f1 (make-ast-int :value 1))
           (f2 (make-ast-int :value 2))
           (node (make-ast-progn :forms (list f1 f2))))
      (let ((children (ast-children node)))
        (expect (length children) :to-equal 2)
        (expect (every #'eq children (list f1 f2)) :to-be-truthy))))

  (it-sequential "let returns binding init-exprs and body"
    (let* ((init (make-ast-int :value 1))
           (body (make-ast-var :name 'x))
           (node (make-ast-let :bindings (list (cons 'x init))
                               :body (list body)))
           (children (ast-children node)))
      (expect (length children) :to-equal 2)
      (expect (every #'eq children (list init body)) :to-be-truthy)))

  (it-sequential "lambda returns its body forms"
    (let* ((body (make-ast-var :name 'x))
           (node (make-ast-lambda :params '(x) :body (list body))))
      (let ((children (ast-children node)))
        (expect (length children) :to-equal 1)
        (expect (every #'eq children (list body)) :to-be-truthy))))

  (it-sequential "setq returns its value expression"
    (let* ((val (make-ast-int :value 42))
           (node (make-ast-setq :var 'x :value val)))
      (expect (length (ast-children node)) :to-equal 1)
      (expect (first (ast-children node)) :to-be val)))

  (it-sequential "call with a symbol func returns args only"
    (let* ((arg1 (make-ast-int :value 1))
           (arg2 (make-ast-int :value 2))
           (node (make-ast-call :func 'foo :args (list arg1 arg2))))
      (let ((children (ast-children node)))
        (expect (length children) :to-equal 2)
        (expect (every #'eq children (list arg1 arg2)) :to-be-truthy))))

  (it-sequential "call with an AST func returns func and args"
    (let* ((func (make-ast-var :name 'f))
           (arg1 (make-ast-int :value 1))
           (node (make-ast-call :func func :args (list arg1)))
           (children (ast-children node)))
      (expect (length children) :to-equal 2)
      (expect (every #'eq children (list func arg1)) :to-be-truthy)))

  (it-sequential "block returns its body forms"
    (let* ((body (make-ast-int :value 1))
           (node (make-ast-block :name 'b :body (list body))))
      (let ((children (ast-children node)))
        (expect (length children) :to-equal 1)
        (expect (every #'eq children (list body)) :to-be-truthy))))

  (it-sequential "catch returns tag and body"
    (let* ((tag (make-ast-var :name 'tag))
           (body (make-ast-int :value 1))
           (node (make-ast-catch :tag tag :body (list body)))
           (children (ast-children node)))
      (expect (length children) :to-equal 2)
      (expect (every #'eq children (list tag body)) :to-be-truthy)))

  (it-sequential "throw returns tag and value"
    (let* ((tag (make-ast-var :name 'tag))
           (val (make-ast-int :value 42))
           (node (make-ast-throw :tag tag :value val)))
      (let ((children (ast-children node)))
        (expect (length children) :to-equal 2)
        (expect (every #'eq children (list tag val)) :to-be-truthy))))

  (it-sequential "the returns its value expression"
    (let* ((val (make-ast-int :value 1))
           (node (make-ast-the :type 'fixnum :value val)))
      (expect (length (ast-children node)) :to-equal 1)
      (expect (first (ast-children node)) :to-be val)))

  (it-sequential "defvar with a value has one child"
    (let* ((val (make-ast-int :value 0))
           (node (make-ast-defvar :name '*x* :value val)))
      (let ((children (ast-children node)))
        (expect (length children) :to-equal 1)
        (expect (every #'eq children (list val)) :to-be-truthy))))

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
    (expect (ast-children 42) :to-be-null))) (describe "ast-bound-names — scoping data layer"
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
     nil))) (describe "ast-search-cps — CPS tree search"
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
              :to-be target-leaf)))) (describe "ast-find-first — direct-style convenience over ast-search-cps"
  (it-sequential "returns the first matching node"
    (let ((target (make-ast-var :name 'needle)))
      (expect (ast-find-first
               (make-ast-if :cond (make-ast-int :value 1) :then target :else (make-ast-int :value 0))
               (lambda (n) (typep n 'ast-var)))
              :to-be target)))

  (it-sequential "returns nil when nothing matches"
    (expect (ast-find-first (make-ast-int :value 1) (lambda (n) (typep n 'ast-var)))
            :to-be-null))) (describe "ast-to-sexp — one case per node kind"
  (define-ast-to-sexp-cases
    ((make-ast-int :value 42)
     42)
    ((make-ast-var :name 'x)
     'x)
    ((make-ast-hole)
     (intern "_" *package*))
    ((make-ast-quote :value '(a b))
     '(quote (a b)))
    ((make-ast-function :name 'car)
     '(function car))
    ((make-ast-binop :op '+ :lhs (make-ast-int :value 1) :rhs (make-ast-int :value 2))
     '(+ 1 2))
    ((make-ast-if :cond (make-ast-int :value 1)
                 :then (make-ast-int :value 2)
                 :else (make-ast-int :value 3))
     '(if 1 2 3))
    ((make-ast-progn :forms (list (make-ast-int :value 1) (make-ast-int :value 2)))
     '(progn 1 2))
    ((make-ast-print :expr (make-ast-int :value 1))
     '(print 1))
    ((make-ast-let :bindings (list (cons 'x (make-ast-int :value 1)))
                  :body (list (make-ast-var :name 'x)))
     '(let ((x 1)) x))
    ((make-ast-block :name 'b :body (list (make-ast-int :value 1)))
     '(block b 1))
    ((make-ast-return-from :name 'b :value (make-ast-int :value 1))
     '(return-from b 1))
    ((make-ast-tagbody :tags (list (list 'start (make-ast-int :value 1)) (list 'end)))
     '(tagbody start 1 end))
    ((make-ast-go :tag 'start)
     '(go start))
    ((make-ast-setq :var 'x :value (make-ast-int :value 1))
     '(setq x 1))
    ((make-ast-multiple-value-call :func (make-ast-function :name '+)
                                   :args (list (make-ast-int :value 1)))
     '(multiple-value-call (function +) 1))
    ((make-ast-multiple-value-prog1 :first (make-ast-int :value 1)
                                    :forms (list (make-ast-int :value 2)))
     '(multiple-value-prog1 1 2))
    ((make-ast-values :forms (list (make-ast-int :value 1) (make-ast-int :value 2)))
     '(values 1 2))
    ((make-ast-multiple-value-bind :vars '(a b)
                                   :values-form (make-ast-values :forms (list (make-ast-int :value 1)))
                                   :body (list (make-ast-var :name 'a)))
     '(multiple-value-bind (a b) (values 1) a))
    ((make-ast-apply :func (make-ast-function :name '+) :args (list (make-ast-int :value 1)))
     '(apply (function +) 1))
    ((make-ast-catch :tag (make-ast-quote :value 'tag) :body (list (make-ast-int :value 1)))
     '(catch (quote tag) 1))
    ((make-ast-throw :tag (make-ast-quote :value 'tag) :value (make-ast-int :value 1))
     '(throw (quote tag) 1))
    ((make-ast-unwind-protect :protected (make-ast-int :value 1)
                              :cleanup (list (make-ast-int :value 2)))
     '(unwind-protect 1 2))
    ((make-ast-call :func 'foo :args (list (make-ast-int :value 1)))
     '(foo 1))
    ((make-ast-call :func (make-ast-var :name 'f) :args (list (make-ast-int :value 1)))
     '(f 1))
    ((make-ast-list :elements (list (make-ast-int :value 1) (make-ast-int :value 2)))
     '(list 1 2))
    ((make-ast-the :type 'fixnum :value (make-ast-int :value 1))
     '(the fixnum 1))
    ((make-ast-defvar :name '*x* :value (make-ast-int :value 1))
     '(defvar *x* 1))
    ((make-ast-defvar :name '*x*)
     '(defvar *x*))
    ((make-ast-defmacro :name 'my-macro :lambda-list '(a b) :body (list '(list a b)))
     '(defmacro my-macro (a b) (list a b)))
    ((make-ast-make-instance :class (make-ast-quote :value 'widget)
                             :initargs (list (cons :size (make-ast-int :value 1))))
     '(make-instance (quote widget) :size 1))
    ((make-ast-slot-value :object (make-ast-var :name 'obj) :slot 'size)
     '(slot-value obj (quote size)))
    ((make-ast-set-slot-value :object (make-ast-var :name 'obj) :slot 'size
                              :value (make-ast-int :value 1))
     '(setf (slot-value obj (quote size)) 1))
    ((make-ast-set-gethash :key (make-ast-quote :value :k) :table (make-ast-var :name 'h)
                           :value (make-ast-int :value 1))
     '(setf (gethash (quote :k) h) 1)))) (describe "ast-to-sexp — lambda / defun lambda-list reconstruction"
  (it-sequential "lambda with required params only"
    (expect (ast-to-sexp (make-ast-lambda :params '(a b) :body (list (make-ast-var :name 'a))))
            :to-equal '(lambda (a b) a)))

  (it-sequential "lambda with optional param, no default"
    (expect (ast-to-sexp (make-ast-lambda :params '(a)
                                          :optional-params '((b nil nil))
                                          :body (list (make-ast-var :name 'a))))
            :to-equal '(lambda (a &optional b) a)))

  (it-sequential "lambda with optional param default only"
    (expect (ast-to-sexp (make-ast-lambda :params '(a)
                                          :optional-params (list (list 'b (make-ast-int :value 1) nil))
                                          :body (list (make-ast-var :name 'a))))
            :to-equal '(lambda (a &optional (b 1)) a)))

  (it-sequential "lambda with optional param default and supplied-p"
    (expect (ast-to-sexp (make-ast-lambda :params '(a)
                                          :optional-params (list (list 'b (make-ast-int :value 1) 'b-p))
                                          :body (list (make-ast-var :name 'a))))
            :to-equal '(lambda (a &optional (b 1 b-p)) a)))

  (it-sequential "lambda with rest param"
    (expect (ast-to-sexp (make-ast-lambda :params '(a) :rest-param 'rest
                                          :body (list (make-ast-var :name 'a))))
            :to-equal '(lambda (a &rest rest) a)))

  (it-sequential "lambda with key param, explicit keyword only"
    (expect (ast-to-sexp (make-ast-lambda :params '(a)
                                          :key-params (list (list 'b nil nil :the-b))
                                          :body (list (make-ast-var :name 'a))))
            :to-equal '(lambda (a &key ((:the-b b))) a)))

  (it-sequential "lambda with key param, explicit keyword and default"
    (expect (ast-to-sexp (make-ast-lambda :params '(a)
                                          :key-params (list (list 'b (make-ast-int :value 1) nil :the-b))
                                          :body (list (make-ast-var :name 'a))))
            :to-equal '(lambda (a &key ((:the-b b) 1)) a)))

  (it-sequential "lambda declarations render before the body"
    (expect (ast-to-sexp (make-ast-lambda :params '(a) :declarations '((type fixnum a))
                                          :body (list (make-ast-var :name 'a))))
            :to-equal '(lambda (a) (declare (type fixnum a)) a)))

  (it-sequential "flet reconstructs bindings and body"
    (expect (ast-to-sexp (make-ast-flet :bindings (list (list 'f '(x) (make-ast-var :name 'x)))
                                        :body (list (make-ast-int :value 1))))
            :to-equal '(flet ((f (x) x)) 1)))

  (it-sequential "labels reconstructs bindings and body"
    (expect (ast-to-sexp (make-ast-labels :bindings (list (list 'f '(x) (make-ast-var :name 'x)))
                                          :body (list (make-ast-int :value 1))))
            :to-equal '(labels ((f (x) x)) 1)))

  (it-sequential "defun with documentation and declarations"
    (expect (ast-to-sexp (make-ast-defun :name 'foo :params '(a)
                                         :documentation "does a thing"
                                         :declarations '((optimize speed))
                                         :body (list (make-ast-var :name 'a))))
            :to-equal '(defun foo (a) "does a thing" (optimize speed) a)))

  (it-sequential "defun without documentation omits the string"
    (expect (ast-to-sexp (make-ast-defun :name 'foo :params '(a)
                                         :body (list (make-ast-var :name 'a))))
            :to-equal '(defun foo (a) a)))

  (it-sequential "SETF DEFUN roundtrip preserves exact function name and body"
    (let* ((symbol (make-symbol "ACCESSOR"))
           (name (list 'cl:setf symbol))
           (form (ast-to-sexp
                  (funcall (fdefinition 'make-ast-defun) :name name :params '(value object)
                                  :documentation "setter"
                                  :declarations '((optimize speed))
                                  :body (list (make-ast-var :name 'value))))))
      (expect (eq (second form) name) :to-be-truthy)
      (expect (eq (car (second form)) 'cl:setf) :to-be-truthy)
      (expect (eq (cadr (second form)) symbol) :to-be-truthy)
      (expect form :to-equal
              (list 'defun name '(value object) "setter"
                    '(optimize speed) 'value))))) (describe "ast-to-sexp — handler-case clause variable presence"
  (it-sequential "clause with a condition variable"
    (expect (ast-to-sexp (make-ast-handler-case
                          :form (make-ast-int :value 1)
                          :clauses (list (list 'error 'e (make-ast-var :name 'e)))))
            :to-equal '(handler-case 1 (error (e) e))))

  (it-sequential "clause without a condition variable"
    (expect (ast-to-sexp (make-ast-handler-case
                          :form (make-ast-int :value 1)
                          :clauses (list (list 'error nil (make-ast-int :value 0)))))
            :to-equal '(handler-case 1 (error () 0))))) (describe "ast-to-sexp — CLOS nodes"
  (it-sequential "defgeneric"
    (expect (ast-to-sexp (make-ast-defgeneric :name 'area :params '(shape)))
            :to-equal '(defgeneric area (shape))))

  (it-sequential "defmethod without a qualifier"
    (expect (ast-to-sexp (make-ast-defmethod :name 'area
                                             :specializers (list (cons 'shape 'circle))
                                             :params '(shape)
                                             :body (list (make-ast-int :value 1))))
            :to-equal '(defmethod area ((shape circle)) 1)))

  (it-sequential "defmethod with a qualifier and an unspecialized param"
    (expect (ast-to-sexp (make-ast-defmethod :name 'area :qualifier :before
                                             :specializers (list nil)
                                             :params '(shape)
                                             :body (list (make-ast-int :value 1))))
            :to-equal '(defmethod area :before (shape) 1)))

  (it-sequential "minimal defclass has no trailing options"
    (expect (ast-to-sexp (make-ast-defclass :name 'widget :superclasses '(object)
                                            :slots (list (make-ast-slot-def :name 'size))))
            :to-equal '(defclass widget (object) (size))))

  (it-sequential "defclass with default-initargs, metaclass, and sealed"
    (expect (ast-to-sexp (make-ast-defclass
                          :name 'widget :superclasses '(object)
                          :slots (list (make-ast-slot-def :name 'size
                                                          :initarg :size
                                                          :initform (make-ast-int :value 0)
                                                          :reader 'widget-size
                                                          :type 'fixnum))
                          :default-initargs (list (cons :size (make-ast-int :value 1)))
                          :metaclass (make-ast-quote :value 'funcallable-standard-class)
                          :sealed t))
            :to-equal '(defclass widget (object)
                        ((size :initarg :size :initform 0 :reader widget-size :type fixnum))
                        (:default-initargs :size 1)
                        (:metaclass funcallable-standard-class)
                        (:sealed t))))

  (it-sequential "metaclass given as a non-quote AST node unparses through ast-to-sexp"
    (expect (ast-to-sexp (make-ast-defclass :name 'widget :superclasses '(object)
                                            :slots (list (make-ast-slot-def :name 'size))
                                            :metaclass (make-ast-var :name 'computed-metaclass)))
            :to-equal '(defclass widget (object) (size) (:metaclass computed-metaclass))))

  (it-sequential "slot-def with non-default allocation"
    (expect (slot-def-to-sexp (make-ast-slot-def :name 'shared-count :allocation :class))
            :to-equal '(shared-count :allocation :class)))

  (it-sequential "slot-def with allocation explicitly nil has no allocation option"
    (expect (slot-def-to-sexp (make-ast-slot-def :name 'size :allocation nil))
            :to-equal 'size))

  (it-sequential "slot-def with no options collapses to a bare name"
    (expect (slot-def-to-sexp (make-ast-slot-def :name 'size))
            :to-equal 'size))

  (it-sequential "slot-def with an accessor and a writer"
    (expect (slot-def-to-sexp (make-ast-slot-def :name 'size :accessor 'widget-size :writer 'set-widget-size))
            :to-equal '(size :writer set-widget-size :accessor widget-size)))) (describe "ast-to-sexp — property: preserves evaluated meaning"
  (it-property "ast-to-sexp of a generated arithmetic tree evaluates to the same value as interpreting the tree directly"
      ((tree (%gen-arith-tree 3)))
    (expect (eval (ast-to-sexp tree)) :to-equal (%interpret-arith-tree tree)))))
