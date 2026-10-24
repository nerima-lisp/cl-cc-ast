;;;; Closure and Free Variable Analysis
(in-package :cl-cc/ast/closure-analysis)

(defun find-mutated-variables (ast &optional (k #'identity))
  "Call (FUNCALL K result) with every variable name that appears as a SETQ
target in AST. The analysis descends through ast-children, so add an
ast-children clause for new node types whose descendants it should visit.
K defaults to the identity function, so direct-style calls return the result."
  (if (typep ast 'ast-setq)
      (mutated-vars-of-list
       (ast-children ast)
       (lambda (children-mutated)
         (funcall k (union (list (ast-setq-var ast)) children-mutated))))
      (mutated-vars-of-list (ast-children ast) k)))

(defun mutated-vars-of-list (nodes &optional (k #'identity))
  "Call (FUNCALL K result) with the union of setq-mutation targets across all
AST NODES in a list. K defaults to #'IDENTITY for ordinary direct-style calls."
  (if (null nodes)
      (funcall k nil)
      (find-mutated-variables
       (first nodes)
       (lambda (first-mutated)
         (mutated-vars-of-list
          (rest nodes)
          (lambda (rest-mutated)
            (funcall k (union first-mutated rest-mutated))))))))

(defun %local-fns-captured-bindings (form params)
  "Union, over every binding in the AST-LOCAL-FNS FORM, of the PARAMS its own
body captures as a pseudo-lambda closure boundary."
  (reduce #'union
          (mapcar (lambda (binding)
                    (let ((pseudo (make-ast-lambda :params (second binding)
                                                   :body (cddr binding))))
                      (intersection (find-free-variables pseudo) params)))
                  (ast-local-fns-bindings form))
          :initial-value nil))

(defun %captured-in-form (form params &optional (k #'identity))
  "Call (FUNCALL K result) with the variables from PARAMS that closure
boundaries in FORM capture, including captures found while recursing through
FORM children. K defaults to the IDENTITY function for direct-style calls."
  (typecase form
    ;; Lambda/defun boundaries: capture free vars that overlap with PARAMS.
    ;; ast-lambda and ast-defun are both ast-callable, so FIND-FREE-VARIABLES'
    ;; own ast-callable clause already handles either concrete type directly.
    (ast-callable (funcall k (intersection (find-free-variables form) params)))
    ;; labels/flet: each binding body is a closure boundary
    (ast-local-fns
     (find-captured-in-children
      (ast-local-fns-body form) params
      (lambda (body-captured)
        (funcall k (union (%local-fns-captured-bindings form params) body-captured)))))
    ;; All other compound forms: recurse via ast-children
    (t (find-captured-in-children (ast-children form) params k))))

(defun find-captured-in-children (body-forms params &optional (k #'identity))
  "Call (FUNCALL K result) with PARAMS variables captured by inner lambda and
defun nodes or local-function definitions in FLET and LABELS forms. Uses
ast-children for generic traversal. K defaults to the identity function for
direct-style calls."
  (if (null body-forms)
      (funcall k nil)
      (%captured-in-form
       (first body-forms) params
       (lambda (first-captured)
         (find-captured-in-children
          (rest body-forms) params
          (lambda (rest-captured)
            (funcall k (union first-captured rest-captured))))))))

(defun free-vars-of-list (nodes &optional (k #'identity))
  "Call (FUNCALL K result) with the union of free variables across all AST
NODES in a list. K defaults to #'IDENTITY for ordinary direct-style calls."
  (if (null nodes)
      (funcall k nil)
      (find-free-variables
       (first nodes)
       (lambda (first-free)
         (free-vars-of-list
          (rest nodes)
          (lambda (rest-free)
            (funcall k (union first-free rest-free))))))))

(defun free-vars-of-defaults (param-list)
  "Union of free variables in the default expressions of an optional/key PARAM-LIST.
Each entry is (name default-ast); entries with no default contribute nothing."
  (free-vars-of-list (remove nil (mapcar #'second param-list))))

(defun %free-vars-of-let (ast)
  "Free variables of an AST-LET: binding init-exprs plus body, minus AST's own
bound names."
  (let ((binding-free (free-vars-of-list (mapcar #'cdr (ast-let-bindings ast))))
        (body-free    (free-vars-of-list (ast-let-body ast))))
    (set-difference (union binding-free body-free) (ast-bound-names ast))))

(defun %free-vars-of-callable (ast)
  "Free variables of an AST-CALLABLE (ast-lambda or ast-defun, sharing this one
clause via their common accessors): body plus optional/key default
expressions, minus AST's own bound names."
  (let ((body-free    (free-vars-of-list (ast-callable-body ast)))
        (default-free (union (free-vars-of-defaults (ast-callable-optional-params ast))
                             (free-vars-of-defaults (ast-callable-key-params ast)))))
    (set-difference (union body-free default-free) (ast-bound-names ast))))

(defun %free-vars-of-local-fns (ast)
  "Free variables of an AST-LOCAL-FNS (ast-flet or ast-labels): every binding's
own body free variables, plus the outer body, minus AST's own bound names."
  (let ((binding-free (free-vars-of-list
                       (mapcar (lambda (b)
                                 (make-ast-lambda :params (second b) :body (cddr b)))
                               (ast-local-fns-bindings ast))))
        (body-free (free-vars-of-list (ast-local-fns-body ast))))
    (set-difference (union binding-free body-free) (ast-bound-names ast))))

(defun %free-vars-of-mvb (ast)
  "Free variables of an AST-MULTIPLE-VALUE-BIND: the values-form plus body,
minus AST's own bound names."
  (set-difference (union (find-free-variables (ast-mvb-values-form ast))
                         (free-vars-of-list (ast-mvb-body ast)))
                 (ast-bound-names ast)))

(defun find-free-variables (ast &optional (k #'identity))
  "Call (FUNCALL K result) with all free variables in AST that would need to
be captured in a closure. Binding forms use ast-bound-names; others fall
through to ast-children. Each binding form's own free-variable rule is a
%FREE-VARS-OF-* helper above, so this dispatch stays a one-clause-per-kind
table rather than growing a nested LET inside every TYPECASE arm. K defaults
to #'IDENTITY, so an ordinary direct-style call (FIND-FREE-VARIABLES ast)
still returns the result as a value, in the same style AST-SEARCH-CPS uses
for tree search."
  (typecase ast
    ;; Leaves
    (ast-var (funcall k (list (ast-var-name ast))))
    ;; Assignment: the var itself is free (it must exist in some enclosing scope)
    (ast-setq
     (find-free-variables
      (ast-setq-value ast)
      (lambda (value-free)
        (funcall k (union (list (ast-setq-var ast)) value-free)))))
    ;; Binding forms: recurse into children, subtract bound names
    (ast-let (funcall k (%free-vars-of-let ast)))
    (ast-callable (funcall k (%free-vars-of-callable ast)))
    (ast-local-fns (funcall k (%free-vars-of-local-fns ast)))
    (ast-multiple-value-bind (funcall k (%free-vars-of-mvb ast)))
    ;; All other nodes: generic traversal via ast-children
    (t (free-vars-of-list (ast-children ast) k))))

(defun %escape-add-kind (kind acc)
  "Return ACC with KIND added unless already present."
  (if (member kind acc) acc (cons kind acc)))

(defun %escape-merge-kinds (&rest kind-lists)
  "Merge multiple escape-kind lists into one deduplicated list."
  (reduce (lambda (acc ks)
            (reduce (lambda (a k) (%escape-add-kind k a)) ks :initial-value acc))
          kind-lists :initial-value nil))

(defun %escape-mentions-node-p (node binding-name)
  "Return T if NODE or any descendant references BINDING-NAME.

Driven by AST-SEARCH-CPS: the SUCCESS continuation fires on the first
AST-VAR matching BINDING-NAME, and the FAILURE continuation — reached once
every descendant has been tried — is what makes a non-mention NIL."
  (ast-search-cps node
                  (lambda (n) (and (typep n 'ast-var) (eq (ast-var-name n) binding-name)))
                  (lambda (n) (declare (ignore n)) t)
                  (lambda () nil)))

(defun %escape-mentions-forms-p (forms binding-name)
  (some (lambda (f) (%escape-mentions-node-p f binding-name)) forms))

(defun %escape-classify-children (node binding-name safe-consumers)
  "Merge escape kinds for all children of NODE."
  (reduce #'%escape-merge-kinds
          (mapcar (lambda (c) (%escape-classify c binding-name safe-consumers))
                  (ast-children node))
          :initial-value nil))

(defun %escape-capture-kinds (body binding-name safe-consumers)
  "Escape kinds when BODY is a closure boundary over BINDING-NAME."
  (%escape-merge-kinds
   (when (%escape-mentions-forms-p body binding-name) (list :capture))
   (reduce #'%escape-merge-kinds
           (mapcar (lambda (f) (%escape-classify f binding-name safe-consumers)) body)
           :initial-value nil)))

(defparameter +external-call-primitive-names+ '("APPLY" "FUNCALL")
  "Uppercase names of call operators that pass their arguments to an
unknown callee.")

(defun %escape-classify-call (node binding-name safe-consumers)
  "Classify escapes through NODE. Safe consumers suppress direct references only."
  (let ((func (ast-call-func node))
        (args (ast-call-args node)))
    (cond
      ((and (symbolp func)
            (some (lambda (consumer)
                    (if (stringp consumer)
                        (string= (symbol-name func) consumer)
                        (eq func consumer)))
                  safe-consumers))
       (reduce #'%escape-merge-kinds
               (mapcar (lambda (arg)
                         (if (and (typep arg 'ast-var)
                                  (eq (ast-var-name arg) binding-name))
                             nil
                             (%escape-classify arg binding-name safe-consumers)))
                       args)
               :initial-value nil))
      ((and (symbolp func)
            (member (symbol-name func) +external-call-primitive-names+ :test #'string=))
       (%escape-add-kind :external-call
                         (reduce #'%escape-merge-kinds
                                 (mapcar (lambda (arg)
                                           (%escape-classify arg binding-name safe-consumers))
                                         args)
                                 :initial-value nil)))
      (t
       (let ((arg-kinds (reduce #'%escape-merge-kinds
                                (mapcar (lambda (arg)
                                          (%escape-classify arg binding-name safe-consumers))
                                        args)
                                :initial-value nil)))
         (if arg-kinds
             (%escape-add-kind :external-call
                               (%escape-merge-kinds
                                (when (typep func 'ast-node)
                                  (%escape-classify func binding-name safe-consumers))
                                arg-kinds))
             (when (typep func 'ast-node) (%escape-classify func binding-name safe-consumers))))))))

(defun %escape-classify (node binding-name safe-consumers)
  (typecase node
    (ast-var        (when (eq (ast-var-name node) binding-name) (list :return)))
    (ast-lambda     (%escape-capture-kinds (ast-lambda-body node)    binding-name safe-consumers))
    (ast-defun      (%escape-capture-kinds (ast-defun-body node)     binding-name safe-consumers))
    (ast-defmethod  (%escape-capture-kinds (ast-defmethod-body node) binding-name safe-consumers))
    (ast-local-fns
     (%escape-merge-kinds
      (%escape-capture-kinds (ast-local-fns-body node) binding-name nil)
      (when (some (lambda (binding)
                    (%escape-mentions-forms-p (cddr binding) binding-name))
                  (ast-local-fns-bindings node))
        (list :capture))))
    (ast-apply
     (%escape-add-kind :external-call
                       (%escape-classify-children node binding-name safe-consumers)))
    (ast-call
     (%escape-classify-call node binding-name safe-consumers))
    (t (%escape-classify-children node binding-name safe-consumers))))

(defun binding-escape-kinds-in-body (body-forms binding-name &key (safe-consumers nil))
  "Return AST-use tags for BINDING-NAME in BODY-FORMS.

Tags describe conservative structural classifications, not control-flow returns
or proven runtime escapes:
- :return         a variable node naming the binding was visited
- :capture        a reference occurs in an inner closure, a FLET or LABELS body,
                  or their local-function definitions
- :external-call  every AST-APPLY adds this tag; AST-CALL to APPLY/FUNCALL adds
                  it unless that operator is safe; other calls add it when
                  argument analysis finds a tagged use and the callee is not safe

SAFE-CONSUMERS applies to AST-CALL nodes. It accepts symbols matched by identity
and strings matched exactly against an operator symbol name (normally uppercase
for unescaped Common Lisp symbols). A matching call suppresses only a direct
argument that is exactly a variable node naming the binding; nested expressions
in other arguments are still analyzed. An explicit AST-APPLY remains tagged.
The list is ignored in FLET or LABELS bodies and in their local-function
definitions."
  (when (listp body-forms)
    (reduce #'%escape-merge-kinds
            (mapcar (lambda (f) (%escape-classify f binding-name safe-consumers))
                    body-forms)
            :initial-value nil)))

(defun binding-escapes-in-body-p (body-forms binding-name &key (safe-consumers nil))
  "Return T when BINDING-NAME has an AST-use tag in BODY-FORMS.

This conservative intra-procedural helper returns T when
BINDING-ESCAPE-KINDS-IN-BODY returns any tag. The tags describe AST structure
and call classification, and do not prove a runtime escape. SAFE-CONSUMERS
accepts symbols matched by identity and strings matched exactly against an
operator symbol name (normally uppercase for unescaped Common Lisp symbols).
A matching call suppresses only a direct argument that is exactly a variable
node naming the binding; nested expressions in other arguments are still
analyzed. The list is ignored in a FLET or LABELS body and in their
local-function definitions."
  (not (null (binding-escape-kinds-in-body body-forms binding-name
                                           :safe-consumers safe-consumers))))

(defun closure-capture-key (captured-vars)
  "Return captured variable symbols sorted by symbol-name.

CAPTURED-VARS is an alist of (var . reg). Duplicate symbols are removed by
identity. Distinct same-named symbols may appear in either relative order, so
reordering those inputs is not guaranteed to produce an equal key."
  (sort (remove-duplicates (mapcar #'car captured-vars) :test #'eq)
        #'string< :key #'symbol-name))

(defun trim-captured-vars (captured-vars required-vars)
  "Return CAPTURED-VARS filtered to variables listed in REQUIRED-VARS.

CAPTURED-VARS is an alist of (var . reg) candidates from the surrounding
compiler environment. REQUIRED-VARS is the set of variables that the closure
body actually needs according to free-variable analysis. The first occurrence
of each variable is kept so shadowing preserves the innermost environment
binding, and unused environment entries are removed before vm-captured-vars is
emitted."
  (let ((required (let ((table (make-hash-table :test #'eq)))
                     (dolist (var required-vars table)
                       (setf (gethash var table) t))))
        (seen (make-hash-table :test #'eq))
        (trimmed nil))
    (dolist (entry captured-vars (nreverse trimmed))
      (let ((var (car entry)))
        (when (and (gethash var required)
                   (not (gethash var seen)))
          (setf (gethash var seen) t)
          (push entry trimmed))))))

(defun %group-multi-member (items key-fn)
  "Group ITEMS into an EQUAL hash table keyed by (FUNCALL KEY-FN item),
preserving member order. Omit groups with only one member, since they share
nothing.

This helper is shared by GROUP-SHARED-SIBLING-CAPTURES and
GROUP-SHAREABLE-CLOSURES; the callers provide their respective grouping keys."
  (let ((all-groups (make-hash-table :test #'equal))
        (shared-only (make-hash-table :test #'equal)))
    (dolist (item items)
      (push item (gethash (funcall key-fn item) all-groups)))
    (maphash (lambda (key group)
               (when (> (length group) 1)
                 (setf (gethash key shared-only) (nreverse group))))
             all-groups)
    shared-only))

(defun group-shared-sibling-captures (captured-var-lists)
  "Group sibling closure captures that share the same captured variable set.

Returns an EQUAL hash-table mapping canonical capture keys to the list of
captured-var alists using that key. Singleton groups are omitted."
  (%group-multi-member captured-var-lists #'closure-capture-key))

(defun %count-ast-calls (node binding-name)
  "Count AST-CALL nodes with BINDING-NAME in their function slot within NODE.
Recurse through AST children except AST-CALL function slots."
  (typecase node
    (ast-call
     (+ (if (eq (ast-call-func node) binding-name) 1 0)
        (reduce #'+ (mapcar (lambda (n) (%count-ast-calls n binding-name))
                            (ast-call-args node))
                :initial-value 0)))
    (t
     (reduce #'+ (mapcar (lambda (n) (%count-ast-calls n binding-name))
                         (ast-children node))
             :initial-value 0))))

(defun binding-direct-call-count-in-body (body-forms binding-name)
  "Count AST-CALL nodes whose function slot is BINDING-NAME in BODY-FORMS.
Recurse through non-call node children and AST-CALL arguments, but not an
AST-valued function slot."
  (if (listp body-forms)
      (reduce #'+ (mapcar (lambda (n) (%count-ast-calls n binding-name)) body-forms)
              :initial-value 0)
      0))

(defun binding-one-shot-p (body-forms binding-name &key (safe-consumers nil))
  "Return T when BINDING-NAME is a non-escaping direct call used exactly once."
  (and (= 1 (binding-direct-call-count-in-body body-forms binding-name))
       (not (binding-escapes-in-body-p body-forms binding-name
                                       :safe-consumers safe-consumers))))

(defun closure-sharing-key (entry-label captured-vars)
  "Return a canonical sharing key for closures with ENTRY-LABEL and CAPTURED-VARS."
  (list entry-label (closure-capture-key captured-vars)))

(defun group-shareable-closures (closure-descriptors)
  "Group closures that share both code label and capture set.

CLOSURE-DESCRIPTORS is a list of plist-like records containing at least
  :entry-label and :captured-vars.
Singleton groups are omitted."
  (%group-multi-member closure-descriptors
                       (lambda (desc)
                         (closure-sharing-key (getf desc :entry-label)
                                              (getf desc :captured-vars)))))
