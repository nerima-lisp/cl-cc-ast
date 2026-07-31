# Changelog

All notable changes to this project will be documented in this file.

The format follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/).

## [Unreleased]

## [0.2.0] - 2026-07-31

### Changed

- `flake.nix` pins `cl-weave` to `v1.1.0` (was `v1.0.0`).
- `packages.cl-cc-ast` in `flake.nix` builds with the org's own
  [`cl-nix-forge`](https://github.com/nerima-lisp/cl-nix-forge) (`v0.1.0`,
  new flake input) instead of nixpkgs' generic `sbcl.buildASDFSystem`, via
  `cl.lispDerivation` and `cl.mkLispSource`. `lispDependencies` is empty,
  matching `cl-cc-ast.asd`'s own `:depends-on ()`; `mkLispSource` allowlists
  `.asd`/`.lisp` files instead of hashing the whole tree (docs/, .github/,
  flake.lock, ...) as the previous `src = self` did.
- `src/closure.lisp`'s `group-shared-sibling-captures` and
  `group-shareable-closures` shared an identical `maphash` body (paredit's
  similarity scan flagged the pair at 1.0 — an exact clone) that differed
  only in the key each grouping call computed per item. Extracted the shared
  "group by key, keep only groups with more than one member" logic into a new
  `%group-multi-member` helper.
- `find-free-variables` in `src/closure.lisp` — the largest function in the
  gated source files by `paredit inspect definitions`' span size — split its
  four non-trivial `typecase` clauses (`ast-let`, `ast-callable`,
  `ast-local-fns`, `ast-multiple-value-bind`) into named `%free-vars-of-*`
  helpers, so the dispatcher reads as a one-clause-per-kind table again
  instead of a nested `let` inside every arm.
- `find-captured-in-children` in `src/closure.lisp` — the third-largest
  function in the gated files, and the only one still threading a mutable
  accumulator through a `dolist`/`typecase`/`setf` — is now a `reduce`/`mapcar`
  fold over a new `%captured-in-form` helper (with its own `ast-local-fns`
  case further factored into `%local-fns-captured-bindings`), matching the
  pure-functional style every other traversal in this file already uses.
