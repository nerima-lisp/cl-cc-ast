# Glossary

Each section identifies a feature package and its key types and functions. `Other contexts` lists features that use a term with a different meaning; `None` means no different meaning is used by another feature.

## nodes

- Definition: An abstract syntax tree (AST) node model and the operations that inspect child nodes, find bound names, and serialize nodes. A binding form introduces names that its body can refer to; examples include `let` variables, lambda parameters, and local functions introduced by `flet` or `labels`.
- Package: `cl-cc/ast/nodes`
- Key types: `ast-node`, `ast-callable` (the base type for `lambda` and `defun` nodes, with parameter and body slots), `ast-local-fns` (the base type with `bindings` and `body` slots), `ast-flet` (local functions cannot refer to one another), and `ast-labels` (local functions can refer to one another recursively). Both local-function types inherit `bindings` and `body` from `ast-local-fns`; `bindings` holds the local function definitions and `body` holds the forms that use them.
- Key functions: `make-ast-node`, `ast-children`, `ast-bound-names`, `ast-to-sexp`
- Other contexts: None.

## closure-analysis

- Definition: Analyzes a binding's use across a sequence of body forms for mutation, free-variable references, and conservative escape kinds: direct value/result flow (`:return`), capture by an inner closure or local function (`:capture`), or passage to `APPLY`/`FUNCALL` or an unlisted call target (`:external-call`). The `safe-consumers` argument to `binding-escape-kinds-in-body` lists safe call operators by symbol identity or uppercase name; they suppress a direct argument reference to the binding and are ignored inside local-function scopes. A closure descriptor is a plist-like record for a closure instance. Its `:entry-label` is the generated code entry label, and its `:captured-vars` is an alist of `(variable . register)` entries. `group-shareable-closures` groups descriptors with the same entry label and captured-variable names, ignoring register choices, and omits singleton groups.
- Package: `cl-cc/ast/closure-analysis`
- Key types: None.
- Key functions: `find-mutated-variables`, `find-free-variables`, `binding-escape-kinds-in-body`, `group-shareable-closures`
- Other contexts: None.
