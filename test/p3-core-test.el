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

(ert-deftest p3-core-project-root-prefers-projectile ()
  (cl-letf (((symbol-function 'projectile-project-root)
             (lambda () "/tmp/projectile-root/"))
            ((symbol-function 'project-current)
             (lambda (&optional _maybe-prompt _directory)
               (ert-fail "Built-in project lookup should not run"))))
    (should (equal (p3/project-root) "/tmp/projectile-root/"))))

(ert-deftest p3-core-project-root-falls-back-to-project-el ()
  (cl-letf (((symbol-function 'projectile-project-root)
             (lambda () nil))
            ((symbol-function 'project-current)
             (lambda (&optional _maybe-prompt _directory) 'fake-project))
            ((symbol-function 'project-root)
             (lambda (_project) "/tmp/project-el-root/")))
    (should (equal (p3/project-root) "/tmp/project-el-root/"))))

(ert-deftest p3-core-project-default-directory-is-buffer-local ()
  (with-temp-buffer
    (let ((original default-directory))
      (cl-letf (((symbol-function 'p3/project-root)
                 (lambda () "/tmp/project-root/")))
        (p3/use-project-root-as-default-dir)
        (should (local-variable-p 'default-directory))
        (should (equal default-directory "/tmp/project-root/"))
        (should-not (equal original default-directory))))))

(ert-deftest p3-core-config-commands-remain-commands ()
  (should (commandp #'p3/config-visit))
  (should (commandp #'p3/config-reload)))

(provide 'p3-core-test)

;;; p3-core-test.el ends here
