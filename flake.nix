{
  description = "cl-cc-ast: AST node types and protocol for the cl-cc Common Lisp compiler";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixpkgs-unstable";
    # Test-only: cl-weave is the test framework. Pulled as a plain source tree
    # and handed to the test runner via CL_CC_AST_CL_WEAVE_ROOT.
    cl-weave = {
      url = "github:nerima-lisp/cl-weave";
      flake = false;
    };
  };

  outputs =
    {
      self,
      nixpkgs,
      cl-weave,
    }:
    let
      systems = [
        "x86_64-linux"
        "aarch64-linux"
        "aarch64-darwin"
        "x86_64-darwin"
      ];
      forAllSystems =
        function: nixpkgs.lib.genAttrs systems (system: function (import nixpkgs { inherit system; }));
    in
    {
      devShells = forAllSystems (pkgs: {
        default = pkgs.mkShell {
          packages = [ pkgs.sbcl ];
        };
      });

      formatter = forAllSystems (pkgs: pkgs.nixfmt-rfc-style);

      packages = forAllSystems (pkgs: {
        default = pkgs.stdenvNoCC.mkDerivation {
          pname = "cl-cc-ast";
          version = "0.1.0";
          src = self;
          nativeBuildInputs = [ pkgs.sbcl ];
          buildPhase = ''
            export HOME="$TMPDIR/home"
            mkdir -p "$HOME"
            sbcl --noinform --non-interactive --script scripts/run-compile-check.lisp
          '';
          installPhase = ''
            mkdir -p "$out/share/common-lisp/source/cl-cc-ast"
            cp -R . "$out/share/common-lisp/source/cl-cc-ast"
          '';
          meta = {
            description = "cl-cc AST node types and protocol";
            homepage = "https://github.com/nerima-lisp/cl-cc-ast";
            license = pkgs.lib.licenses.mit;
            platforms = pkgs.lib.platforms.unix;
          };
        };
      });

      checks = forAllSystems (pkgs: {
        compile = self.packages.${pkgs.stdenv.hostPlatform.system}.default;

        test = pkgs.stdenvNoCC.mkDerivation {
          name = "cl-cc-ast-test";
          src = self;
          nativeBuildInputs = [ pkgs.sbcl ];
          buildPhase = ''
            export HOME="$TMPDIR/home"
            mkdir -p "$HOME"
            export CL_CC_AST_CL_WEAVE_ROOT="${toString cl-weave}"
            sbcl --noinform --non-interactive --script scripts/run-tests.lisp
          '';
          installPhase = "touch $out";
        };
      });
    };
}
