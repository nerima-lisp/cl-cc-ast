# API reference

Everything below is exported from `:cl-cc/ast`. Node structures follow
`defstruct` convention throughout: a node kind `ast-foo` gives you
`make-ast-foo`, `ast-foo-p`, and one accessor per slot, all exported.

## Data protocol

These two are the structural interface. Write passes against them, not against
your own `typecase`.

### `ast-children`

```lisp
(ast-children node) => list
```

A flat list of `node`'s child sub-expressions. Leaves (`ast-int`, `ast-var`,
`ast-hole`, `ast-quote`, `ast-function`, `ast-go`) return `nil`. This function
is the single source of truth for AST shape.

### `ast-bound-names`

```lisp
(ast-bound-names node) => list of symbols
```

The variable names `node` newly binds. Meaningful for `ast-let`, `ast-lambda`,
`ast-defun`, `ast-local-fns` (so `ast-flet` and `ast-labels`) and
`ast-multiple-value-bind`; `nil` for everything else. For callables the list
covers required, optional, rest and keyword parameters.

## Traversal

### `ast-search-cps`

```lisp
(ast-search-cps node predicate success failure) => whatever a continuation returns
```

Depth-first search over `node` and its `ast-children` descendants. Calls
`(funcall success match)` on the first node satisfying `predicate`; calls
`(funcall failure)` with no arguments once the subtree is exhausted. Each
recursive step wraps `failure` in a continuation that resumes at the next
sibling, so backtracking is function composition rather than mutable loop
state.

### `ast-find-first`

```lisp
(ast-find-first node predicate) => node or nil
```

`ast-search-cps` with `#'identity` as `success` and `(constantly nil)` as
`failure`. Use it when you want an answer rather than control over the search.

## Closure and escape analysis

| Name | Signature | Returns |
|---|---|---|
| `find-free-variables` | `(ast)` | Variables referenced but not bound in `ast` |
| `free-vars-of-list` | `(nodes)` | Union of `find-free-variables` over a list |
| `free-vars-of-defaults` | `(param-list)` | Free variables in optional/keyword default forms |
| `find-mutated-variables` | `(ast)` | Variables that are `setq` targets |
| `mutated-vars-of-list` | `(nodes)` | Union of `find-mutated-variables` over a list |
| `find-captured-in-children` | `(body-forms params)` | Which of `params` an inner closure captures |

### `binding-escape-kinds-in-body`

```lisp
(binding-escape-kinds-in-body body-forms binding-name &key safe-consumers) => list
```

Conservative, intra-procedural escape analysis. Returns some subset of:

| Kind | Meaning |
|---|---|
| `:return` | The binding flows out as a direct value or result |
| `:capture` | An inner closure or local function captures it |
| `:external-call` | It is passed to `apply`, `funcall`, or an unknown callee |

`safe-consumers` is a list of uppercase function-name strings that may consume
the binding without that counting as an escape.

### `binding-escapes-in-body-p`

```lisp
(binding-escapes-in-body-p body-forms binding-name &key safe-consumers) => boolean
```

True when `binding-escape-kinds-in-body` returns anything at all.

### `binding-direct-call-count-in-body`

```lisp
(binding-direct-call-count-in-body body-forms binding-name) => integer
```

How many times `binding-name` appears as the *callee* of a call in
`body-forms`. Accepts a single node as well as a list.

### `binding-one-shot-p`

```lisp
(binding-one-shot-p body-forms binding-name &key safe-consumers) => boolean
```

True when the binding is called exactly once and escapes nowhere — the
condition under which it can be inlined rather than allocated.

## Environment and closure sharing

### `trim-captured-vars`

```lisp
(trim-captured-vars captured-vars required-vars) => alist
```

Filters an alist of `(var . register)` candidates down to `required-vars`,
keeping the first occurrence of each variable so shadowing preserves the
innermost binding.

### `closure-capture-key`

```lisp
(closure-capture-key captured-vars) => sorted list of symbols
```

Canonical key for a capture set: variable names only, sorted, duplicate-free.
Two closures with the same key capture the same variables.

### `closure-sharing-key`

```lisp
(closure-sharing-key entry-label captured-vars) => (entry-label capture-key)
```

### `group-shared-sibling-captures`

```lisp
(group-shared-sibling-captures captured-var-lists) => equal hash-table
```

Maps `closure-capture-key` to the list of capture alists using it. Singleton
groups are omitted, since a group of one shares nothing.

### `group-shareable-closures`

```lisp
(group-shareable-closures closure-descriptors) => equal hash-table
```

Same, keyed on `closure-sharing-key`. Each descriptor is a plist with at least
`:entry-label` and `:captured-vars`. Singleton groups are omitted.

## Round-trip

### `ast-to-sexp`

```lisp
(ast-to-sexp node) => s-expression
```

Generic function with one method per node type, rendering a tree back as
readable source. Intended for debugging and diagnostics. A node type with no
method signals `no-applicable-method` rather than printing a partial tree.

### `slot-def-to-sexp`

```lisp
(slot-def-to-sexp slot) => s-expression
```

Renders an `ast-slot-def` as a `defclass` slot specification.

## Source locations and errors

| Name | Kind | Notes |
|---|---|---|
| `ast-location-string` | function | `"file:line:column"`, degrading to `"file:line"`, `"file"`, then `"<unknown location>"` |
| `ast-compilation-error` | condition | Subtype of `error`; its report prefixes the location |
| `ast-error` | function | `(ast-error node format-control &rest args)`; signals the above |
| `ast-error-location` | reader | |
| `ast-error-format-control` | reader | |
| `ast-error-format-arguments` | reader | |

## Node kinds

`ast-node` is the base structure. Its `:conc-name` is `ast-`, so its own slots
read `ast-source-file`, `ast-source-line`, `ast-source-column`,
`ast-namespace`, `ast-imports`.

| Group | Node kinds |
|---|---|
| Intermediate | `ast-callable`, `ast-local-fns` |
| Literals and references | `ast-int`, `ast-var`, `ast-hole`, `ast-quote`, `ast-list` |
| Expressions | `ast-binop`, `ast-if`, `ast-progn`, `ast-print`, `ast-the` |
| Binding | `ast-let`, `ast-setq` |
| Functions | `ast-lambda`, `ast-function`, `ast-flet`, `ast-labels`, `ast-defun`, `ast-defvar`, `ast-defmacro` |
| Calls | `ast-call`, `ast-apply` |
| Control flow | `ast-block`, `ast-return-from`, `ast-tagbody`, `ast-go` |
| Multiple values | `ast-values`, `ast-multiple-value-call`, `ast-multiple-value-prog1`, `ast-multiple-value-bind` |
| Conditions | `ast-catch`, `ast-throw`, `ast-unwind-protect`, `ast-handler-case` |
| CLOS | `ast-defclass`, `ast-slot-def`, `ast-defgeneric`, `ast-defmethod`, `ast-make-instance`, `ast-slot-value`, `ast-set-slot-value`, `ast-set-gethash` |

Some accessors are abbreviated where the full name would be unwieldy:
`ast-multiple-value-bind` uses `ast-mvb-vars`, `ast-mvb-values-form` and
`ast-mvb-body`; `ast-multiple-value-call` uses `ast-mv-call-func` and
`ast-mv-call-args`; `ast-multiple-value-prog1` uses `ast-mv-prog1-first` and
`ast-mv-prog1-forms`. `ast-unwind-protect` reads as `ast-unwind-protected` and
`ast-unwind-cleanup`.
