(in-package :cl-cc/ast/nodes/test)

(defparameter *all-ast-node-constructors*
  (list #'make-ast-node #'make-ast-callable #'make-ast-local-fns
        #'make-ast-int #'make-ast-var #'make-ast-hole #'make-ast-binop #'make-ast-if
        #'make-ast-progn #'make-ast-print #'make-ast-let
        #'make-ast-lambda #'make-ast-function #'make-ast-flet #'make-ast-labels
        #'make-ast-defun #'make-ast-defvar #'make-ast-defmacro
        #'make-ast-block #'make-ast-return-from #'make-ast-tagbody #'make-ast-go
        #'make-ast-setq
        #'make-ast-multiple-value-call #'make-ast-multiple-value-prog1 #'make-ast-values
        #'make-ast-multiple-value-bind #'make-ast-apply
        #'make-ast-catch #'make-ast-throw #'make-ast-unwind-protect #'make-ast-handler-case
        #'make-ast-call #'make-ast-quote #'make-ast-list #'make-ast-the
        #'make-ast-slot-def #'make-ast-defclass #'make-ast-defgeneric #'make-ast-defmethod
        #'make-ast-make-instance #'make-ast-slot-value #'make-ast-set-slot-value
        #'make-ast-set-gethash)
  "Every constructor exported by :cl-cc/ast, in package.lisp export order.")

(defmacro define-ast-to-sexp-cases (&body cases)
  "Register one AST-TO-SEXP case per (NODE-FORM EXPECTED-FORM) pair in CASES;
see DEFINE-CASES for the underlying table-test mechanics."
  `(define-cases
     ,@(loop for (node-form expected-form) in cases
             collect `((ast-to-sexp ,node-form) ,expected-form))))

(defun %gen-arith-tree (max-depth)
  "A GEN-ONE-OF/GEN-MAP/GEN-TUPLE-composed generator of AST-INT/AST-BINOP trees
up to MAX-DEPTH deep. Built from plain recursive composition of cl-weave's own
combinators rather than GEN-RECURSIVE, so the shape produced is exactly the
node types this file already has fixed expectations for."
  (if (<= max-depth 0)
      (gen-map (lambda (v) (make-ast-int :value v)) (gen-integer :min -20 :max 20))
      (gen-one-of
       (gen-map (lambda (v) (make-ast-int :value v)) (gen-integer :min -20 :max 20))
       (gen-map (lambda (spec)
                  (make-ast-binop :op (first spec) :lhs (second spec) :rhs (third spec)))
                (gen-tuple (gen-member '(+ - *))
                          (%gen-arith-tree (1- max-depth))
                          (%gen-arith-tree (1- max-depth)))))))

(defun %interpret-arith-tree (node)
  "Directly evaluate an AST-INT/AST-BINOP tree without going through
AST-TO-SEXP, so %GEN-ARITH-TREE's property test has an independent oracle to
compare AST-TO-SEXP's output against."
  (if (ast-int-p node)
      (ast-int-value node)
      (funcall (symbol-function (ast-binop-op node))
               (%interpret-arith-tree (ast-binop-lhs node))
               (%interpret-arith-tree (ast-binop-rhs node)))))

(defun %assert-facade-export-surface ()
  (flet ((read-rows ()
                    (with-open-file (stream
                                     (asdf:system-relative-pathname
                                      "cl-cc-ast/test"
                                      "t/export-surface.txt"))
                      (let ((*package* (find-package "COMMON-LISP-USER"))
                            (*read-eval* nil))
                        (let ((rows (read stream nil :eof)))
                          (expect (eq (read stream nil :eof) :eof) :to-be-truthy)
                          rows)))))
    (let* ((rows (read-rows))
           (facade-package (find-package "CL-CC/AST")))
      (expect facade-package :to-be-truthy)
      (expect (length rows) :to-equal 272)
      (let ((actual-names nil))
        (do-external-symbols (symbol facade-package)
                             (push (symbol-name symbol) actual-names))
        (expect (sort actual-names
                      (lambda (left right) (string< left right)))
                :to-equal
                (sort (mapcar (lambda (row) (sixth row)) rows)
                      (lambda (left right) (string< left right)))))
      (dolist (row rows)
        (destructuring-bind (kind policy facade-name feature-name home-name symbol-name)
            row
          (expect kind :to-be :symbol)
          (expect policy :to-be :keep)
          (expect facade-name :to-equal "cl-cc/ast")
          (let ((feature-package (find-package (string-upcase feature-name)))
                (home-package (find-package (string-upcase home-name))))
            (expect feature-package :to-be-truthy)
            (expect home-package :to-be-truthy)
            (multiple-value-bind (facade-symbol facade-status)
                (find-symbol symbol-name facade-package)
              (multiple-value-bind (feature-symbol feature-status)
                  (find-symbol symbol-name feature-package)
                (multiple-value-bind (home-symbol home-status)
                    (find-symbol symbol-name home-package)
                  (expect facade-status :to-be :external)
                  (expect feature-status :to-be :external)
                  (expect home-status :to-be :external)
                  (expect (eq facade-symbol feature-symbol) :to-be-truthy)
                  (expect (eq facade-symbol home-symbol) :to-be-truthy)
                  (expect (eq (symbol-package facade-symbol) home-package)
                          :to-be-truthy))))))))))
