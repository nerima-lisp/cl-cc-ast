# API reference

Feature packages named in the [Glossary](glossary.md) own these symbols; the
`:cl-cc/ast` facade imports and reexports the same public symbols. Everything
below is available from `:cl-cc/ast`. Node structures follow `defstruct`
convention throughout: a node kind `ast-foo` gives you
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
(ast-bound-names node) => list of binding names
```

The names `node` newly binds. Variable-binding forms return symbols.
`ast-flet` and `ast-labels` return local function names, which may include
`(cl:setf symbol)`. Meaningful for `ast-let`, `ast-lambda`, `ast-defun`,
`ast-local-fns` and `ast-multiple-value-bind`; `nil` for everything else.
For callables the list covers required, optional, rest and keyword parameters.

## Traversal

### `ast-search-cps`

```lisp
(ast-search-cps node predicate success failure) => whatever a continuation returns
```

Depth-first search over `node` and its `ast-children` descendants. Calls
`(funcall success match)` on the first node satisfying `predicate`; calls
`(funcall failure)` with no arguments once the subtree is exhausted. Each
recursive step wraps `failure` in a continuation that resumes at the next
sibling.

### `ast-find-first`

```lisp
(ast-find-first node predicate) => node or nil
```

`ast-search-cps` with `#'identity` as `success` and `(constantly nil)` as
`failure`. Use it when you want an answer rather than control over the search.

## Closure and escape analysis

| Name | Signature | Returns |
|---|---|---|
| `find-free-variables` | `(ast &optional k)` | Variables referenced but not bound in `ast` |
| `free-vars-of-list` | `(nodes &optional k)` | Union of `find-free-variables` over a list |
| `free-vars-of-defaults` | `(param-list)` | Free variables in optional/keyword default forms |
| `find-mutated-variables` | `(ast &optional k)` | Variables that are `setq` targets |
| `mutated-vars-of-list` | `(nodes &optional k)` | Union of `find-mutated-variables` over a list |
| `find-captured-in-children` | `(body-forms params &optional k)` | Which of `params` are captured by inner lambdas, defuns, or local functions in `flet`/`labels` |

The optional `k` argument defaults to `#'identity`. When supplied, the function
calls `k` with the computed result and returns whatever `k` returns.

### `binding-escape-kinds-in-body`

```lisp
(binding-escape-kinds-in-body body-forms binding-name &key safe-consumers) => list
```

Conservative, intra-procedural analysis of AST uses. Returns some subset of
escape tags; they do not prove a runtime escape:

| Kind | Meaning |
|---|---|
| `:return` | A variable node naming the binding was visited; this is not a control-flow return. |
| `:capture` | An inner `lambda`, `defun`, or `defmethod` body, or a `flet`/`labels` body or local-function definition, refers to the binding. |
| `:external-call` | Every explicit `ast-apply` adds this tag. An `ast-call` to `apply` or `funcall` adds it unless that operator is in `safe-consumers`; other non-safe calls add it when an argument contains a tagged use. |

`safe-consumers` accepts symbols matched by identity and strings matched exactly
against the operator's symbol name (normally uppercase for unescaped Common Lisp
symbols). A matching direct variable argument receives no tag; nested
expressions in other arguments are still analyzed.
For `ast-call` nodes, this check runs before the `apply` and `funcall` rule, so
listing either operator can suppress `:external-call` for a skipped direct
argument. It does not suppress the tag added by an explicit `ast-apply` node.
The list is ignored in a `flet` or `labels` body and in their local-function
definitions.

### `binding-escapes-in-body-p`

```lisp
(binding-escapes-in-body-p body-forms binding-name &key safe-consumers) => boolean
```

True when `binding-escape-kinds-in-body` returns anything at all.

### `binding-direct-call-count-in-body`

```lisp
(binding-direct-call-count-in-body body-forms binding-name) => integer
```

Counts `ast-call` nodes whose function slot is `binding-name`. It recurses
through non-call node children and each `ast-call`'s arguments, but not an
AST-valued function slot. An `ast-apply` node itself does not count, although
its children are traversed. `BODY-FORMS` must be a list; non-list values return
zero.

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
keeping the first occurrence of each required variable. The input alist must
list the innermost binding first.

### `closure-capture-key`

```lisp
(closure-capture-key captured-vars) => list of symbols, sorted by name
```

Returns the captured symbols sorted by `symbol-name`, removing duplicates by
symbol identity. Distinct symbols with the same name remain separate, but their
relative order is unspecified. Capture sets containing same-named symbols from
different packages may therefore produce different keys when their input order
differs.

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

### Function definition names

`make-ast-defun` and `(setf ast-defun-name)` accept a symbol or a proper
two-element list `(cl:setf symbol)`. The constructor and accessor retain the
original name object, including uninterned symbols. `ast-to-sexp` uses that
same name object when rendering a `defun` form.

Malformed lists, non-symbol accessor names, and symbols merely named `SETF`
from another package are not function names and signal `type-error`.

Some accessors are abbreviated where the full name would be unwieldy:
`ast-multiple-value-bind` uses `ast-mvb-vars`, `ast-mvb-values-form` and
`ast-mvb-body`; `ast-multiple-value-call` uses `ast-mv-call-func` and
`ast-mv-call-args`; `ast-multiple-value-prog1` uses `ast-mv-prog1-first` and
`ast-mv-prog1-forms`. `ast-unwind-protect` reads as `ast-unwind-protected` and
`ast-unwind-cleanup`.
