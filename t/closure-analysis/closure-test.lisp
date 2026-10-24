(in-package :cl-cc/ast/closure-analysis/test)

(defun %sorted-symbols (symbols)
  "Sort SYMBOLS by name so set-like results compare deterministically."
  (sort (copy-list symbols) #'string< :key #'symbol-name))

(defmacro expect-escape-kind (kind body-forms binding-name &key safe-consumers)
  "Assert that KIND is among BINDING-NAME's escape kinds in BODY-FORMS.

Factors out the repeated \"compute the escape kinds, then check membership\"
shape that dominates the escape-analysis suite below: every case that only
cares whether one particular kind shows up, rather than the exact kind set,
reads as one line instead of a LET plus an EXPECT."
  `(expect (member ,kind (binding-escape-kinds-in-body ,body-forms ,binding-name
                                                        :safe-consumers ,safe-consumers))
           :to-be-truthy))

(describe-concurrent "closure / free-variable / escape analysis"

(describe "find-mutated-variables / mutated-vars-of-list"
  (define-cases
    ((find-mutated-variables (make-ast-setq :var 'x :value (make-ast-int :value 1)))
     '(x))
    ((find-mutated-variables (make-ast-var :name 'x))
     nil))

  (it-sequential "find-mutated-variables recurses through generic children"
    (let ((node (make-ast-progn
                 :forms (list (make-ast-setq :var 'x :value (make-ast-int :value 1))
                              (make-ast-setq :var 'y :value (make-ast-int :value 2))))))
      (expect (%sorted-symbols (find-mutated-variables node)) :to-equal '(x y))))

  (it-sequential "mutated-vars-of-list unions mutations across sibling nodes"
    (let ((nodes (list (make-ast-setq :var 'x :value (make-ast-int :value 1))
                       (make-ast-setq :var 'y :value (make-ast-int :value 2)))))
      (expect (%sorted-symbols (mutated-vars-of-list nodes)) :to-equal '(x y))))

  (it-sequential "find-mutated-variables drives its result through an explicit continuation"
    (with-continuation-result (result next calledp)
        (find-mutated-variables (make-ast-setq :var 'x :value (make-ast-int :value 1)) #'next)
      (expect calledp :to-be-truthy)
      (expect result :to-equal '(x))))

  (it-sequential "mutated-vars-of-list drives its result through an explicit continuation"
    (with-continuation-result (result next calledp)
        (mutated-vars-of-list
         (list (make-ast-setq :var 'x :value (make-ast-int :value 1))
               (make-ast-setq :var 'y :value (make-ast-int :value 2)))
         #'next)
      (expect calledp :to-be-truthy)
      (expect (%sorted-symbols result) :to-equal '(x y)))))

(describe "find-free-variables / free-vars-of-list / free-vars-of-defaults"
  (define-cases
    ((find-free-variables (make-ast-var :name 'x))
     '(x)))

  (it-sequential "setq's target and value are both free"
    (expect (%sorted-symbols
             (find-free-variables (make-ast-setq :var 'x :value (make-ast-var :name 'y))))
            :to-equal '(x y)))

  (it-sequential "let subtracts its own bound names"
    (expect (find-free-variables
             (make-ast-let :bindings (list (cons 'x (make-ast-var :name 'outer)))
                          :body (list (make-ast-var :name 'x))))
            :to-equal '(outer)))

  (it-sequential "lambda subtracts params and includes default free vars"
    (expect (%sorted-symbols
             (find-free-variables
              (make-ast-lambda :params '(a)
                               :optional-params (list (list 'b (make-ast-var :name 'outer) nil))
                               :body (list (make-ast-var :name 'a) (make-ast-var :name 'free-in-body)))))
            :to-equal '(free-in-body outer)))

  (it-sequential "defun subtracts params and includes default free vars"
    (expect (%sorted-symbols
             (find-free-variables
              (make-ast-defun :name 'foo :params '(a)
                              :key-params (list (list 'b (make-ast-var :name 'outer) nil))
                              :body (list (make-ast-var :name 'a) (make-ast-var :name 'free-in-body)))))
            :to-equal '(free-in-body outer)))

  (it-sequential "local-fns (flet/labels) subtracts function names"
    (expect (%sorted-symbols
             (find-free-variables
              (make-ast-flet :bindings (list (list 'f '(x) (make-ast-var :name 'x))
                                             (list 'f (list) (make-ast-var :name 'outer)))
                            :body (list (make-ast-call :func 'f :args nil)))))
            :to-equal '(outer)))

  (it-sequential "multiple-value-bind subtracts its own vars"
    (expect (find-free-variables
             (make-ast-multiple-value-bind
              :vars '(a b)
              :values-form (make-ast-var :name 'source)
              :body (list (make-ast-var :name 'a) (make-ast-var :name 'other))))
            :to-equal '(source other)))

  (it-sequential "generic nodes recurse through ast-children"
    (expect (%sorted-symbols
             (find-free-variables
              (make-ast-if :cond (make-ast-var :name 'c)
                          :then (make-ast-var :name 'a)
                          :else (make-ast-var :name 'b))))
            :to-equal '(a b c)))

  (it-sequential "free-vars-of-list unions free variables across sibling nodes"
    (expect (%sorted-symbols
             (free-vars-of-list (list (make-ast-var :name 'x) (make-ast-var :name 'y))))
            :to-equal '(x y)))

  (define-cases
    ((free-vars-of-defaults (list (list 'a nil) (list 'b (make-ast-var :name 'z))))
     '(z)))

  (it-property "never returns a let's own bound names"
      ((bound-raw (gen-list (gen-member '(a b c d e)) :min-length 1 :max-length 5))
       (body-var (gen-member '(a b c d e f g))))
    (let* ((bound-names (remove-duplicates bound-raw))
           (node (make-ast-let
                  :bindings (mapcar (lambda (n) (cons n (make-ast-int :value 0))) bound-names)
                  :body (list (make-ast-var :name body-var)))))
      (expect (intersection (find-free-variables node) bound-names) :to-be-null)))

  (it-sequential "find-free-variables drives its result through an explicit continuation"
    (with-continuation-result (result next calledp)
        (find-free-variables (make-ast-var :name 'x) #'next)
      (expect calledp :to-be-truthy)
      (expect result :to-equal '(x))))

  (it-sequential "free-vars-of-list drives its result through an explicit continuation"
    (with-continuation-result (result next calledp)
        (free-vars-of-list (list (make-ast-var :name 'x) (make-ast-var :name 'y)) #'next)
      (expect calledp :to-be-truthy)
      (expect (%sorted-symbols result) :to-equal '(x y))))

  (it-sequential "free-vars-atomic-forms int"
    (expect (find-free-variables (make-ast-int :value 42)) :to-equal nil))

  (it-sequential "free-vars-atomic-forms quote"
    (expect (find-free-variables (make-ast-quote :value '(a b c))) :to-equal nil))

  (it-sequential "free-vars-binop-two-distinct-vars"
    (expect (%sorted-symbols
             (find-free-variables
              (make-ast-binop :op '+
                              :lhs (make-ast-var :name 'x)
                              :rhs (make-ast-var :name 'y))))
            :to-equal '(x y)))

  (it-sequential "free-vars-same-var-deduplicated"
    (expect (find-free-variables
             (make-ast-binop :op '+
                             :lhs (make-ast-var :name 'x)
                             :rhs (make-ast-var :name 'x)))
            :to-equal '(x)))

  (it-sequential "free-vars-let-all-bound"
    (expect (find-free-variables
             (make-ast-let :bindings (list (cons 'x (make-ast-int :value 1)))
                           :body (list (make-ast-var :name 'x))))
            :to-equal nil))

  (it-sequential "free-vars-let-unbound-body-var-is-free"
    (expect (find-free-variables
             (make-ast-let
              :bindings (list (cons 'x (make-ast-int :value 1)))
              :body (list (make-ast-binop :op '+
                                         :lhs (make-ast-var :name 'x)
                                         :rhs (make-ast-var :name 'z)))))
            :to-equal '(z)))

  (it-sequential "free-vars-lambda-all-params-bound"
    (expect (find-free-variables
             (make-ast-lambda
              :params '(x y)
              :body (list (make-ast-binop :op '+
                                          :lhs (make-ast-var :name 'x)
                                          :rhs (make-ast-var :name 'y)))))
            :to-equal nil))

  (it-sequential "free-vars-lambda-outer-var-is-free"
    (expect (find-free-variables
             (make-ast-lambda
              :params '(x)
              :body (list (make-ast-binop :op '+
                                          :lhs (make-ast-var :name 'x)
                                          :rhs (make-ast-var :name 'z)))))
            :to-equal '(z)))

  (it-sequential "free-vars-lambda-rest-param-shadows-body"
    (expect (find-free-variables
             (make-ast-lambda :params '(x) :rest-param 'rest
                              :body (list (make-ast-var :name 'rest))))
            :to-equal nil))

  (it-sequential "free-vars-lambda-optional-param-shadows-body"
    (expect (find-free-variables
             (make-ast-lambda
              :params nil
              :optional-params (list (list 'a (make-ast-int :value 0) nil))
              :body (list (make-ast-var :name 'a))))
            :to-equal nil))

  (it-sequential "free-vars-keyword-param-is-not-free-in-body"
    (expect (find-free-variables
             (make-ast-lambda
              :params nil
              :key-params (list (list 'k nil nil))
              :body (list (make-ast-var :name 'k))))
            :to-equal nil))

  (it-sequential "free-vars-nested-let"
    (expect (find-free-variables
             (make-ast-let
              :bindings (list (cons 'x (make-ast-int :value 1)))
              :body (list
                     (make-ast-let
                      :bindings (list (cons 'y (make-ast-var :name 'x)))
                      :body (list (make-ast-var :name 'y)
                                  (make-ast-var :name 'w))))))
            :to-equal '(w)))

  (it-sequential "free-vars-defun-shadows-multiple-params"
    (expect (find-free-variables
             (make-ast-defun
              :name 'my-fn :params '(a b)
              :body (list (make-ast-var :name 'a)
                          (make-ast-var :name 'b)
                          (make-ast-var :name 'c))))
            :to-equal '(c)))

  (it-sequential "free-vars-call-symbol-func"
    (expect (find-free-variables
             (make-ast-call :func 'foo
                            :args (list (make-ast-var :name 'x))))
            :to-equal '(x)))

  (it-sequential "free-vars-call-ast-func-node"
    (expect (%sorted-symbols
             (find-free-variables
              (make-ast-call :func (make-ast-var :name 'f)
                             :args (list (make-ast-var :name 'x)))))
            :to-equal '(f x)))

  (it-sequential "free-vars-labels-outer-var-in-binding-is-free"
    (expect (find-free-variables
             (make-ast-labels
              :bindings (list (list 'rec '(n) (make-ast-var :name 'limit)))
              :body (list (make-ast-call :func 'rec
                                         :args (list (make-ast-int :value 0))))))
            :to-equal '(limit)))

  (it-sequential "free-vars-progn-collects-all-forms"
    (expect (%sorted-symbols
             (find-free-variables
              (make-ast-progn :forms (list (make-ast-var :name 'a)
                                           (make-ast-var :name 'b)))))
            :to-equal '(a b))))

(describe "binding-escape-kinds-in-body / binding-escapes-in-body-p"
  (define-cases
    ((binding-escape-kinds-in-body (list (make-ast-var :name 'x)) 'x)
     '(:return)))

  (it-sequential "a variable never mentioned does not escape"
    (expect (binding-escape-kinds-in-body (list (make-ast-var :name 'y)) 'x) :to-be-null)
    (expect (binding-escapes-in-body-p (list (make-ast-var :name 'y)) 'x) :to-be nil))

  (it-sequential "a non-list BODY-FORMS argument never escapes"
    (expect (binding-escape-kinds-in-body (make-ast-var :name 'x) 'x) :to-be-null)
    (expect (binding-escapes-in-body-p (make-ast-var :name 'x) 'x) :to-be nil))

  (it-sequential "calling a binding directly is not an escape"
    (expect (binding-escape-kinds-in-body (list (make-ast-call :func 'x :args nil)) 'x)
            :to-be-null))

  (it-sequential "closing over a binding in a nested lambda is a :capture"
    (expect-escape-kind :capture
        (list (make-ast-lambda :body (list (make-ast-var :name 'x)))) 'x))

  (it-sequential "a nested lambda that never mentions the binding does not capture it"
    (expect (binding-escape-kinds-in-body
             (list (make-ast-lambda :body (list (make-ast-var :name 'unrelated)))) 'x)
            :to-be-null))

  (it-sequential "passing a binding as a call argument is an :external-call"
    (let ((args (list (make-ast-call :func 'foo :args (list (make-ast-var :name 'x))))))
      (expect-escape-kind :external-call args 'x)
      (expect-escape-kind :return args 'x)))

  (it-sequential "passing a binding to funcall is an :external-call"
    (expect-escape-kind :external-call
        (list (make-ast-call :func 'funcall :args (list (make-ast-var :name 'x)))) 'x))

  (it-sequential "safe consumers only suppress direct references in the same scope"
    (let ((direct-call
            (make-ast-call :func 'safe-fn :args (list (make-ast-var :name 'x))))
          (length-call
            (make-ast-call :func 'cl:length :args (list (make-ast-var :name 'x))))
          (foreign-length-call
            (make-ast-call :func (make-symbol "LENGTH")
                           :args (list (make-ast-var :name 'x))))
          (nested-call
            (make-ast-call :func 'safe-fn
                           :args (list (make-ast-if
                                        :cond (make-ast-int :value 1)
                                        :then (make-ast-var :name 'x)
                                        :else (make-ast-int :value 0)))))
          (capturing-call
            (make-ast-call :func 'safe-fn
                           :args (list (make-ast-lambda
                                        :body (list (make-ast-var :name 'x))))))
          (shadowed-call
            (make-ast-flet
             :bindings (list (list 'length '(value) (make-ast-int :value 0)))
             :body (list (make-ast-call :func 'cl:length
                                        :args (list (make-ast-var :name 'x)))))))
      (expect (binding-escape-kinds-in-body
               (list direct-call) 'x :safe-consumers '("SAFE-FN"))
              :to-be-null)
      (expect (binding-escape-kinds-in-body
               (list length-call) 'x :safe-consumers (list 'cl:length))
              :to-be-null)
      (expect-escape-kind :external-call (list foreign-length-call) 'x
                          :safe-consumers (list 'cl:length))
      (expect-escape-kind :return (list nested-call) 'x
                          :safe-consumers '("SAFE-FN"))
      (expect-escape-kind :capture (list capturing-call) 'x
                          :safe-consumers '("SAFE-FN"))
      (expect-escape-kind :external-call (list shadowed-call) 'x
                          :safe-consumers (list 'cl:length))))

  (it-sequential "escapes through generic ast-children recursion"
    (expect-escape-kind :return
        (list (make-ast-if :cond (make-ast-int :value 1)
                           :then (make-ast-var :name 'x)
                           :else (make-ast-int :value 0)))
        'x))

  (it-sequential "a nested defun closing over a binding is a :capture"
    (expect-escape-kind :capture
        (list (make-ast-defun :name 'inner :body (list (make-ast-var :name 'x)))) 'x))

  (it-sequential "a nested defmethod closing over a binding is a :capture"
    (expect-escape-kind :capture
        (list (make-ast-defmethod :name 'foo :params '(y)
                                  :body (list (make-ast-var :name 'x))))
        'x))

  (it-sequential "flet bodies and local functions capture a binding"
    (expect-escape-kind :capture
        (list (make-ast-flet :bindings (list (list 'f '(y) (make-ast-int :value 0)))
                             :body (list (make-ast-var :name 'x))))
        'x)
    (expect-escape-kind :capture
        (list (make-ast-flet
               :bindings (list (list 'f nil (make-ast-var :name 'x)))
               :body (list (make-ast-call :func 'f :args nil))))
        'x))
  (it-sequential "labels local function body captures a binding"
    (expect-escape-kind :capture
        (list (make-ast-labels
               :bindings (list (list 'f nil
                                     (make-ast-if :cond (make-ast-int :value 1)
                                                  :then (make-ast-var :name 'x)
                                                  :else (make-ast-int :value 0))))
               :body (list (make-ast-call :func 'f :args nil))))
        'x))

  (it-sequential "passing a binding to apply is an :external-call"
    (expect-escape-kind :external-call
        (list (make-ast-apply :func (make-ast-function :name 'foo)
                              :args (list (make-ast-var :name 'x))))
        'x))

  (it-sequential "capture is detected through a nested non-var form"
    (expect-escape-kind :capture
        (list (make-ast-lambda
               :body (list (make-ast-if :cond (make-ast-int :value 1)
                                        :then (make-ast-var :name 'x)
                                        :else (make-ast-int :value 0)))))
        'x))

  (it-sequential "calling through a binding-valued function target merges its own escape"
    (let ((args (list (make-ast-call :func (make-ast-var :name 'x)
                                     :args (list (make-ast-var :name 'x))))))
      (expect-escape-kind :external-call args 'x)
      (expect-escape-kind :return args 'x)))

  (it-sequential "an AST-valued call target with no matching args classifies the target alone"
    (let ((kinds (binding-escape-kinds-in-body
                  (list (make-ast-call :func (make-ast-var :name 'x)
                                       :args (list (make-ast-int :value 1))))
                  'x)))
      (expect kinds :to-equal '(:return))))

  (it-sequential "binding-escapes-in-body-p returns true for a direct reference"
    (expect (binding-escapes-in-body-p
             (list (make-ast-var :name 'x)) 'x)
            :to-be-truthy))

  (it-sequential "binding-escapes-in-body-p suppresses a safe direct consumer"
    (expect (binding-escapes-in-body-p
             (list (make-ast-call :func 'car
                                  :args (list (make-ast-var :name 'x))))
             'x :safe-consumers '("CAR"))
            :to-be nil))

  (it-sequential "binding-escapes-in-body-p reports closure capture"
    (expect (binding-escapes-in-body-p
             (list (make-ast-lambda :body (list (make-ast-var :name 'x)))) 'x)
            :to-be-truthy))

  (it-sequential "escape kinds deduplicate repeated uses and merge classifications"
    (let ((kinds (binding-escape-kinds-in-body
                  (list (make-ast-var :name 'x)
                        (make-ast-var :name 'x)
                        (make-ast-lambda :body (list (make-ast-var :name 'x))))
                  'x)))
      (expect (member :return kinds) :to-be-truthy)
      (expect (member :capture kinds) :to-be-truthy)
      (expect (length kinds) :to-equal 2)))

  (it-sequential "literal and compound nodes without the binding do not escape"
    (expect (binding-escape-kinds-in-body (list (make-ast-int :value 0)) 'x)
            :to-be-null)
    (expect (binding-escape-kinds-in-body
             (list (make-ast-progn :forms (list (make-ast-int :value 0)))) 'x)
            :to-be-null)
    (expect (binding-escape-kinds-in-body
             (list (make-ast-lambda :body (list (make-ast-int :value 0)))) 'x)
            :to-be-null))

  (it-sequential "an empty body has no escape kinds"
    (expect (binding-escape-kinds-in-body nil 'x) :to-be-null)
    (expect (binding-escapes-in-body-p nil 'x) :to-be nil)))

(describe "find-captured-in-children"
  (it-sequential "a nested lambda capturing a param"
    (expect (find-captured-in-children
             (list (make-ast-lambda :body (list (make-ast-var :name 'x))))
             '(x y))
            :to-equal '(x)))

  (it-sequential "a nested defun capturing a param"
    (expect (find-captured-in-children
             (list (make-ast-defun :name 'inner :body (list (make-ast-var :name 'x))))
             '(x y))
            :to-equal '(x)))

  (it-sequential "local-fns bindings and body are both scanned"
    (expect (%sorted-symbols
             (find-captured-in-children
              (list (make-ast-flet
                     :bindings (list (list 'f (list) (make-ast-var :name 'x)))
                     :body (list (make-ast-var :name 'y))))
              '(x y z)))
            :to-equal '(x)))

  (it-sequential "variables outside params are not candidates"
    (expect (find-captured-in-children
             (list (make-ast-lambda :body (list (make-ast-var :name 'unrelated))))
             '(x y))
            :to-be-null))

  (it-sequential "recurses through non-boundary forms"
    (expect (find-captured-in-children
             (list (make-ast-if :cond (make-ast-int :value 1)
                                :then (make-ast-lambda :body (list (make-ast-var :name 'x)))
                                :else (make-ast-int :value 0)))
             '(x y))
            :to-equal '(x)))

  (it-sequential "drives its result through an explicit continuation"
    (with-continuation-result (result next calledp)
        (find-captured-in-children
         (list (make-ast-lambda :body (list (make-ast-var :name 'x))))
         '(x y) #'next)
      (expect calledp :to-be-truthy)
      (expect result :to-equal '(x)))))

(describe "closure-capture-key / trim-captured-vars / group-shared-sibling-captures"
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

  (it-sequential "groups siblings by capture-set, drops singletons"
    (let* ((captures-1 '((a . r1) (b . r2)))
           (captures-2 '((b . r3) (a . r4)))
           (captures-3 '((c . r5)))
           (groups (group-shared-sibling-captures (list captures-1 captures-2 captures-3))))
      (expect (hash-table-count groups) :to-equal 1)
      (expect (gethash (closure-capture-key captures-1) groups)
              :to-equal (list captures-1 captures-2)))))

(describe "binding-direct-call-count-in-body / binding-one-shot-p"
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

  (it-sequential "true for exactly one non-escaping direct call"
    (expect (binding-one-shot-p (list (make-ast-call :func 'f :args nil)) 'f) :to-be-truthy))

  (it-sequential "false when called more than once"
    (expect (binding-one-shot-p
             (list (make-ast-call :func 'f :args nil) (make-ast-call :func 'f :args nil))
             'f)
            :to-be nil))

  (it-sequential "false when the binding also escapes"
    (expect (binding-one-shot-p
             (list (make-ast-call :func 'f :args nil) (make-ast-var :name 'f))
             'f)
            :to-be nil))

  (it-sequential "binding-direct-call-count counts a direct matching call"
    (expect (binding-direct-call-count-in-body
             (list (make-ast-call :func 'my-fn
                                  :args (list (make-ast-int :value 1))))
             'my-fn)
            :to-equal 1))

  (it-sequential "binding-direct-call-count ignores non-call references"
    (expect (binding-direct-call-count-in-body
             (list (make-ast-call :func 'f :args nil)
                   (make-ast-var :name 'f))
             'f)
            :to-equal 1))

  (it-sequential "binding-direct-call-count returns zero for a different callee"
    (expect (binding-direct-call-count-in-body
             (list (make-ast-call :func 'other-fn :args nil)) 'my-fn)
            :to-equal 0))

  (it-sequential "binding-one-shot-p is false when a call is captured"
    (expect (binding-one-shot-p
             (list (make-ast-call :func 'f :args nil)
                   (make-ast-lambda :body (list (make-ast-var :name 'f))))
             'f)
            :to-be nil)))

(describe "closure-sharing-key / group-shareable-closures"
  (define-cases
    ((closure-sharing-key 'entry-1 '((a . r1) (b . r2)))
     '(entry-1 (a b))))

  (it-sequential "groups by (entry-label . capture-key), drops singletons"
    (let* ((d1 (list :entry-label 'l1 :captured-vars '((a . r1))))
           (d2 (list :entry-label 'l1 :captured-vars '((a . r2))))
           (d3 (list :entry-label 'l2 :captured-vars '((a . r3))))
           (groups (group-shareable-closures (list d1 d2 d3))))
      (expect (hash-table-count groups) :to-equal 1)
      (expect (gethash (closure-sharing-key 'l1 '((a . r1))) groups) :to-equal (list d1 d2))))

  (it-sequential "closure-key-normalization preserves a string entry label"
    (expect (closure-sharing-key "L0" '((y . r2) (x . r1)))
            :to-equal '("L0" (x y))))

  (it-sequential "group-shareable-closures groups string labels and capture sets"
    (let* ((d1 (list :entry-label "L0" :captured-vars '((x . r1) (y . r2))))
           (d2 (list :entry-label "L0" :captured-vars '((y . r8) (x . r7))))
           (d3 (list :entry-label "L1" :captured-vars '((x . r3) (y . r4))))
           (groups (group-shareable-closures (list d1 d2 d3))))
      (expect (hash-table-count groups) :to-equal 1)
      (expect (gethash '("L0" (x y)) groups) :to-equal (list d1 d2))))))
