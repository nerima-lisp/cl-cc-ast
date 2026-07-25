# Changelog

All notable changes to this project will be documented in this file.

The format follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/).

## [Unreleased]

## [0.1.0] - 2026-07-26

The first release. `cl-cc-ast` is the dependency-free leaf of the `cl-cc`
compiler, extracted so that the systems above it can depend on the AST without
pulling in the whole compiler.

### Added

- AST node types and their accessors, extracted from `cl-cc` as a standalone
  system with no dependencies of its own.
- The `ast-children` / `ast-bound-names` data protocol, which is what lets
  downstream systems walk a tree without knowing every node type.
- Closure and free-variable analysis helpers.
- S-expression round-trip (unparse) support.
- A test suite on [cl-weave](https://github.com/nerima-lisp/cl-weave), covering
  the round-trip property and closure analysis.
- The org standard workflow set — `ci.yml`, `docs.yml`, `release.yml`,
  `flake-update.yml` — and the shared `nix-setup` composite action.
- A documentation site under `docs/`, built with `mkdocs build --strict` as
  part of `nix flake check`.

### Changed

- The test system moved from a separate `cl-cc-ast-test.asd` into
  `cl-cc-ast.asd` as the `cl-cc-ast/test` secondary system. A second `.asd` is
  a second place for the version and the metadata to drift.
- Tests moved from `tests/` to `t/`, and each file is now named after the
  source file it covers.
- `flake.nix` reads the version from `cl-cc-ast.asd` instead of carrying its
  own copy, tracks `nixos-unstable`, and pins `cl-weave` to `v1.0.0` rather
  than following its default branch.

### Known issues

- The Lisp package these systems define is `:cl-cc/ast`, not `:cl-cc-ast`. The
  `/` already means "ASDF secondary system", which is what `cl-cc-ast/test`
  uses it for. Renaming the package breaks `cl-cc-type` and `cl-cc`, so it is
  left for its own change.
- `cl-cc/packages/cl-cc-ast` defines a system by the same name. Which one ASDF
  resolves depends on the registry order. The duplication is known and
  unresolved.
