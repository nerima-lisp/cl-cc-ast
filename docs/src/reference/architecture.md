# Architecture

## Position in the org

`cl-cc-ast` is layer L3 (domain) at depth 0 in the org's
[dependency policy](https://github.com/nerima-lisp/.github/blob/main/DEPENDENCY_POLICY.md):
it is a domain-specific system with no dependency on any other system in the
org, and nothing it can depend on would be lower. `cl-cc-type` depends on it,
and `cl-cc` depends on both.

Depth 0 is not an accident of the split. It is the property that makes the
system testable on its own: a change here is verified without building the
compiler around it, which is what allowed the extraction from the `cl-cc`
monorepo to happen first.

## The four source files

`src/` is flat, and load order is `:serial t`, so the list is also the
dependency order.

| File | Owns |
|---|---|
| `package.lisp` | The `:cl-cc/ast` package and its export list |
| `ast.lisp` | Every node `defstruct`, plus the `define-ast-nodes` macro that generates them |
| `ast-functions.lisp` | `ast-children`, `ast-bound-names`, CPS traversal, source locations, the error condition |
| `closure.lisp` | Free variable, mutation, capture and escape analysis |
| `ast-roundtrip.lisp` | `ast-to-sexp` and its per-node methods |

The split is by concern rather than by node kind, and the direction of the
arrows is one-way: `ast.lisp` knows nothing about traversal, `ast-functions.lisp`
knows nothing about closures, and `closure.lisp` reaches the tree only through
`ast-children` and `ast-bound-names`.

## Why the traversal primitive is CPS

`ast-search-cps` drives its outcome through two continuations instead of a
return value. It could have been a loop with a mutable "found" flag, or a
recursive function returning the match or `nil`.

The reason it is not is backtracking. Each recursive step builds a new
`failure` continuation that resumes the search at the next sibling, so
"exhausted this subtree, try the next one" is ordinary function composition
rather than state a caller has to unwind by hand. The escape analysis in
`closure.lisp` (`%escape-mentions-node-p`) is built directly on this.

`ast-find-first` then recovers the plain return-value interface in a single
line, for the majority of callers who only want the answer. Having the general
form underneath and the convenience on top costs nothing and means the
convenient version does not have to be re-derived when a caller does need
control.

## Why round-tripping is not generic over `ast-children`

Every other traversal in the system is written against `ast-children`, and
`ast-to-sexp` deliberately is not: it is a `defgeneric` with one `defmethod`
per node type.

Printing needs each form's concrete syntax — where the bindings go in a `let`,
how a lambda list reassembles from four separate slots, which `defclass`
options are present. There is no generic shape to exploit, so a generic walk
would only hide the per-node knowledge inside one large `typecase`.

The dispatch also fails usefully. A new node type with no `ast-to-sexp` method
signals `no-applicable-method` the first time it is printed, rather than
producing a plausible-looking but wrong tree.

## Testing and the coverage floor

Tests live in `t/` and run under
[cl-weave](https://github.com/nerima-lisp/cl-weave), the org's test framework.
`nix flake check` runs four checks: the suite (`checks.default`), the SB-COVER
floor (`checks.coverage`), Nix formatting (`checks.formatting`), and this docs
site built with `mkdocs --strict` (`checks.docs`).

The coverage floor is 99% expression and 99% branch, measured over
`ast-functions.lisp`, `ast-roundtrip.lisp` and `closure.lisp` only. `ast.lisp`
and `package.lisp` are reported but not gated: they are ~40 `defstruct` forms
and one `defpackage`, whose slot default-value forms SB-COVER counts as
coverable expressions but which are evaluated only at a construction that
omits the slot. That was checked empirically rather than assumed — calling
every constructor with zero arguments does not move the number, and
`(optimize (debug 3))` does not either. Gating on them would make the
threshold unreachable no matter how good the tests were.
