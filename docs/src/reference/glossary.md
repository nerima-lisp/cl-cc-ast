# Glossary

## nodes

- Definition: An abstract syntax tree (AST) node model and operations to inspect child nodes, find bound names, and convert nodes back to S-expressions for debugging and pretty-printing. A binding form introduces names that its body can refer to; examples include `let` variables, lambda parameters, and local functions. `flet` does not make its local function names visible in their definitions; `labels` does, so its functions can call themselves or one another. The `ast-callable` base type supplies parameter and body slots to `lambda` and `defun` nodes. The `ast-local-fns` base type supplies bindings and body slots to `flet` and `labels`.
- Package: `cl-cc/ast/nodes`
- Key types: `ast-node`, `ast-callable`, `ast-local-fns`, `ast-flet`, `ast-labels`
- Key functions: `make-ast-node`, `ast-children`, `ast-bound-names`, `ast-to-sexp`
- Other contexts: None.

## closure-analysis

- Definition: Analyzes binding use for mutation, free-variable references, and closure escape tags. It also groups compatible closure descriptors for sharing.
- Package: `cl-cc/ast/closure-analysis`
- Key types: None.
- Key functions: `find-mutated-variables`, `find-free-variables`, `binding-escape-kinds-in-body`, `group-shareable-closures`
- Other contexts: None.
