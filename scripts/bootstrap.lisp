(require :asdf)

(defvar *project-root*
  (uiop:pathname-parent-directory-pathname
   (uiop:pathname-directory-pathname (or *load-pathname* *compile-file-pathname*))))

(defparameter *test-dependency-specs*
  '(("CL_CC_AST_CL_WEAVE_ROOT" "cl-weave" "cl-weave.asd" ("cl-weave"))))

(defun current-project-root ()
  *project-root*)

(defun project-file (project-root relative-path)
  (merge-pathnames relative-path project-root))

(defun normalize-directory-pathname (pathspec)
  (uiop:ensure-directory-pathname (uiop:parse-native-namestring pathspec)))

(defun normalize-system-name (designator)
  (string-downcase
   (etypecase designator
     (string designator)
     (symbol (symbol-name designator)))))

(defun load-asd-definition (asd-path)
  (load (probe-file asd-path)))

(defun %pathname-under-directory-p (pathname directory)
  (let ((path (namestring (truename pathname)))
        (root (namestring (uiop:ensure-directory-pathname (truename directory)))))
    (and (<= (length root) (length path))
         (string= root path :end2 (length root)))))

(defun %dependency-source-root (asd-path)
  (uiop:pathname-directory-pathname asd-path))

(defmacro with-source-load-evaluator (&body body)
  #+sbcl
  `(let ((sb-ext:*evaluator-mode* :interpret))
     ,@body)
  #-sbcl
  `(progn
     ,@body))

(defun dependency-root-candidates (project-root env-var fallback-directory)
  (remove nil
          (list (uiop:getenv env-var)
                (namestring
                 (merge-pathnames
                  (concatenate 'string "../" fallback-directory "/")
                  project-root)))
          :test #'equal))

(defun locate-dependency-asd (project-root env-var fallback-directory asd-name)
  (loop for candidate in (dependency-root-candidates project-root env-var fallback-directory)
        for root = (normalize-directory-pathname candidate)
        for asd-path = (merge-pathnames asd-name root)
        when (probe-file asd-path)
          do (return asd-path)
        finally
           (error "Missing dependency ASD ~A. Set ~A or place ~A next to the project checkout."
                  asd-name
                  env-var
                  fallback-directory)))

(defun load-test-dependency-asd-definitions (project-root)
  (dolist (spec *test-dependency-specs*)
    (destructuring-bind (env-var fallback-directory asd-name system-names) spec
      (let ((asd-path (locate-dependency-asd project-root env-var fallback-directory asd-name)))
        (dolist (system-name system-names)
          (system-source-files-from-asd asd-path system-name))))))

(defun component-property (component key)
  (getf (cddr component) key))

(defun defsystem-form-p (form)
  (and (consp form)
       (symbolp (car form))
       (string-equal (symbol-name (car form)) "DEFSYSTEM")))

(defun find-defsystem-form (asd-path system-name)
  (with-open-file (stream asd-path :direction :input)
    (let ((*read-eval* nil))
      (loop for form = (read stream nil nil)
            while form
            when (and (defsystem-form-p form)
                      (string= (normalize-system-name (second form))
                               (normalize-system-name system-name)))
              do (return form)
            finally
               (error "Missing defsystem ~A in ~A." system-name asd-path)))))

(defun relative-source-pathname (pathspec)
  (let ((pathname (uiop:parse-unix-namestring (format nil "~A" pathspec))))
    (if (pathname-type pathname)
        pathname
        (make-pathname :type "lisp" :defaults pathname))))

(defun relative-directory-pathname (pathspec)
  (uiop:ensure-directory-pathname
   (uiop:parse-unix-namestring (format nil "~A" pathspec))))

(defun %validate-source-file-pathname (pathname source-root)
  (let ((source-file (resolve-source-file-pathname pathname)))
    (unless (%pathname-under-directory-p source-file source-root)
      (error "ASD component path ~A escapes source root ~A."
             source-file
             source-root))
    source-file))

(defun component-source-files (component parent-directory source-root)
  (case (car component)
    (:file
     (list (%validate-source-file-pathname
            (merge-pathnames
             (relative-source-pathname (second component))
             parent-directory)
            source-root)))
    (:module
     (let ((module-directory
             (merge-pathnames
              (relative-directory-pathname
               (or (component-property component :pathname)
                   (second component)))
              parent-directory)))
       (loop for child in (component-property component :components)
             append (component-source-files child module-directory source-root))))
    (t
     nil)))

(defun system-source-files-from-asd (asd-path system-name)
  (let* ((defsystem-form (find-defsystem-form asd-path system-name))
         (options (cddr defsystem-form))
         (base-directory
           (merge-pathnames
            (relative-directory-pathname (or (getf options :pathname) ""))
            (uiop:pathname-directory-pathname asd-path)))
         (source-root (%dependency-source-root asd-path)))
    (loop for component in (getf options :components)
          append (component-source-files component base-directory source-root))))

(defun resolve-source-file-pathname (pathname)
  (or (probe-file pathname)
      (probe-file (make-pathname :type "lisp" :defaults pathname))
      pathname))

(defun load-system-source-files (asd-path system-name)
  (with-source-load-evaluator
    (dolist (pathname (system-source-files-from-asd asd-path system-name))
      (load (resolve-source-file-pathname pathname)))))

(defun component-fasl-pathname (output-root pathname index)
  (merge-pathnames
   (format nil "~4,'0D-~A.fasl" index (pathname-name pathname))
   output-root))

(defun compile-output-root ()
  (uiop:ensure-directory-pathname
   (merge-pathnames
    (format nil "cl-cc-ast-compile-~36R/"
            (logxor (get-universal-time) (sxhash (gensym "COMPILE"))))
    (uiop:temporary-directory))))

(defun compile-system-source-files (asd-path system-name)
  (let ((output-root (compile-output-root)))
    (ensure-directories-exist output-root)
    (loop for pathname in (system-source-files-from-asd asd-path system-name)
          for source-file = (resolve-source-file-pathname pathname)
          for index from 0
          for output-file = (component-fasl-pathname output-root source-file index)
          do (load (compile-file source-file :output-file output-file)))))

(defun load-test-dependency-sources (project-root)
  (dolist (spec *test-dependency-specs*)
    (destructuring-bind (env-var fallback-directory asd-name system-names) spec
      (let ((asd-path (locate-dependency-asd project-root env-var fallback-directory asd-name)))
        (dolist (system-name system-names)
          (load-system-source-files asd-path system-name))))))

(defun load-project-asd-definitions (project-root &key (include-test-system-p t))
  (when include-test-system-p
    (load-test-dependency-asd-definitions project-root))
  (load-asd-definition (project-file project-root "cl-cc-ast.asd"))
  (when include-test-system-p
    (load-asd-definition (project-file project-root "cl-cc-ast-test.asd"))))

(defun load-project-sources (project-root)
  (load-system-source-files (project-file project-root "cl-cc-ast.asd")
                            "cl-cc-ast"))

(defun compile-project-sources (project-root)
  (compile-system-source-files (project-file project-root "cl-cc-ast.asd")
                               "cl-cc-ast"))

(defun load-project-tests (project-root)
  (load-project-asd-definitions project-root)
  (load-test-dependency-sources project-root)
  (load-project-sources project-root)
  (load-system-source-files (project-file project-root "cl-cc-ast-test.asd")
                            "cl-cc-ast-test"))

(defun compile-project-tests (project-root)
  (load-project-asd-definitions project-root)
  (load-test-dependency-sources project-root)
  (compile-project-sources project-root)
  (compile-system-source-files (project-file project-root "cl-cc-ast-test.asd")
                               "cl-cc-ast-test"))

(defun package-symbol-call (package-name symbol-name &rest arguments)
  (apply (symbol-function (find-symbol (string symbol-name) package-name))
         arguments))
