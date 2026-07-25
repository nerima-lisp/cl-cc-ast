;;;; packages/ast/src/ast.lisp - AST Node Struct Definitions
;;;;
;;;; This module provides the base AST node defstructs with source location tracking.
;;;; The concrete expression/control/CLOS variants are kept here so the ASDF
;;;; source snapshot stays self-contained.

(in-package :cl-cc/ast)

;;; AST Base Struct with Source Location Tracking

(defstruct (ast-node (:conc-name ast-))
  "Base struct for all AST nodes with optional source location tracking."
  (source-file nil)
  (source-line nil)
  (source-column nil)
  (namespace nil)
  (imports nil))

;;; DEFINE-AST-NODES: table-driven node struct definitions
;;;
;;; Every AST node kind below is a DEFSTRUCT that includes AST-NODE, directly
;;; or through an intermediate struct. Writing out (:include ast-node) on
;;; ~40 near-identical forms buries the one fact that actually varies per
;;; node — its own slots — under repeated boilerplate. DEFINE-AST-NODES
;;; mirrors DEFSTRUCT's own (name-and-options docstring . slots) syntax and
;;; only removes that repetition: every entry expands to the exact same
;;; DEFSTRUCT form a human would otherwise write by hand.

(defmacro define-ast-nodes (&body specs)
  "Define a batch of AST node DEFSTRUCTs.

Each entry in SPECS has the shape (NAME (&key include conc-name) DOCSTRING
. SLOTS). INCLUDE defaults to AST-NODE; CONC-NAME defaults to DEFSTRUCT's own
NAME- convention. Expands to one ordinary DEFSTRUCT per entry, in order, so
:include dependencies between entries in the same call still resolve
top-to-bottom exactly as hand-written forms would."
  `(progn
     ,@(loop for (name options docstring . slots) in specs
             for include = (or (getf options :include) 'ast-node)
             for conc-name = (getf options :conc-name)
             collect `(defstruct (,name (:include ,include)
                                  ,@(when conc-name `((:conc-name ,conc-name))))
                        ,docstring
                        ,@slots))))

;;; Intermediate AST Structs (shared slot groups)

(define-ast-nodes
  (ast-callable ()
    "Intermediate struct for callable forms (lambda, defun)."
    (params nil :type list)
    (optional-params nil :type list)
    (rest-param nil)
    (key-params nil :type list)
    (declarations nil :type list)
    (body nil :type list))

  (ast-local-fns ()
    "Intermediate struct for local function binding forms (flet, labels)."
    (bindings nil :type list)
    (body nil :type list)))

;;; Function and Lambda AST Structs

(define-ast-nodes
  (ast-lambda (:include ast-callable)
    "Lambda expression AST node."
    (env nil))

  (ast-function ()
    "Function reference AST node for #'var."
    (name nil))

  (ast-flet (:include ast-local-fns)
    "Local non-recursive function bindings AST node.")

  (ast-labels (:include ast-local-fns)
    "Local recursive function bindings AST node.")

  (ast-defun (:include ast-callable)
    "Top-level function definition AST node."
    (name nil :type symbol)
    (documentation nil :type (or null string)))

  (ast-defvar ()
    "Top-level variable definition AST node (defvar/defparameter)."
    (name nil)
    (value nil)
    (kind 'defparameter)  ; 'defvar or 'defparameter — controls conditional-init semantics
    )

  (ast-defmacro ()
    "Top-level macro definition AST node."
    (name nil)
    (lambda-list nil)
    (body nil :type list)))

;;; Core expression AST Structs

(define-ast-nodes
  (ast-int ()
    "Integer literal AST node."
    (value nil))

  (ast-var ()
    "Variable reference AST node."
    (name nil))

  (ast-hole ()
    "Expression-level typed hole AST node for source symbol _.")

  (ast-binop ()
    "Binary operation AST node."
    (op nil)
    (lhs nil)
    (rhs nil))

  (ast-if ()
    "Conditional expression AST node."
    (cond nil)
    (then nil)
    (else nil))

  (ast-progn ()
    "Sequence of expressions AST node."
    (forms nil :type list))

  (ast-print ()
    "Print expression AST node."
    (expr nil))

  (ast-let ()
    "Let binding AST node."
    (bindings nil :type list)
    (declarations nil :type list)
    (body nil :type list)))

;;; Block and control flow AST Structs

(define-ast-nodes
  (ast-block ()
    "Named block AST node."
    (name nil)
    (body nil :type list))

  (ast-return-from ()
    "Return from named block AST node."
    (name nil)
    (value nil))

  (ast-tagbody ()
    "Tagged body for goto-style control flow AST node."
    (tags nil :type list))

  (ast-go ()
    "Go to tag AST node."
    (tag nil)))

;;; Assignment and variables AST Structs

(define-ast-nodes
  (ast-setq ()
    "Variable assignment AST node."
    (var nil)
    (value nil)))

;;; Multiple values AST Structs

(define-ast-nodes
  (ast-multiple-value-call (:conc-name ast-mv-call-)
    "Multiple-value-call special form AST node."
    (func nil)
    (args nil :type list))

  (ast-multiple-value-prog1 (:conc-name ast-mv-prog1-)
    "Multiple-value-prog1 special form AST node."
    (first nil)
    (forms nil :type list))

  (ast-values ()
    "Values form AST node."
    (forms nil :type list))

  (ast-multiple-value-bind (:conc-name ast-mvb-)
    "Multiple-value-bind AST node."
    (vars nil :type list)
    (values-form nil)
    (body nil :type list))

  (ast-apply ()
    "Apply form AST node."
    (func nil)
    (args nil :type list)))

;;; Exception handling AST Structs

(define-ast-nodes
  (ast-catch ()
    "Catch block AST node."
    (tag nil)
    (body nil :type list))

  (ast-throw ()
    "Throw AST node."
    (tag nil)
    (value nil))

  (ast-unwind-protect (:conc-name ast-unwind-)
    "Unwind-protect AST node."
    (protected nil)
    (cleanup nil :type list))

  (ast-handler-case ()
    "Handler-case AST node for condition handling."
    (form nil)
    (clauses nil :type list)))

;;; Additional AST Structs for Common Operations

(define-ast-nodes
  (ast-call ()
    "Function call AST node (for non-special operator calls)."
    (func nil)
    (args nil :type list))

  (ast-quote ()
    "Quote special form AST node."
    (value nil))

  (ast-list ()
    "Runtime list construction AST node."
    (elements nil :type list))

  (ast-the ()
    "The type declaration AST node."
    (type nil)
    (value nil)))

;;; CLOS AST Structs

(define-ast-nodes
  (ast-slot-def (:conc-name ast-slot-)
    "Slot definition for defclass."
    (name nil :type symbol)
    (initarg nil)
    (initform nil)
    (reader nil)
    (writer nil)
    (accessor nil)
    (type nil)
    (allocation :instance))

  (ast-defclass ()
    "Class definition AST node (defclass)."
    (name nil)
    (superclasses nil :type list)
    (slots nil :type list)
    (default-initargs nil :type list)
    (metaclass nil)
    (sealed nil)
    (php-kind nil)
    (php-enum-type nil)
    (php-enum-cases nil :type list))

  (ast-defgeneric ()
    "Generic function definition AST node (defgeneric)."
    (name nil)
    (params nil :type list)
    (combination nil))

  (ast-defmethod ()
    "Method definition AST node (defmethod)."
    (name nil)
    (qualifier nil)
    (specializers nil :type list)
    (params nil :type list)
    (body nil :type list))

  (ast-make-instance ()
    "Object creation AST node (make-instance)."
    (class nil)
    (initargs nil :type list))

  (ast-slot-value ()
    "Slot access AST node (slot-value)."
    (object nil)
    (slot nil))

  (ast-set-slot-value ()
    "Slot mutation AST node (setf (slot-value obj 'slot) val)."
    (object nil)
    (slot nil)
    (value nil))

  (ast-set-gethash ()
    "Hash table mutation AST node (setf (gethash key table) value)."
    (key nil)
    (table nil)
    (value nil)))
