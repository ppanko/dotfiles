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

(ert-deftest p3-init-loads-org-export-after-generated-config ()
  (with-temp-buffer
    (insert-file-contents (expand-file-name "init.el" p3-config-test--root))
    (goto-char (point-min))
    (let ((config-load
           (search-forward "(load-file p3/config-generated)" nil t))
          (export-load
           (progn
             (goto-char (point-min))
             (search-forward "(load \"p3-org-export\"" nil t))))
      (should config-load)
      (should export-load)
      (should (< config-load export-load)))))

(provide 'p3-config-test)

;;; p3-config-test.el ends here
