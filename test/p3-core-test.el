;;; p3-core-test.el --- Tests for p3-core -*- lexical-binding: t; -*-

(require 'ert)
(require 'cl-lib)

(defconst p3-core-test--root
  (file-name-directory
   (directory-file-name
    (file-name-directory (or load-file-name buffer-file-name))))
  "Root of the Emacs configuration under test.")

(add-to-list 'load-path (expand-file-name "lisp" p3-core-test--root))

(require 'p3-core)

(ert-deftest p3-core-config-commands-remain-commands ()
  (should (commandp #'p3/config-visit))
  (should (commandp #'p3/config-reload)))

(ert-deftest p3-core-config-reload-builds-once-then-loads-directly ()
  (let (calls)
    (cl-letf (((symbol-function 'p3/config-build)
               (lambda () (push 'build calls)))
              ((symbol-function 'p3/config-load-generated)
               (lambda () (push 'load calls))))
      (p3/config-reload))
    (should (equal (nreverse calls) '(build load)))))

(ert-deftest p3-core-config-reload-reloads-current-module-source ()
  (let* ((directory (make-temp-file "p3-core-reload-test-" t))
         (p3/config-source (expand-file-name "config.org" directory))
         (p3/config-generated (expand-file-name "config.el" directory))
         (p3/config-lisp-directory (expand-file-name "lisp" directory))
         (module (expand-file-name "p3-reload-test-module.el"
                                   p3/config-lisp-directory)))
    (unwind-protect
        (progn
          (make-directory p3/config-lisp-directory t)
          (with-temp-file p3/config-source
            (insert "#+begin_src emacs-lisp\n"
                    "(p3/config-load-module 'p3-reload-test-module)\n"
                    "#+end_src\n"))
          (with-temp-file module
            (insert "(setq p3-core-test--reload-value 'one)\n"
                    "(provide 'p3-reload-test-module)\n"))
          (setq p3-core-test--reload-value nil)
          (p3/config-reload)
          (should (eq p3-core-test--reload-value 'one))
          (with-temp-file module
            (insert "(setq p3-core-test--reload-value 'two)\n"
                    "(provide 'p3-reload-test-module)\n"))
          (p3/config-reload)
          (should (eq p3-core-test--reload-value 'two)))
      (setq features (delq 'p3-reload-test-module features))
      (delete-directory directory t))))

(provide 'p3-core-test)

;;; p3-core-test.el ends here
