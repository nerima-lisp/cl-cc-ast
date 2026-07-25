;;;; t/ast-roundtrip-test.lisp — AST -> S-expression roundtrip (cl-weave).
;;;;
;;;; Covers every AST-TO-SEXP method and SLOT-DEF-TO-SEXP using
;;;; DEFINE-AST-TO-SEXP-CASES, a thin specialization of helpers-cases.lisp's
;;;; DEFINE-CASES that wraps every row's node form in an AST-TO-SEXP call.

(in-package :cl-cc-ast/test)

(defmacro define-ast-to-sexp-cases (&body cases)
  "Register one AST-TO-SEXP case per (NODE-FORM EXPECTED-FORM) pair in CASES;
see DEFINE-CASES for the underlying table-test mechanics."
  `(define-cases
     ,@(loop for (node-form expected-form) in cases
             collect `((ast-to-sexp ,node-form) ,expected-form))))

;;; ─────────────────────────────────────────────────────────────────────────
;;; ast-to-sexp — one case per node kind
;;; ─────────────────────────────────────────────────────────────────────────

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
  ((make-ast-tagbody :tags (list (cons 'start (list (make-ast-int :value 1)))
                                 (cons 'end nil)))
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
   '(setf (gethash (quote :k) h) 1)))

;;; ─────────────────────────────────────────────────────────────────────────
;;; ast-to-sexp — lambda / defun lambda-list reconstruction
;;; ─────────────────────────────────────────────────────────────────────────

(it-sequential "ast-to-sexp: lambda with required params only"
  (expect (ast-to-sexp (make-ast-lambda :params '(a b) :body (list (make-ast-var :name 'a))))
          :to-equal '(lambda (a b) a)))

(it-sequential "ast-to-sexp: lambda with optional param, no default"
  (expect (ast-to-sexp (make-ast-lambda :params '(a)
                                        :optional-params '((b nil nil))
                                        :body (list (make-ast-var :name 'a))))
          :to-equal '(lambda (a &optional b) a)))

(it-sequential "ast-to-sexp: lambda with optional param default only"
  (expect (ast-to-sexp (make-ast-lambda :params '(a)
                                        :optional-params (list (list 'b (make-ast-int :value 1) nil))
                                        :body (list (make-ast-var :name 'a))))
          :to-equal '(lambda (a &optional (b 1)) a)))

(it-sequential "ast-to-sexp: lambda with optional param default and supplied-p"
  (expect (ast-to-sexp (make-ast-lambda :params '(a)
                                        :optional-params (list (list 'b (make-ast-int :value 1) 'b-p))
                                        :body (list (make-ast-var :name 'a))))
          :to-equal '(lambda (a &optional (b 1 b-p)) a)))

(it-sequential "ast-to-sexp: lambda with rest param"
  (expect (ast-to-sexp (make-ast-lambda :params '(a) :rest-param 'rest
                                        :body (list (make-ast-var :name 'a))))
          :to-equal '(lambda (a &rest rest) a)))

(it-sequential "ast-to-sexp: lambda with key param, explicit keyword only"
  (expect (ast-to-sexp (make-ast-lambda :params '(a)
                                        :key-params (list (list 'b nil nil :the-b))
                                        :body (list (make-ast-var :name 'a))))
          :to-equal '(lambda (a &key ((:the-b b))) a)))

(it-sequential "ast-to-sexp: lambda with key param, explicit keyword and default"
  (expect (ast-to-sexp (make-ast-lambda :params '(a)
                                        :key-params (list (list 'b (make-ast-int :value 1) nil :the-b))
                                        :body (list (make-ast-var :name 'a))))
          :to-equal '(lambda (a &key ((:the-b b) 1)) a)))

(it-sequential "ast-to-sexp: lambda declarations render before the body"
  (expect (ast-to-sexp (make-ast-lambda :params '(a) :declarations '((type fixnum a))
                                        :body (list (make-ast-var :name 'a))))
          :to-equal '(lambda (a) (declare (type fixnum a)) a)))

(it-sequential "ast-to-sexp: flet reconstructs bindings and body"
  (expect (ast-to-sexp (make-ast-flet :bindings (list (list 'f '(x) (make-ast-var :name 'x)))
                                      :body (list (make-ast-int :value 1))))
          :to-equal '(flet ((f (x) x)) 1)))

(it-sequential "ast-to-sexp: labels reconstructs bindings and body"
  (expect (ast-to-sexp (make-ast-labels :bindings (list (list 'f '(x) (make-ast-var :name 'x)))
                                        :body (list (make-ast-int :value 1))))
          :to-equal '(labels ((f (x) x)) 1)))

(it-sequential "ast-to-sexp: defun with documentation and declarations"
  (expect (ast-to-sexp (make-ast-defun :name 'foo :params '(a)
                                       :documentation "does a thing"
                                       :declarations '((optimize speed))
                                       :body (list (make-ast-var :name 'a))))
          :to-equal '(defun foo (a) "does a thing" (optimize speed) a)))

(it-sequential "ast-to-sexp: defun without documentation omits the string"
  (expect (ast-to-sexp (make-ast-defun :name 'foo :params '(a)
                                       :body (list (make-ast-var :name 'a))))
          :to-equal '(defun foo (a) a)))

;;; ─────────────────────────────────────────────────────────────────────────
;;; ast-to-sexp — handler-case clause variable presence
;;; ─────────────────────────────────────────────────────────────────────────

(it-sequential "ast-to-sexp: handler-case clause with a condition variable"
  (expect (ast-to-sexp (make-ast-handler-case
                        :form (make-ast-int :value 1)
                        :clauses (list (list 'error 'e (make-ast-var :name 'e)))))
          :to-equal '(handler-case 1 (error (e) e))))

(it-sequential "ast-to-sexp: handler-case clause without a condition variable"
  (expect (ast-to-sexp (make-ast-handler-case
                        :form (make-ast-int :value 1)
                        :clauses (list (list 'error nil (make-ast-int :value 0)))))
          :to-equal '(handler-case 1 (error () 0))))

;;; ─────────────────────────────────────────────────────────────────────────
;;; ast-to-sexp — CLOS nodes
;;; ─────────────────────────────────────────────────────────────────────────

(it-sequential "ast-to-sexp: defgeneric"
  (expect (ast-to-sexp (make-ast-defgeneric :name 'area :params '(shape)))
          :to-equal '(defgeneric area (shape))))

(it-sequential "ast-to-sexp: defmethod without a qualifier"
  (expect (ast-to-sexp (make-ast-defmethod :name 'area
                                           :specializers (list (cons 'shape 'circle))
                                           :params '(shape)
                                           :body (list (make-ast-int :value 1))))
          :to-equal '(defmethod area ((shape circle)) 1)))

(it-sequential "ast-to-sexp: defmethod with a qualifier and an unspecialized param"
  (expect (ast-to-sexp (make-ast-defmethod :name 'area :qualifier :before
                                           :specializers (list nil)
                                           :params '(shape)
                                           :body (list (make-ast-int :value 1))))
          :to-equal '(defmethod area :before (shape) 1)))

(it-sequential "ast-to-sexp: minimal defclass has no trailing options"
  (expect (ast-to-sexp (make-ast-defclass :name 'widget :superclasses '(object)
                                          :slots (list (make-ast-slot-def :name 'size))))
          :to-equal '(defclass widget (object) (size))))

(it-sequential "ast-to-sexp: defclass with default-initargs, metaclass, and sealed"
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

(it-sequential "ast-to-sexp: defclass metaclass given as a non-quote AST node unparses through ast-to-sexp"
  (expect (ast-to-sexp (make-ast-defclass :name 'widget :superclasses '(object)
                                          :slots (list (make-ast-slot-def :name 'size))
                                          :metaclass (make-ast-var :name 'computed-metaclass)))
          :to-equal '(defclass widget (object) (size) (:metaclass computed-metaclass))))

(it-sequential "ast-to-sexp: slot-def with non-default allocation"
  (expect (slot-def-to-sexp (make-ast-slot-def :name 'shared-count :allocation :class))
          :to-equal '(shared-count :allocation :class)))

(it-sequential "ast-to-sexp: slot-def with allocation explicitly nil has no allocation option"
  (expect (slot-def-to-sexp (make-ast-slot-def :name 'size :allocation nil))
          :to-equal 'size))

(it-sequential "ast-to-sexp: slot-def with no options collapses to a bare name"
  (expect (slot-def-to-sexp (make-ast-slot-def :name 'size))
          :to-equal 'size))

(it-sequential "ast-to-sexp: slot-def with an accessor and a writer"
  (expect (slot-def-to-sexp (make-ast-slot-def :name 'size :accessor 'widget-size :writer 'set-widget-size))
          :to-equal '(size :writer set-widget-size :accessor widget-size)))
