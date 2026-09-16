;;; p3-org-test.el --- Tests for p3-org -*- lexical-binding: t; -*-

(require 'cl-lib)
(require 'ert)

(defconst p3-org-test--root
  (file-name-directory
   (directory-file-name
    (file-name-directory (or load-file-name buffer-file-name))))
  "Root of the Emacs configuration under test.")

(add-to-list 'load-path (expand-file-name "lisp" p3-org-test--root))
(require 'p3-org)

(ert-deftest p3-org-sort-todos-preserves-current-sort-call ()
  (let (seen)
    (cl-letf (((symbol-function 'org-sort-entries)
               (lambda (&rest args)
                 (setq seen args))))
      (p3/org-sort-todos)
      (should (equal seen (list nil ?o))))))

(ert-deftest p3-org-set-line-checkbox-prefixes-current-line ()
  (with-temp-buffer
    (insert "alpha\nbeta\n")
    (goto-char (point-min))
    (org-set-line-checkbox 1)
    (should (equal (buffer-string) "- [ ] alpha\nbeta\n"))
    (should (looking-at "beta"))))

(ert-deftest p3-org-set-line-checkbox-prefixes-active-region-lines ()
  (with-temp-buffer
    (insert "alpha\nbeta\ngamma\n")
    (goto-char (point-min))
    (set-mark (save-excursion
                (forward-line 2)
                (point)))
    (setq transient-mark-mode t
          mark-active t)
    (org-set-line-checkbox 1)
    (should (equal (buffer-string)
                   "- [ ] alpha\n- [ ] beta\ngamma\n"))
    (should (looking-at "gamma"))))

(provide 'p3-org-test)

;;; p3-org-test.el ends here
