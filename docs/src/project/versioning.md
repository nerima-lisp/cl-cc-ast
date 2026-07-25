# Versioning

`cl-cc-ast` follows [Semantic Versioning 2.0.0](https://semver.org/spec/v2.0.0.html).

## One source of truth

The version lives in exactly one place: the `:version` form in
`cl-cc-ast.asd`.

- `flake.nix` reads that form at evaluation time, so every Nix package derives
  its version from it rather than repeating a literal.
- `release.yml` compares the pushed tag against it and refuses to publish when
  they disagree. A tag `v0.1.0` requires `:version "0.1.0"`.

So a release edits one line, and the two places that could otherwise drift are
mechanically prevented from doing so.

## Pre-1.0

The current version is `0.1.0`. Under SemVer that means the public API may
change in a minor release, and this system makes use of that: it was extracted
from the `cl-cc` monorepo recently and at least one rename is known to be
pending.

The known one is the package name. The ASDF system is `cl-cc-ast`, the Lisp
package is `:cl-cc/ast`, and the org
[glossary](https://github.com/nerima-lisp/.github/blob/main/GLOSSARY.md)
requires the two to agree. Changing it is a breaking change for `cl-cc-type`
and `cl-cc`, so it will land as its own change with the downstream systems
updated in step, not folded into an unrelated release.

## Consuming a release

Pin a tag. Inside the org this is mandatory rather than advisory:

```nix
inputs.cl-cc-ast = {
  url = "github:nerima-lisp/cl-cc-ast/v0.1.0";
  inputs.nixpkgs.follows = "nixpkgs";
};
```

A bare `github:nerima-lisp/cl-cc-ast` follows the default branch, which means
a push here breaks your build with no change on your side and no warning.

## Changelog

Changes are recorded in
[CHANGELOG.md](https://github.com/nerima-lisp/cl-cc-ast/blob/main/CHANGELOG.md)
in [Keep a Changelog](https://keepachangelog.com/en/1.1.0/) format. The release
workflow extracts the section matching the pushed tag and uses it verbatim as
the GitHub Release body, so the heading format `## [X.Y.Z] - YYYY-MM-DD` is
load-bearing rather than cosmetic.
