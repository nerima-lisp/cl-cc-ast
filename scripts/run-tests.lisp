(eval-when (:compile-toplevel :load-toplevel :execute)
  (load (merge-pathnames "bootstrap.lisp"
                         (make-pathname :name nil
                                        :type nil
                                        :version nil
                                        :defaults (or *load-pathname*
                                                      *compile-file-pathname*)))))

(let ((project-root (current-project-root)))
  (require :asdf)
  (load-project-tests project-root)
  (let ((plan (package-symbol-call "CL-WEAVE" "LIST-TESTS"
                                   :reporter :json
                                   :stream (make-broadcast-stream))))
    (format t "Loaded ~D tests.~%" (length plan))
    (when (zerop (length plan))
      (error "cl-cc-ast loaded zero tests")))
  (unless (package-symbol-call :cl-weave
                               :run-all
                               :reporter :spec
                               :pass-with-no-tests nil)
    (uiop:quit 1)))