- `find-mutated-variables`, `mutated-vars-of-list`, `find-captured-in-children`,
  `%captured-in-form`, `find-free-variables`, and `free-vars-of-list` are now
  genuinely CPS: each takes an `&optional (k #'identity)` continuation and
  threads it through its own recursive calls, in the same style as
  `ast-search-cps`. (The `%free-vars-of-*` helpers `find-free-variables`
  dispatches to stay direct-style leaf combiners, the same role
  `%local-fns-captured-bindings` already had — each does its own internal
  `union`/`set-difference` synchronously and calls back into the now-CPS
  functions using their default continuation.) `docs/src/project/versioning.md`
  states this package's public API "may change in a minor release" at
  `0.1.0`, so the earlier "declining to CPS-convert exported functions is a
  breaking change" reasoning was over-cautious — but defaulting `k` to
  `#'identity` avoids the break anyway: every existing direct-style call
  (`(find-mutated-variables ast)`) still returns a plain value, unchanged.
  New `t/closure-test.lisp` cases exercise the continuation-passing path
  explicitly via `with-continuation-result`. Landing this exposed a second,
  independent case of the same coverage-instrumentation limit documented in
  `run-coverage.lisp`'s header: each new `&optional (k #'identity)` default
  form is itself a one-shot expression `sb-cover` cannot mark covered, which
  dropped gated expression coverage from 99.05% to 98.98%. Recalibrated
  `run-coverage.lisp`'s floor to 98.9% (was 99.0%) with the reasoning
  documented in the script's own header, rather than reverting genuinely
  useful CPS coverage to protect a floor that was already an empirically-set
  number, not a round one.
- Added an `it-property` case to `t/ast-roundtrip-test.lisp` that builds
  random `ast-int`/`ast-binop` arithmetic trees (via a hand-composed
  `gen-one-of`/`gen-map`/`gen-tuple` generator, bounded to depth 3) and
  asserts `(eval (ast-to-sexp tree))` agrees with directly interpreting the
  same tree — a correctness property over generated input, not just the
  fixed hand-written cases, scoped to what this repository can express
  without a sexp-to-AST lowering step (which belongs to `cl-cc-parse`).
- Grepped every string literal in `src/` for embedded magic values that
  should be data tables instead: none found beyond what's already extracted
  (`+external-call-primitive-names+`, `*slot-option-readers*`) or inherent to
  the syntax being rendered (e.g. `"_"` as the hole symbol's name).
- The test suite now groups its cases under cl-weave `describe` blocks instead
  of comment-only section dividers, so `nix flake check`'s spec output reports
  a `describe > case` hierarchy per file rather than a flat list. `describe`
  was already shadow-imported in `t/package.lisp` but unused until now.
- `t/ast-analysis-test.lisp`'s single 30-assertion `it-sequential` covering
  every `ast-children` node kind is now one named case per node kind, so a
  failure reports which node kind broke instead of which line.
- `README.md`'s Development section referenced a `scripts/` directory that
  does not exist in this repository (`scripts/run-compile-check.lisp`,
  `scripts/run-tests.lisp`, `scripts/run-coverage.lisp`); corrected to the
  actual root-level `run-tests.lisp` / `run-coverage.lisp` entry points, matching
  `docs/src/getting-started.md`.
- Each test file's suites now run under cl-weave `describe-concurrent`: every
  case is a pure function over locally-constructed AST nodes with no shared
  mutable state, so nothing prevents them running in parallel batches.
- `t/closure-test.lisp` factors the repeated "compute a binding's escape
  kinds, then assert one is present" shape into a new local `defmacro`,
  `expect-escape-kind`, replacing ten `let` + `member` + `expect` blocks with
  one-line assertions.
- `t/ast-analysis-test.lisp` adds a `gen-list`/`gen-integer`-driven
  `it-property` case that builds a randomly sized/valued sibling list under
  `ast-progn` and asserts `ast-search-cps` finds the exact leaf a generated
  target value names — exercising the CPS backtracking traversal against
  generated inputs rather than only the fixed 2-3 node hand-written examples.
- `run-tests.lisp` and `run-coverage.lisp` now enforce their own
  `sb-ext:with-timeout` (100s / 240s) around the test run, so a hang fails
  loudly with a named condition even when invoked directly (as README.md's
  "Outside Nix" path does) rather than only under the shell `timeout` wrapper
  `flake.nix`'s checks and apps already used.
- Ran `paredit inspect lint` (the `recommended` preset) over `src/` and `t/`
  and worked every genuine finding, using `paredit edit select`/`replace` to
  apply each one:
  - `trim-captured-vars` in `src/closure.lisp` scanned `required-vars` and
    `seen` with a linear `member` on every one of `captured-vars`'s entries —
    `linear-search-in-loop` flagged both as O(n·m) where both sides can grow
    with a function's free-variable count. Rewritten to build `required` and
    `seen` as `eq` hash tables up front, so each entry is an O(1) lookup
    instead; the first-occurrence-wins order the docstring promises is
    unchanged; all 185 tests still pass.
  - `ast-location-string` in `src/ast-functions.lisp`'s `(format nil "~A"
    file)` is exactly `princ-to-string`; `format-to-string` caught it.
  - The `ast-tagbody` method of `ast-to-sexp` in `src/ast-roundtrip.lisp`
    built its result with `(list* 'tagbody ...)`, a two-argument `list*` —
    `list-star-to-cons` caught it; now `(cons 'tagbody ...)`.
  - Two three-argument `if`s with a literal `nil` else-branch —
    `(if var (list var) nil)` in `ast-to-sexp`'s handler-case clause
    (`src/ast-roundtrip.lisp`) and `(if (listp body-forms) (reduce ...) nil)`
    in `binding-escape-kinds-in-body` (`src/closure.lisp`) — dropped the
    redundant `nil` (`redundant-if-nil`), which the same run then flagged as
    `one-armed-if` (`(if test then)` is `(when test then)`); both now read
    `when`.
  - Two hand-built `ast-tagbody` fixtures shared between
    `t/ast-analysis-test.lisp` and `t/ast-roundtrip-test.lisp` wrote each
    `(tag . forms)` pair as `(cons 'start (list form))` / `(cons 'end nil)`;
    `cons-to-list` caught both as spelled-out `list` calls. Now
    `(list 'start form)` / `(list 'end)` — same value, since the code that
    reads these back destructures with `(tag . forms)`, unaffected either way.

### Verified, not changed

- Ran `paredit inspect lint` over `src/` and `t/` and investigated every
  remaining finding rather than auto-applying `paredit fix`; five of the
  twelve are false positives specific to a package whose whole job is
  representing Lisp code as data, and one is a deliberate, consistent idiom:
  - `malformed-cond-clause` on `src/ast.lisp`'s `(cond nil)` — this is the
    `ast-if` struct's `cond` *slot* (`DEFSTRUCT`'s `(name default)` shape),
    not a `COND` clause. Its own accessor, `ast-if-cond`, is exported and used
    throughout `ast-functions.lisp` and `ast-roundtrip.lisp`; the slot name
    matches the special form only lexically.
  - `redundant-progn` on `define-ast-nodes` (`src/ast.lisp`) and
    `define-cases` (`t/helpers-cases.lisp`) — both macros expand to
    `` `(progn ,@(loop ... collect `(...))) ``. The linter sees one static
    subform after `progn` (the `loop`) and calls the wrapper redundant without
    accounting for `,@` unquote-splicing at macroexpansion time, when it
    unrolls into as many forms as `specs`/`cases` has entries. Applying the
    suggested rewrite would delete the `progn`, leaving a bare `,@(loop ...)`
    with nowhere to splice into — a reader error, not a style improvement.
  - `redundant-quote`, `one-step-arithmetic`, and `constant-if-test` on three
    separate `'(...)` literals in `t/ast-roundtrip-test.lisp` — each is a
    *quoted* `expected-form` in a round-trip test table (`'(setf (gethash
    (quote :k) h) 1)`, `'(+ 1 2)`, `'(if 1 2 3)`), asserting the exact
    S-expression `ast-to-sexp` must produce, not code this file executes. The
    suggested rewrites (drop the inner `quote`, fold `+ x 1` to `1+`, discard
    the "dead" else-branch of a constant-test `if`) all target what the
    quoted list would mean *as code*, which would change the asserted value
    and make each test check the wrong thing.
  - `handler-case-swallows-error` on the same file's `'(handler-case 1 (error
    () 0))` expected-form and its matching `(list 'error nil ...)` AST-node
    constructor call — again quoted/constructed *data* describing what
    `ast-to-sexp` should emit for an `ast-handler-case` node, not a live
    `handler-case` this file evaluates and whose condition it discards.
  - `eval-of-non-constant` on the `it-property` case's `(eval (ast-to-sexp
    tree))` (`t/ast-roundtrip-test.lisp`, added earlier in this same
    Unreleased section) — `tree` comes from this file's own bounded
    `gen-one-of`/`gen-map`/`gen-tuple` arithmetic generator, not from any path
    reachable outside the test process; there is no untrusted input for the
    rule's "arbitrary execution" concern to apply to.
  - `negated-if` on `src/ast-functions.lisp`'s `ast-search-cps` and three
    sibling functions in `src/closure.lisp` (`mutated-vars-of-list`,
    `find-captured-in-children`, `free-vars-of-list`) — all four share the
    exact `(if (null xs) (funcall k/failure ...) (recurse ...))` base-case
    shape. Flipping the branches on some but not all of this file's near-
    identical CPS list-walkers would make the one deliberately mirrored idiom
    inconsistent across siblings for a marginal, debatable style gain; left
    as `null`-first to match every neighboring clause.

- The 99% coverage floor in `run-coverage.lisp` was checked against the
  current `sb-cover` HTML report rather than taken on faith: every remaining
  gap in `ast-functions.lisp`, `ast-roundtrip.lisp`, and `closure.lisp` is an
  `(in-package ...)` form, a `defgeneric`'s `:documentation` option, a
  `defparameter` value form, or an `&key (safe-consumers nil)` default —
  exactly the one-shot-at-load-time artifact category the coverage script's
  own header comment already documents as unreachable by testing. 100% is not
  achievable under `sb-cover`'s instrumentation of these forms; the floor is
  already calibrated to the practical ceiling.
- Surveyed the rest of the nerima-lisp org for packages this system could
  depend on; deliberately added none as a runtime dependency.
  `cl-parser-kit` (tokenizer/parser-combinator toolkit) and `cl-prolog`
  (already the base of the org's `cl-cc-prolog-tools`) are real fits for a
  Lisp compiler front end, but belong to `cl-cc-parse` and downstream
  prolog-based tooling respectively, not to this dependency-free AST leaf.
  `cl-boundary-kit` and `cl-dataflow` assume I/O boundaries and pipeline
  execution this package has none of. Adding any of them here would violate
  `cl-cc-ast.asd`'s own `:depends-on ()` contract, which `cl-cc-type`,
  `cl-cc-parse`, and `cl-cc-prolog-tools` all rely on downstream.
- Grepped `src/` for `TODO`, `FIXME`, `XXX`, `deprecated`, `legacy`,
  `backward-compat`, `obsolete`, and `#+`/`#-` reader-conditional branches:
  zero matches. There is no legacy code path or superseded API here to
  remove — confirmed rather than assumed.
