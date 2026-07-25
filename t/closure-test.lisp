;;;; t/closure-test.lisp — closure / free-variable / escape analysis (cl-weave).
;;;;
;;;; Covers every public helper in src/closure.lisp: mutation tracking, free-
;;;; variable analysis, escape classification, and the closure-sharing
;;;; grouping helpers used by downstream closure conversion. Plain single-call
;;;; assertions use helpers-cases.lisp's DEFINE-CASES table macro; cases that
;;;; need shared setup or multiple assertions stay as hand-written IT-SEQUENTIAL.

(in-package :cl-cc-ast/test)

(defun %sorted-symbols (symbols)
  "Sort SYMBOLS by name so set-like results compare deterministically."
  (sort (copy-list symbols) #'string< :key #'symbol-name))

;;; ─────────────────────────────────────────────────────────────────────────
;;; find-mutated-variables / mutated-vars-of-list
;;; ─────────────────────────────────────────────────────────────────────────

(define-cases
  ((find-mutated-variables (make-ast-setq :var 'x :value (make-ast-int :value 1)))
   '(x))
  ((find-mutated-variables (make-ast-var :name 'x))
   nil))

(it-sequential "find-mutated-variables: recurses through generic children"
  (let ((node (make-ast-progn
               :forms (list (make-ast-setq :var 'x :value (make-ast-int :value 1))
                            (make-ast-setq :var 'y :value (make-ast-int :value 2))))))
    (expect (%sorted-symbols (find-mutated-variables node)) :to-equal '(x y))))

(it-sequential "mutated-vars-of-list: unions mutations across sibling nodes"
  (let ((nodes (list (make-ast-setq :var 'x :value (make-ast-int :value 1))
                     (make-ast-setq :var 'y :value (make-ast-int :value 2)))))
    (expect (%sorted-symbols (mutated-vars-of-list nodes)) :to-equal '(x y))))

;;; ─────────────────────────────────────────────────────────────────────────
;;; find-free-variables / free-vars-of-list / free-vars-of-defaults
;;; ─────────────────────────────────────────────────────────────────────────

(define-cases
  ((find-free-variables (make-ast-var :name 'x))
   '(x)))

(it-sequential "find-free-variables: setq's target and value are both free"
  (expect (%sorted-symbols
           (find-free-variables (make-ast-setq :var 'x :value (make-ast-var :name 'y))))
          :to-equal '(x y)))

(it-sequential "find-free-variables: let subtracts its own bound names"
  (expect (find-free-variables
           (make-ast-let :bindings (list (cons 'x (make-ast-var :name 'outer)))
                        :body (list (make-ast-var :name 'x))))
          :to-equal '(outer)))

(it-sequential "find-free-variables: lambda subtracts params and includes default free vars"
  (expect (%sorted-symbols
           (find-free-variables
            (make-ast-lambda :params '(a)
                             :optional-params (list (list 'b (make-ast-var :name 'outer) nil))
                             :body (list (make-ast-var :name 'a) (make-ast-var :name 'free-in-body)))))
          :to-equal '(free-in-body outer)))

(it-sequential "find-free-variables: defun subtracts params and includes default free vars"
  (expect (%sorted-symbols
           (find-free-variables
            (make-ast-defun :name 'foo :params '(a)
                            :key-params (list (list 'b (make-ast-var :name 'outer) nil))
                            :body (list (make-ast-var :name 'a) (make-ast-var :name 'free-in-body)))))
          :to-equal '(free-in-body outer)))

(it-sequential "find-free-variables: local-fns (flet/labels) subtracts function names"
  (expect (%sorted-symbols
           (find-free-variables
            (make-ast-flet :bindings (list (list 'f '(x) (make-ast-var :name 'x))
                                           (list 'f (list) (make-ast-var :name 'outer)))
                          :body (list (make-ast-call :func 'f :args nil)))))
          :to-equal '(outer)))

(it-sequential "find-free-variables: multiple-value-bind subtracts its own vars"
  (expect (find-free-variables
           (make-ast-multiple-value-bind
            :vars '(a b)
            :values-form (make-ast-var :name 'source)
            :body (list (make-ast-var :name 'a) (make-ast-var :name 'other))))
          :to-equal '(source other)))

(it-sequential "find-free-variables: generic nodes recurse through ast-children"
  (expect (%sorted-symbols
           (find-free-variables
            (make-ast-if :cond (make-ast-var :name 'c)
                        :then (make-ast-var :name 'a)
                        :else (make-ast-var :name 'b))))
          :to-equal '(a b c)))

(it-sequential "free-vars-of-list: unions free variables across sibling nodes"
  (expect (%sorted-symbols
           (free-vars-of-list (list (make-ast-var :name 'x) (make-ast-var :name 'y))))
          :to-equal '(x y)))

(define-cases
  ((free-vars-of-defaults (list (list 'a nil) (list 'b (make-ast-var :name 'z))))
   '(z)))

(it-property "find-free-variables never returns a let's own bound names"
    ((bound-raw (gen-list (gen-member '(a b c d e)) :min-length 1 :max-length 5))
     (body-var (gen-member '(a b c d e f g))))
  (let* ((bound-names (remove-duplicates bound-raw))
         (node (make-ast-let
                :bindings (mapcar (lambda (n) (cons n (make-ast-int :value 0))) bound-names)
                :body (list (make-ast-var :name body-var)))))
    (expect (intersection (find-free-variables node) bound-names) :to-be-null)))

;;; ─────────────────────────────────────────────────────────────────────────
;;; binding-escape-kinds-in-body / binding-escapes-in-body-p
;;; ─────────────────────────────────────────────────────────────────────────

(define-cases
  ((binding-escape-kinds-in-body (list (make-ast-var :name 'x)) 'x)
   '(:return)))

(it-sequential "escape analysis: a variable never mentioned does not escape"
  (expect (binding-escape-kinds-in-body (list (make-ast-var :name 'y)) 'x) :to-be-null)
  (expect (binding-escapes-in-body-p (list (make-ast-var :name 'y)) 'x) :to-be nil))

(it-sequential "escape analysis: a non-list BODY-FORMS argument never escapes"
  (expect (binding-escape-kinds-in-body (make-ast-var :name 'x) 'x) :to-be-null)
  (expect (binding-escapes-in-body-p (make-ast-var :name 'x) 'x) :to-be nil))

(it-sequential "escape analysis: calling a binding directly is not an escape"
  (expect (binding-escape-kinds-in-body (list (make-ast-call :func 'x :args nil)) 'x)
          :to-be-null))

(it-sequential "escape analysis: closing over a binding in a nested lambda is a :capture"
  (let ((kinds (binding-escape-kinds-in-body
                (list (make-ast-lambda :body (list (make-ast-var :name 'x)))) 'x)))
    (expect (member :capture kinds) :to-be-truthy)))

(it-sequential "escape analysis: a nested lambda that never mentions the binding does not capture it"
  (expect (binding-escape-kinds-in-body
           (list (make-ast-lambda :body (list (make-ast-var :name 'unrelated)))) 'x)
          :to-be-null))

(it-sequential "escape analysis: passing a binding as a call argument is an :external-call"
  (let ((kinds (binding-escape-kinds-in-body
                (list (make-ast-call :func 'foo :args (list (make-ast-var :name 'x)))) 'x)))
    (expect (member :external-call kinds) :to-be-truthy)
    (expect (member :return kinds) :to-be-truthy)))

(it-sequential "escape analysis: passing a binding to funcall is an :external-call"
  (let ((kinds (binding-escape-kinds-in-body
                (list (make-ast-call :func 'funcall :args (list (make-ast-var :name 'x)))) 'x)))
    (expect (member :external-call kinds) :to-be-truthy)))

(it-sequential "escape analysis: a declared safe consumer suppresses escape detection"
  (expect (binding-escape-kinds-in-body
           (list (make-ast-call :func 'safe-fn :args (list (make-ast-var :name 'x)))) 'x
           :safe-consumers '("SAFE-FN"))
          :to-be-null)
  (expect (binding-escapes-in-body-p
           (list (make-ast-call :func 'safe-fn :args (list (make-ast-var :name 'x)))) 'x
           :safe-consumers '("SAFE-FN"))
          :to-be nil))

(it-sequential "escape analysis: escapes through generic ast-children recursion"
  (let ((kinds (binding-escape-kinds-in-body
                (list (make-ast-if :cond (make-ast-int :value 1)
                                   :then (make-ast-var :name 'x)
                                   :else (make-ast-int :value 0)))
                'x)))
    (expect (member :return kinds) :to-be-truthy)))

(it-sequential "escape analysis: a nested defun closing over a binding is a :capture"
  (let ((kinds (binding-escape-kinds-in-body
                (list (make-ast-defun :name 'inner :body (list (make-ast-var :name 'x)))) 'x)))
    (expect (member :capture kinds) :to-be-truthy)))

(it-sequential "escape analysis: a nested defmethod closing over a binding is a :capture"
  (let ((kinds (binding-escape-kinds-in-body
                (list (make-ast-defmethod :name 'foo :params '(y)
                                          :body (list (make-ast-var :name 'x))))
                'x)))
    (expect (member :capture kinds) :to-be-truthy)))

(it-sequential "escape analysis: a flet body referencing a binding is a :capture"
  (let ((kinds (binding-escape-kinds-in-body
                (list (make-ast-flet :bindings (list (list 'f '(y) (make-ast-int :value 0)))
                                     :body (list (make-ast-var :name 'x))))
                'x)))
    (expect (member :capture kinds) :to-be-truthy)))

(it-sequential "escape analysis: passing a binding to apply is an :external-call"
  (let ((kinds (binding-escape-kinds-in-body
                (list (make-ast-apply :func (make-ast-function :name 'foo)
                                      :args (list (make-ast-var :name 'x))))
                'x)))
    (expect (member :external-call kinds) :to-be-truthy)))

(it-sequential "escape analysis: capture is detected through a nested non-var form"
  (let ((kinds (binding-escape-kinds-in-body
                (list (make-ast-lambda
                       :body (list (make-ast-if :cond (make-ast-int :value 1)
                                                :then (make-ast-var :name 'x)
                                                :else (make-ast-int :value 0)))))
                'x)))
    (expect (member :capture kinds) :to-be-truthy)))

(it-sequential "escape analysis: calling through a binding-valued function target merges its own escape"
  (let ((kinds (binding-escape-kinds-in-body
                (list (make-ast-call :func (make-ast-var :name 'x)
                                     :args (list (make-ast-var :name 'x))))
                'x)))
    (expect (member :external-call kinds) :to-be-truthy)
    (expect (member :return kinds) :to-be-truthy)))

(it-sequential "escape analysis: an AST-valued call target with no matching args classifies the target alone"
  (let ((kinds (binding-escape-kinds-in-body
                (list (make-ast-call :func (make-ast-var :name 'x)
                                     :args (list (make-ast-int :value 1))))
                'x)))
    (expect kinds :to-equal '(:return))))

;;; ─────────────────────────────────────────────────────────────────────────
;;; find-captured-in-children
;;; ─────────────────────────────────────────────────────────────────────────

(it-sequential "find-captured-in-children: a nested lambda capturing a param"
  (expect (find-captured-in-children
           (list (make-ast-lambda :body (list (make-ast-var :name 'x))))
           '(x y))
          :to-equal '(x)))

(it-sequential "find-captured-in-children: a nested defun capturing a param"
  (expect (find-captured-in-children
           (list (make-ast-defun :name 'inner :body (list (make-ast-var :name 'x))))
           '(x y))
          :to-equal '(x)))

(it-sequential "find-captured-in-children: local-fns bindings and body are both scanned"
  (expect (%sorted-symbols
           (find-captured-in-children
            (list (make-ast-flet
                   :bindings (list (list 'f (list) (make-ast-var :name 'x)))
                   :body (list (make-ast-var :name 'y))))
            '(x y z)))
          :to-equal '(x)))

(it-sequential "find-captured-in-children: variables outside params are not candidates"
  (expect (find-captured-in-children
           (list (make-ast-lambda :body (list (make-ast-var :name 'unrelated))))
           '(x y))
          :to-be-null))

(it-sequential "find-captured-in-children: recurses through non-boundary forms"
  (expect (find-captured-in-children
           (list (make-ast-if :cond (make-ast-int :value 1)
                              :then (make-ast-lambda :body (list (make-ast-var :name 'x)))
                              :else (make-ast-int :value 0)))
           '(x y))
          :to-equal '(x)))

;;; ─────────────────────────────────────────────────────────────────────────
;;; closure-capture-key / trim-captured-vars / group-shared-sibling-captures
;;; ─────────────────────────────────────────────────────────────────────────

(define-cases
  ((closure-capture-key '((b . r2) (a . r1) (a . r3)))
   '(a b))
  ((trim-captured-vars '((a . r1) (b . r2) (a . r3) (c . r4)) '(c a))
   '((a . r1) (c . r4)))
  ((trim-captured-vars '((a . r1) (b . r2)) '())
   nil))

(it-property "closure-capture-key is sorted and duplicate-free for any captured-vars alist"
    ((vars (gen-list (gen-member '(a b c d e)) :min-length 0 :max-length 8)))
  (let* ((captures (mapcar (lambda (v) (cons v (gensym))) vars))
         (key (closure-capture-key captures)))
    (expect (remove-duplicates key) :to-equal key)
    (expect (sort (copy-list key) #'string< :key #'symbol-name) :to-equal key)))

(it-sequential "group-shared-sibling-captures: groups siblings by capture-set, drops singletons"
  (let* ((captures-1 '((a . r1) (b . r2)))
         (captures-2 '((b . r3) (a . r4)))
         (captures-3 '((c . r5)))
         (groups (group-shared-sibling-captures (list captures-1 captures-2 captures-3))))
    (expect (hash-table-count groups) :to-equal 1)
    (expect (gethash (closure-capture-key captures-1) groups)
            :to-equal (list captures-1 captures-2))))

;;; ─────────────────────────────────────────────────────────────────────────
;;; binding-direct-call-count-in-body / binding-one-shot-p
;;; ─────────────────────────────────────────────────────────────────────────

(define-cases
  ((binding-direct-call-count-in-body
    (list (make-ast-call :func 'f :args (list (make-ast-call :func 'f :args nil))))
    'f)
   2)
  ((binding-direct-call-count-in-body (list (make-ast-var :name 'x)) 'f)
   0)
  ((binding-direct-call-count-in-body (make-ast-var :name 'x) 'f)
   0)
  ((binding-direct-call-count-in-body
    (list (make-ast-call :func 'g :args (list (make-ast-call :func 'f :args nil))))
    'f)
   1)
  ((binding-direct-call-count-in-body
    (list (make-ast-if :cond (make-ast-call :func 'f :args nil)
                       :then (make-ast-int :value 0)
                       :else (make-ast-int :value 0)))
    'f)
   1))

(it-sequential "binding-one-shot-p: true for exactly one non-escaping direct call"
  (expect (binding-one-shot-p (list (make-ast-call :func 'f :args nil)) 'f) :to-be-truthy))

(it-sequential "binding-one-shot-p: false when called more than once"
  (expect (binding-one-shot-p
           (list (make-ast-call :func 'f :args nil) (make-ast-call :func 'f :args nil))
           'f)
          :to-be nil))

(it-sequential "binding-one-shot-p: false when the binding also escapes"
  (expect (binding-one-shot-p
           (list (make-ast-call :func 'f :args nil) (make-ast-var :name 'f))
           'f)
          :to-be nil))

;;; ─────────────────────────────────────────────────────────────────────────
;;; closure-sharing-key / group-shareable-closures
;;; ─────────────────────────────────────────────────────────────────────────

(define-cases
  ((closure-sharing-key 'entry-1 '((a . r1) (b . r2)))
   '(entry-1 (a b))))

(it-sequential "group-shareable-closures: groups by (entry-label . capture-key), drops singletons"
  (let* ((d1 (list :entry-label 'l1 :captured-vars '((a . r1))))
         (d2 (list :entry-label 'l1 :captured-vars '((a . r2))))
         (d3 (list :entry-label 'l2 :captured-vars '((a . r3))))
         (groups (group-shareable-closures (list d1 d2 d3))))
    (expect (hash-table-count groups) :to-equal 1)
    (expect (gethash (closure-sharing-key 'l1 '((a . r1))) groups) :to-equal (list d1 d2))))
