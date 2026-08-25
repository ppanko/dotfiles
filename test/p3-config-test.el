;;; p3-config-test.el --- Smoke tests for the Emacs config -*- lexical-binding: t; -*-

(require 'ert)
(require 'org)
(require 'ob-tangle)

(defconst p3-config-test--root
  (file-name-directory
   (directory-file-name
    (file-name-directory (or load-file-name buffer-file-name))))
  "Root of the Emacs configuration under test.")

(defun p3-config-test--assert-readable-elisp (path)
  "Fail when PATH does not contain syntactically readable Emacs Lisp."
  (with-temp-buffer
    (insert-file-contents path)
    (emacs-lisp-mode)
    (condition-case err
        (progn
          ;; `check-parens' distinguishes an incomplete form from the normal
          ;; end-of-file signal produced by repeatedly calling `read'.
          (check-parens)
          (goto-char (point-min))
          (condition-case nil
              (while t
                (read (current-buffer)))
            (end-of-file t)))
      (error
       (ert-fail
        (format "Could not read %s: %s" path (error-message-string err)))))))

(ert-deftest p3-init-el-is-readable ()
  (p3-config-test--assert-readable-elisp
   (expand-file-name "init.el" p3-config-test--root)))

(ert-deftest p3-config-org-tangles-to-readable-elisp ()
  (let ((target (make-temp-file "p3-config-test-" nil ".el")))
    (unwind-protect
        (progn
          (org-babel-tangle-file
           (expand-file-name "config.org" p3-config-test--root)
           target
           "emacs-lisp")
          (should (> (file-attribute-size (file-attributes target)) 0))
          (p3-config-test--assert-readable-elisp target))
      (delete-file target))))

(ert-deftest p3-config-org-owns-org-export-integration ()
  (with-temp-buffer
    (insert-file-contents (expand-file-name "config.org" p3-config-test--root))
    (should (search-forward "(use-package p3-org-export" nil t))
    (goto-char (point-min))
    (should-not (search-forward "(defun p3/org-export-to-office" nil t))
    (goto-char (point-min))
    (should (search-forward "(\"C-c C-o\" . \"open link at point\")" nil t))
    (goto-char (point-min))
    (should (search-forward "(\"C-c E\" . \"export Org file\")" nil t))))

(ert-deftest p3-config-org-delegates-custom-subsystems-to-modules ()
  (with-temp-buffer
    (insert-file-contents (expand-file-name "config.org" p3-config-test--root))
    (dolist (module '("p3-core" "p3-python" "p3-terminal" "p3-gptel"))
      (goto-char (point-min))
      (should (search-forward (format "(use-package %s" module) nil t)))
    ;; Package declarations and wiring stay visible in the literate config.
    (dolist (package '("python" "eglot" "vterm" "gptel"))
      (goto-char (point-min))
      (should (search-forward (format "(use-package %s" package) nil t)))
    ;; Subsystem implementations belong to independently testable libraries.
    (dolist (implementation '("(defun p3/project-root"
                               "(defun p3/python-project-interpreter"
                               "(defun p3/vterm-buffer"
                               "(defun p3/gptel-send-task"))
      (goto-char (point-min))
      (should-not (search-forward implementation nil t)))))

(ert-deftest p3-init-does-not-special-case-org-export ()
  (with-temp-buffer
    (insert-file-contents (expand-file-name "init.el" p3-config-test--root))
    (should-not (search-forward "(load \"p3-org-export\"" nil t))))

(provide 'p3-config-test)

;;; p3-config-test.el ends here
