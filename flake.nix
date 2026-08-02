{
  description = "cl-cc AST node types and protocol (ast-children, ast-bound-names)";

  inputs = {
    # nixos-unstable, not nixpkgs-unstable: it advances only after the NixOS
    # release tests pass, so it is less likely to land a broken build.
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";

    # Pinned to a release tag. A bare `github:nerima-lisp/cl-weave` follows
    # that repository's default branch, so an upstream push to main would
    # break this repository's CI without warning. This used to be a
    # `flake = false` source tree handed to the runner through an environment
    # variable; it is a normal flake input now, which is what lets ASDF find
    # cl-weave through CL_SOURCE_REGISTRY like any other dependency.
    cl-weave = {
      url = "github:nerima-lisp/cl-weave/v1.1.4";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    # The org's own ASDF-system-as-derivation builder (the `crane` of this
    # org), used below for `packages.cl-cc-ast` instead of nixpkgs' generic
    # `sbcl.buildASDFSystem`. Pinned to a release tag for the same reason
    # cl-weave is: a bare `github:nerima-lisp/cl-nix-forge` follows its
    # default branch.
    cl-nix-forge = {
      url = "github:nerima-lisp/cl-nix-forge/v0.4.0";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    treefmt-nix = {
      url = "github:numtide/treefmt-nix";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };

  outputs =
    inputs@{
      self,
      nixpkgs,
      cl-weave,
      cl-nix-forge,
      treefmt-nix,
      ...
    }:
    let
      # CI builds and tests only x86_64-linux, so that is the sole declared
      # system: the flake never advertises a platform it does not verify.
      # aarch64-darwin was dropped on 2026-08-01. Its only verification was a
      # local `nix flake check` on a development machine, and a run nobody can
      # tell was skipped is not a gate. aarch64-linux and x86_64-darwin were
      # already undeclared for the same reason.
      #
      # Consequence, accepted deliberately: every per-system output -- packages,
      # checks, apps AND devShells -- is generated from this one list, so
      # `nix develop` and `nix build` no longer work on macOS. Development
      # happens on Linux. See PACKAGE_STANDARD.md, section "systems".
      systems = [
        "x86_64-linux"
      ];
      forAllSystems = nixpkgs.lib.genAttrs systems;

      # CL_SOURCE_REGISTRY for the test, coverage and dev environments.
      sourceRegistry = "${cl-weave}//:${self}//";

      # Single source of truth for the package version: the `:version` form in
      # cl-cc-ast.asd. A release only ever edits the .asd file and every Nix
      # package (default + docs) follows automatically. Nix regexes are
      # whole-string anchored and `.` never spans newlines, so the version is
      # extracted line-by-line rather than with one multi-line match.
      version =
        let
          lines = nixpkgs.lib.splitString "\n" (builtins.readFile ./cl-cc-ast.asd);
          versionLine = builtins.head (
            builtins.filter (line: builtins.match "[[:space:]]*:version \"[^\"]*\"" line != null) lines
          );
        in
        builtins.head (builtins.match "[[:space:]]*:version \"([^\"]*)\"" versionLine);

      # treefmt drives `nix fmt` and the `checks.<system>.formatting` gate.
      # Scope is Nix only: nixfmt (RFC-style) is a zero-footgun, low-diff
      # formatter, whereas YAML formatters mangle the GitHub Actions `on:`
      # key and Markdown reformatting would churn the whole docs tree.
      treefmtEval = forAllSystems (
        system:
        treefmt-nix.lib.evalModule nixpkgs.legacyPackages.${system} {
          projectRootFile = "flake.nix";
          programs.nixfmt.enable = true;
        }
      );
    in
    {
      packages = forAllSystems (
        system:
        let
          pkgs = nixpkgs.legacyPackages.${system};
          cl = cl-nix-forge.lib.${system};
        in
        rec {
          # cl-cc-ast has no Lisp dependencies of its own (:depends-on ()), so
          # lispDependencies is empty here; cl-weave only enters the picture
          # for the test-only `cl-cc-ast/test` system, which this package
          # deliberately does not build (see checks.default below, which runs
          # the full suite instead). mkLispSource allowlists .asd/.lisp files
          # under the source tree rather than hashing everything self
          # contains (docs/, .github/, flake.lock, a stray local .fasl, ...).
          cl-cc-ast = cl.lispDerivation {
            lispSystem = "cl-cc-ast";
            inherit version;
            src = cl.mkLispSource { root = ./.; };
            lispDependencies = [ ];
          };
          default = cl-cc-ast;

          # Rendered documentation site (Material for MkDocs).
          # Build fully offline: Material for MkDocs bundles all of its assets,
          # so no network access is required inside the Nix sandbox. --strict
          # promotes broken links and unlisted pages to build failures.
          docs = pkgs.stdenvNoCC.mkDerivation {
            pname = "cl-cc-ast-docs";
            inherit version;
            src = pkgs.lib.fileset.toSource {
              root = ./docs;
              fileset = pkgs.lib.fileset.unions [
                ./docs/mkdocs.yml
                ./docs/src
              ];
            };
            nativeBuildInputs = [ pkgs.python3Packages.mkdocs-material ];
            buildPhase = ''
              runHook preBuild
              mkdocs build --strict --config-file mkdocs.yml --site-dir "$out"
              runHook postBuild
            '';
            dontInstall = true;
            meta = {
              description = "Rendered MkDocs (Material) documentation for cl-cc-ast";
              homepage = "https://github.com/nerima-lisp/cl-cc-ast";
              license = pkgs.lib.licenses.mit;
            };
          };
        }
      );

      # `nix fmt` entry point.
      formatter = forAllSystems (system: treefmtEval.${system}.config.build.wrapper);

      # Granularity lives here, NOT in extra GitHub Actions jobs: `nix flake
      # check` evaluates each attribute as its own derivation, in parallel,
      # with build caching. Add a check here rather than a job in ci.yml.
      checks = forAllSystems (
        system:
        let
          pkgs = nixpkgs.legacyPackages.${system};
        in
        {
          default =
            pkgs.runCommand "cl-cc-ast-tests"
              {
                nativeBuildInputs = [
                  pkgs.sbcl
                  pkgs.coreutils
                ];
                CL_SOURCE_REGISTRY = sourceRegistry;
              }
              ''
                export HOME="$TMPDIR/home"
                mkdir -p "$HOME" "$out"
                timeout 120 sbcl --script ${self}/run-tests.lisp
                touch "$out/passed"
              '';

          # Fails `nix flake check` when any tracked file is unformatted,
          # turning the formatter into an enforced CI gate.
          formatting = treefmtEval.${system}.config.build.check self;

          # The docs package builds with `mkdocs --strict`, so a broken link or
          # a page missing from the nav fails the build. Without this the docs
          # are only ever built by the publish workflow, which runs after a
          # merge to main, meaning such a break surfaces as a failed deploy
          # rather than as a failed pull request.
          docs = self.packages.${system}.docs;

          # SB-COVER floor on the three files in src/ that carry branching
          # logic. This is a check rather than a CI job precisely because it
          # needs nothing the Nix sandbox cannot provide. It is a derivation
          # of its own rather than a runCommand over ${self} because the
          # script writes its HTML report next to the sources, which the
          # read-only store path does not allow.
          coverage = pkgs.stdenvNoCC.mkDerivation {
            name = "cl-cc-ast-coverage";
            src = self;
            nativeBuildInputs = [
              pkgs.sbcl
              pkgs.coreutils
            ];
            CL_SOURCE_REGISTRY = sourceRegistry;
            buildPhase = ''
              runHook preBuild
              export HOME="$TMPDIR/home"
              mkdir -p "$HOME"
              timeout 300 sbcl --script run-coverage.lisp
              runHook postBuild
            '';
            installPhase = ''
              runHook preInstall
              mkdir -p "$out"
              cp -R cl-cc-ast-coverage-report "$out/report"
              runHook postInstall
            '';
          };
        }
      );

      apps = forAllSystems (
        system:
        let
          pkgs = nixpkgs.legacyPackages.${system};
          test = pkgs.writeShellApplication {
            name = "cl-cc-ast-test";
            runtimeInputs = [
              pkgs.sbcl
              pkgs.coreutils
            ];
            text = ''
              export CL_SOURCE_REGISTRY="${sourceRegistry}"
              exec timeout 120 sbcl --script ${self}/run-tests.lisp
            '';
          };
        in
        {
          default = {
            type = "app";
            program = "${test}/bin/cl-cc-ast-test";
          };
          test = {
            type = "app";
            program = "${test}/bin/cl-cc-ast-test";
          };
        }
      );

      devShells = forAllSystems (
        system:
        let
          pkgs = nixpkgs.legacyPackages.${system};
        in
        {
          default = pkgs.mkShell {
            packages = [ pkgs.sbcl ];
            CL_SOURCE_REGISTRY = sourceRegistry;
          };
        }
      );
    };
}
