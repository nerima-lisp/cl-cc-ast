# cl-cc-ast

AST node types and protocol for the [cl-cc](https://github.com/nerima-lisp/cl-cc)
Common Lisp compiler.

This is a **dependency-free leaf system** extracted from the cl-cc monorepo as
the first step of the repository split (see `docs/repo-split-design.md` in
cl-cc). It defines the `:cl-cc/ast` package: AST node structures, accessors,
the `ast-children` / `ast-bound-names` protocol, closure conversion helpers,
and round-trip (unparse) support.

Downstream systems (`cl-cc-type`, `cl-cc-parse`, and the cl-cc compiler itself)
depend on this package through its **public API only**.

## Status

Extracted and building standalone. Tests run on
[cl-weave](https://github.com/nerima-lisp/cl-weave); see the cl-cc split
design.

## Usage

```lisp
(asdf:load-system :cl-cc-ast)
```

## Development

```bash
nix develop            # sbcl dev shell
nix flake check        # compile check, tests, and coverage gate
sbcl --script scripts/run-compile-check.lisp
sbcl --script scripts/run-tests.lisp
sbcl --script scripts/run-coverage.lisp   # SB-COVER report + gate; see the
                                           # script's header for what the gate
                                           # does and does not enforce
```

## License

MIT — see [LICENSE](LICENSE).
