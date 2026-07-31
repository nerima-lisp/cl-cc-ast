;;;; compile/closure.lisp - Closure and Free Variable Analysis
(in-package :cl-cc/ast)

(defun find-mutated-variables (ast &optional (k #'identity))
  "Call (FUNCALL K result) with all variable names that are targets of SETQ in
AST. Uses ast-children for generic traversal — new node types work
automatically. K defaults to #'IDENTITY, so an ordinary direct-style call
(FIND-MUTATED-VARIABLES ast) still returns the result as a value; a caller
that wants control over what happens next passes its own continuation, in the
same style AST-SEARCH-CPS does for tree search."
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
  "Call (FUNCALL K result) with the variables from PARAMS that FORM's own
closure boundaries capture, or that recursing into FORM's children captures
transitively. One clause of FIND-CAPTURED-IN-CHILDREN's per-form logic,
factored out so that function reads as a CPS fold over BODY-FORMS rather than
a mutable accumulator threaded through a TYPECASE. K defaults to #'IDENTITY
for ordinary direct-style calls."
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
  "Call (FUNCALL K result) with the variables that inner lambdas/defuns in
BODY-FORMS capture as free variables. PARAMS are the current scope's bound
variables — only those are candidates for boxing. Uses ast-children for
generic traversal. K defaults to #'IDENTITY, so an ordinary direct-style call
(FIND-CAPTURED-IN-CHILDREN body-forms params) still returns the result as a
value."
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
  "Return T if any form in FORMS references BINDING-NAME."
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
unknown callee. Named and factored out of %ESCAPE-CLASSIFY so the data this
clause matches against is legible independent of the escape-classification
logic built on top of it.")

(defun %escape-classify-call (node binding-name safe-consumers)
  "Classify how BINDING-NAME escapes through the AST-CALL NODE.

Split out of %ESCAPE-CLASSIFY because the call case alone carries three
distinct rules — a declared safe consumer, a known external-call primitive,
or a generic callee — each worth reading as its own COND clause rather than
nested inside a nine-way TYPECASE."
  (let ((func (ast-call-func node))
        (args (ast-call-args node)))
    (cond
      ((and (symbolp func) (member (symbol-name func) safe-consumers :test #'string=))
       nil)
      ((and (symbolp func)
            (member (symbol-name func) +external-call-primitive-names+ :test #'string=))
       (%escape-add-kind :external-call
                         (reduce #'%escape-merge-kinds
                                 (mapcar (lambda (a)
                                           (%escape-classify a binding-name safe-consumers))
                                         args)
                                 :initial-value nil)))
      (t
       (let ((arg-kinds (reduce #'%escape-merge-kinds
                                (mapcar (lambda (a)
                                          (%escape-classify a binding-name safe-consumers))
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
  "Classify how BINDING-NAME escapes through NODE."
  (typecase node
    (ast-var        (when (eq (ast-var-name node) binding-name) (list :return)))
    (ast-lambda     (%escape-capture-kinds (ast-lambda-body node)    binding-name safe-consumers))
    (ast-defun      (%escape-capture-kinds (ast-defun-body node)     binding-name safe-consumers))
    (ast-defmethod  (%escape-capture-kinds (ast-defmethod-body node) binding-name safe-consumers))
    (ast-local-fns  (%escape-capture-kinds (ast-local-fns-body node) binding-name safe-consumers))
    (ast-apply
     (%escape-add-kind :external-call
                       (%escape-classify-children node binding-name safe-consumers)))
    (ast-call
     (%escape-classify-call node binding-name safe-consumers))
    (t (%escape-classify-children node binding-name safe-consumers))))

(defun binding-escape-kinds-in-body (body-forms binding-name &key (safe-consumers nil))
  "Return a list of conservative escape kinds for BINDING-NAME in BODY-FORMS.

Escape modes:
- :return         the binding flows out as a direct value/result
- :capture        the binding is captured by an inner closure/local function
- :external-call  the binding is passed to APPLY/FUNCALL or an unknown callee

SAFE-CONSUMERS is a list of uppercase function names that may consume the
binding without constituting an escape."
  (when (listp body-forms)
    (reduce #'%escape-merge-kinds
            (mapcar (lambda (f) (%escape-classify f binding-name safe-consumers))
                    body-forms)
            :initial-value nil)))

(defun binding-escapes-in-body-p (body-forms binding-name &key (safe-consumers nil))
  "Return T when BINDING-NAME escapes from BODY-FORMS.

This is a conservative intra-procedural escape analysis helper layered on top
of BINDING-ESCAPE-KINDS-IN-BODY. SAFE-CONSUMERS is a list of uppercase
function names that are allowed to consume the binding without causing escape."
  (not (null (binding-escape-kinds-in-body body-forms binding-name
                                           :safe-consumers safe-consumers))))

(defun closure-capture-key (captured-vars)
  "Return a canonical key for CAPTURED-VARS.

CAPTURED-VARS is an alist of (var . reg). The key ignores order and groups by
captured variable names only, which is enough to detect sibling closures that
could share one environment record."
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
  "Group ITEMS into an EQUAL hash-table keyed by (FUNCALL KEY-FN item),
preserving each group's original relative order. Keys with only one member
are omitted, since a group of one shares nothing with anything else.

Shared by GROUP-SHARED-SIBLING-CAPTURES and GROUP-SHAREABLE-CLOSURES, whose
grouping logic was otherwise identical apart from the key each computes per
item — paredit's similarity scan flagged the two MAPHASH bodies as an exact
(similarity 1.0) clone."
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
  "Count direct AST-CALL occurrences of BINDING-NAME in NODE tree."
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
  "Count direct AST-CALL occurrences of BINDING-NAME in BODY-FORMS."
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