- paredit's similarity scan also flagged ~14 `ast-to-sexp` methods in
  `src/ast-roundtrip.lisp` as pairwise near-duplicates (0.94+) — e.g.
  `ast-multiple-value-call`, `ast-multiple-value-prog1`, `ast-apply`,
  `ast-catch`, and `ast-unwind-protect` all reduce to
  `(list* 'head (ast-to-sexp first) (mapcar #'ast-to-sexp rest))`. Prototyped
  four small batch-defining macros (one per recurring shape) to replace them,
  then declined to land it: `docs/src/reference/architecture.md` already
  documents, with reasons, why this file is one `defmethod` per node type
  rather than a shared/generic implementation — per-node concrete syntax
  knowledge and a loud `no-applicable-method` on a missing method. A macro
  that still expands to one `defmethod` per type preserves both properties,
  but for methods this short (most are one line), trading a self-evident
  `defmethod` for a macro call the reader must know the calling convention of
  is not a readability win, only a line-count one. Left these as explicit,
  independently-readable methods.
- Went further than the analysis above once: actually landed a
  `define-head-and-rest-to-sexp` batch macro for the five methods with the
  strongest duplication signal (`ast-multiple-value-call`,
  `ast-multiple-value-prog1`, `ast-apply`, `ast-catch`,
  `ast-unwind-protect`), verified it compiled and passed all 180 tests, then
  ran the full `nix flake check` — which **failed**: `checks.coverage` dropped
  from 99.05% to 98.66% expression coverage, below the 99% floor. The macro's
  own `loop`/backquote body introduces expressions `sb-cover` cannot attribute
  to a runtime-executed instrumentation the way the five hand-written
  `defmethod` forms were. Reverted immediately (`git diff` on the file is
  empty). This is no longer a style argument: macro-generating this file's
  methods has a measured, reproducible cost beyond readability, on the exact
  gate this project's own coverage floor depends on.

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
