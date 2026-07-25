# Getting started

## Install

`cl-cc-ast` has no runtime dependencies, so any of the usual routes work.

=== "Nix flake"

    ```nix
    # flake.nix
    inputs.cl-cc-ast = {
      url = "github:nerima-lisp/cl-cc-ast/v0.1.0";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    ```

    Pin the tag. Consumers inside the org must not follow the default branch:
    an upstream push would otherwise break your build with no change on your
    side.

=== "ASDF"

    Clone the repository somewhere ASDF can see it and load it:

    ```lisp
    (asdf:load-system "cl-cc-ast")
    ```

## The smallest useful example

Build a tree, ask it what it binds, and print it back as source.

```lisp
(asdf:load-system "cl-cc-ast")
(use-package :cl-cc/ast)

(defparameter *tree*
  (make-ast-let
   :bindings (list (cons 'x (make-ast-int :value 1)))
   :body (list (make-ast-binop :op '+
                               :lhs (make-ast-var :name 'x)
                               :rhs (make-ast-var :name 'y)))))

(ast-bound-names *tree*)      ;; => (X)
(find-free-variables *tree*)  ;; => (Y)
(ast-to-sexp *tree*)          ;; => (LET ((X 1)) (+ X Y))
```

`x` is bound by the `let` and `y` is not, so `y` is what a closure over this
form would have to capture. That distinction — bound here, free here — is the
one the whole system is organised around.

## Running the tests

The suite runs under [cl-weave](https://github.com/nerima-lisp/cl-weave).

```sh
nix run .#test       # the suite on its own
nix flake check      # tests, coverage floor, formatting, and this docs site
```

Outside Nix, point `CL_SOURCE_REGISTRY` at a cl-weave checkout and run the
entry point directly:

```sh
CL_SOURCE_REGISTRY="/path/to/cl-weave//:" sbcl --script run-tests.lisp
```
