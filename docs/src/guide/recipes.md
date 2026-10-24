# Recipes

After making the system available to ASDF (see [Getting started](../getting-started.md)),
run this setup once before using the examples below:

```lisp
(asdf:load-system "cl-cc-ast")
(use-package :cl-cc/ast)
```

## Walk a tree without knowing its shape

`ast-children` is the only structural knowledge you need. A whole-tree fold
looks like this:

```lisp
(defun count-nodes (node)
  (1+ (reduce #'+ (mapcar #'count-nodes (ast-children node)) :initial-value 0)))

(count-nodes (make-ast-binop :op '+
                             :lhs (make-ast-int :value 1)
                             :rhs (make-ast-int :value 2)))
;; => 3
```

## Find the first node matching a predicate

`ast-find-first` is the direct-style search: it returns the match or `nil`.

```lisp
(ast-find-first (make-ast-progn
                 :forms (list (make-ast-int :value 1)
                              (make-ast-var :name 'target)))
                #'ast-var-p)
;; => the AST-VAR node named TARGET
```

When you need control over what happens on failure — resuming a different
search, or accumulating rather than returning — use `ast-search-cps` directly
and pass your own success and failure continuations. `ast-find-first` is
nothing more than `ast-search-cps` with `#'identity` and `(constantly nil)`.

## Decide what a closure must capture

Free-variable analysis answers "what does this body need from outside?".

```lisp
(find-free-variables
 (make-ast-lambda :params '(x)
                  :body (list (make-ast-binop :op '+
                                              :lhs (make-ast-var :name 'x)
                                              :rhs (make-ast-var :name 'y)))))
;; => (Y)
```

`x` is a parameter, so it is bound; `y` is not, so a closure over this lambda
has to capture it.

## Trim an environment down to what is actually used

Compiler environments accumulate candidate bindings. `trim-captured-vars`
filters an `(var . register)` alist against the set free-variable analysis
says is required. The input alist must list the innermost binding first; the
function keeps the first occurrence of each required variable:

```lisp
(trim-captured-vars '((a . r1) (b . r2) (a . r3)) '(a))
;; => ((A . R1))
```

## Detect closures that can share an environment

Two sibling closures whose `closure-capture-key` values match can share one
environment record. `closure-capture-key` sorts captured symbols by name and
removes duplicate symbols. `group-shared-sibling-captures` buckets by that key,
dropping singleton groups because a group of one shares nothing. Same-named
symbols from different packages may not produce the same key after reordering;
see the [API reference](../reference/api.md#closure-capture-key):

```lisp
(closure-capture-key '((b . r2) (a . r1) (a . r3)))
;; => (A B)
```

`group-shareable-closures` is the same idea one step further: it groups
closure descriptors that agree on *both* `:entry-label` and capture set, which
means they can be one closure object rather than two.

## Ask whether a binding escapes

```lisp
(binding-escapes-in-body-p
 (list (make-ast-call :func 'funcall :args (list (make-ast-var :name 'f))))
 'f)
;; => T
```

The predicate is true because `f` is passed directly to `funcall`. See the
[API reference](../reference/api.md#binding-escape-kinds-in-body) for the
escape tags and `safe-consumers` rules.

## Print a tree back as source

```lisp
(ast-to-sexp (make-ast-if :cond (make-ast-var :name 'p)
                          :then (make-ast-int :value 1)
                          :else (make-ast-int :value 2)))
;; => (IF P 1 2)
```

This is for debugging and error messages, not for re-parsing: it is a
faithful rendering of the tree, not a guarantee of a fixed point through the
reader.

## Report an error with source context

```lisp
(handler-case
    (ast-error (make-ast-var :name 'x :source-file "a.lisp" :source-line 12)
               "unbound variable ~A" 'x)
  (ast-compilation-error (e)
    (princ-to-string e)))
;; => "Compilation error at a.lisp:12: unbound variable X"
```

`ast-error` signals `ast-compilation-error`, whose report prepends
`ast-location-string` of the offending node. Use it rather than plain `error`
in a pass, so the message keeps saying where in the *user's* source the
problem is.
