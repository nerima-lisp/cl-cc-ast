# Changelog

## 0.2.2 - Unreleased

### Fixed

- Accept Common Lisp SETF function names in `ast-defun`, while retaining
  symbol names and rejecting malformed names in constructors and setters.
- Preserve function-name identity when rendering function definitions with
  `ast-to-sexp`.

### Verification scope

Regression tests in `t/ast-test.lisp` and `t/ast-roundtrip-test.lisp` cover
constructor and setter contracts, malformed names, uninterned symbols, and
round-trip identity. These tests do not establish compiler self-hosting or
native execution; consumers need their own integration checks.
