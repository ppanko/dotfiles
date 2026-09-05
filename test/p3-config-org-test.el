;;; p3-config-org-test.el --- Org configuration boundary tests -*- lexical-binding: t; -*-

(require 'ert)
(require 'seq)

(defconst p3-config-org-test--root
  (file-name-directory
   (directory-file-name
    (file-name-directory (or load-file-name buffer-file-name))))
  "Root of the Emacs configuration under test.")

(defun p3-config-org-test--path (relative)
  "Return RELATIVE under the repository root."
  (expand-file-name relative p3-config-org-test--root))

(defun p3-config-org-test--contents (relative)
  "Return contents of repository file RELATIVE."
  (with-temp-buffer
    (insert-file-contents (p3-config-org-test--path relative))
    (buffer-string)))

(defun p3-config-org-test--forms (relative)
  "Read all top-level Lisp forms from RELATIVE."
  (with-temp-buffer
    (insert-file-contents (p3-config-org-test--path relative))
    (goto-char (point-min))
    (let (forms)
      (condition-case nil
          (while t
            (push (read (current-buffer)) forms))
        (end-of-file nil))
      (nreverse forms))))

(defun p3-config-org-test--use-package-form (package)
  "Return the `use-package' form for PACKAGE."
  (seq-find
   (lambda (form)
     (and (consp form)
          (eq (car form) 'use-package)
          (eq (cadr form) package)))
   (p3-config-org-test--forms "lisp/p3-config-org.el")))

(ert-deftest p3-config-org-loads-core-behavior-before-binding-it ()
  (let* ((forms (p3-config-org-test--forms "lisp/p3-config-org.el"))
         (behavior (seq-position
                    forms '(p3/config-load-module 'p3-org) #'equal))
         (binding (seq-position
                   forms
                   '(define-key org-mode-map
                      (kbd "C-c C-x C-o")
                      #'p3/org-sort-todos)
                   #'equal)))
    (should (integerp behavior))
    (should (integerp binding))
    (should (< behavior binding))))

(ert-deftest p3-config-org-preserves-core-settings-and-timestamp-hook ()
  (let ((forms (p3-config-org-test--forms "lisp/p3-config-org.el")))
    (should (member '(setq org-startup-folded 'content) forms))
    (should
     (member
      '(add-hook 'org-mode-hook
         (lambda nil
           (setq-local time-stamp-active t
                       time-stamp-start "#\\+last_modified:[ \t]*"
                       time-stamp-end "$"
                       time-stamp-format "\[%Y-%m-%d %3a %02H:%02M\]")
           (add-hook 'before-save-hook 'time-stamp nil 'local)))
      forms))
    (should
     (member
      '(setq org-todo-keywords
             '((sequence "TODO(t)" "WAIT(w)" "|" "DONE(d)"))
             org-todo-keyword-faces
             '(("WAIT" . "DarkOrange")))
      forms))))

(ert-deftest p3-config-org-preserves-org-package-and-babel-wiring ()
  (should
   (equal
    (p3-config-org-test--use-package-form 'org)
    '(use-package org
       :defer t
       :bind (:map org-mode-map
                   ("C-c s" lambda nil (interactive)
                    (insert "#+BEGIN_SRC emacs-lisp\n#+END_SRC")))
       :hook ((org-mode . flyspell-mode)
              (org-mode . visual-line-mode)
              (org-mode . org-indent-mode))
       :init
       (org-babel-do-load-languages
        'org-babel-load-languages
        '((emacs-lisp .t)
          (R . t)
          (C . t)
          (python . t)
          (latex . t)
          (shell . t)))
       :config
       (setq org-confirm-babel-evaluate t
             org-src-fontify-natively t
             org-src-tab-acts-natively t
             org-hide-emphasis-markers t
             org-ellipsis " ↴")))))

(ert-deftest p3-config-org-preserves-export-pdf-and-agenda-wiring ()
  (let* ((forms (p3-config-org-test--forms "lisp/p3-config-org.el"))
         (require-position
          (seq-position forms '(require 'p3-org-export) #'equal))
         (package-form (p3-config-org-test--use-package-form 'p3-org-export))
         (package-position (seq-position forms package-form #'equal)))
    (should (integerp require-position))
    (should (integerp package-position))
    (should (< require-position package-position))
    (should
     (equal
      package-form
      '(use-package p3-org-export
         :ensure nil
         :demand t
         :config
         (p3-org-export-setup))))
    (should-not (member '(p3/config-load-module 'p3-org-export) forms))
    (should
     (member
      '(when (eq system-type 'gnu/linux)
         (add-to-list 'org-file-apps '("pdf" . "evince %s")))
      forms))
    (should
     (equal
      (p3-config-org-test--use-package-form 'org-agenda)
      '(use-package org-agenda
         :ensure nil
         :config
         (setq org-agenda-sorting-strategy '(priority-down)))))))

(provide 'p3-config-org-test)

;;; p3-config-org-test.el ends here
