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
nix flake check        # tests, the SB-COVER gate, formatting, and the docs build
nix run .#test         # the suite on its own

# Outside Nix, point CL_SOURCE_REGISTRY at a cl-weave checkout:
CL_SOURCE_REGISTRY="/path/to/cl-weave//:" sbcl --script run-tests.lisp
CL_SOURCE_REGISTRY="/path/to/cl-weave//:" sbcl --script run-coverage.lisp   # SB-COVER
                                           # report + gate; see the script's
                                           # header for what it does and does
                                           # not enforce
```

## License

MIT — see [LICENSE](LICENSE).
