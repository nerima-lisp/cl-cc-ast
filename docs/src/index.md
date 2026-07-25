# cl-cc-ast

`cl-cc-ast` holds the abstract syntax tree of the
[cl-cc](https://github.com/nerima-lisp/cl-cc) Common Lisp compiler: the node
structures, the traversal protocol every later pass is written against, the
closure and escape analysis helpers, and the S-expression round-trip used for
debugging.

It is the dependency-free leaf of the compiler. The system's `:depends-on` is
empty, it targets SBCL, and it deliberately knows nothing about types, code
generation or any particular back end — those live in `cl-cc-type`,
`cl-cc-binary` and the rest of the `cl-cc-*` family, all of which sit above
this one.

The point of separating it out is that AST *shape* has exactly one owner.
Passes do not each carry their own `typecase` over forty node types; they call
[`ast-children`](reference/api.md#ast-children) and
[`ast-bound-names`](reference/api.md#ast-bound-names), and a new node kind
becomes visible to every existing traversal at once.

## Where to go next

- [Getting started](getting-started.md) — install it and build a first tree.
- [Core concepts](guide/concepts.md) — the node hierarchy and the data
  protocol, which is the part worth understanding before writing a pass.
- [API reference](reference/api.md) — every exported name.
- [Architecture](reference/architecture.md) — how the four source files divide
  the work, and why the traversal primitive is written in CPS.

## A note on the package name

The ASDF system is `cl-cc-ast`; the Lisp package it defines is `:cl-cc/ast`.
Those disagree, and the org
[glossary](https://github.com/nerima-lisp/.github/blob/main/GLOSSARY.md) calls
for `cl-cc-ast` in both places, because `/` already means "ASDF secondary
system" — as in `cl-cc-ast/test`. Renaming the package is a breaking change
for every downstream system, so it has not happened yet. Write `:cl-cc/ast`
today.
