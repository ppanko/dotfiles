;;; p3-config-org.el --- Org configuration -*- lexical-binding: t; -*-

(require 'use-package)
(require 'p3-config-loader)

(defvar org-agenda-sorting-strategy)
(defvar org-confirm-babel-evaluate)
(defvar org-ellipsis)
(defvar org-file-apps)
(defvar org-hide-emphasis-markers)
(defvar org-mode-map)
(defvar org-src-fontify-natively)
(defvar org-src-tab-acts-natively)
(defvar org-startup-folded)
(defvar org-todo-keyword-faces)
(defvar org-todo-keywords)
(defvar time-stamp-active)
(defvar time-stamp-end)
(defvar time-stamp-format)
(defvar time-stamp-start)

(declare-function org-babel-do-load-languages "ob-core" (sym value))
(declare-function p3/org-sort-todos "p3-org" ())
(declare-function p3-org-export-setup "p3-org-export" ())

(p3/config-load-module 'p3-org)

(setq org-startup-folded 'content)

(add-hook 'org-mode-hook
          (lambda ()
            (setq-local time-stamp-active t
                        time-stamp-start "#\\+last_modified:[ \t]*"
                        time-stamp-end "$"
                        time-stamp-format "\[%Y-%m-%d %3a %02H:%02M\]")
            (add-hook 'before-save-hook 'time-stamp nil 'local)))

(use-package org
  :defer t
  :bind (:map org-mode-map
              ("C-c s" lambda () (interactive)
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
        org-ellipsis " ↴"))

(define-key org-mode-map (kbd "C-c C-x C-o") #'p3/org-sort-todos)

(use-package p3-org-export
  :ensure nil
  :demand t
  :config
  (p3-org-export-setup))

(when (eq system-type 'gnu/linux)
  (add-to-list 'org-file-apps '("pdf" . "evince %s")))

(setq org-todo-keywords
      '((sequence "TODO(t)" "WAIT(w)" "|" "DONE(d)"))
      org-todo-keyword-faces
      '(("WAIT" . "DarkOrange")))

(use-package org-agenda
  :ensure nil
  :config
  (setq org-agenda-sorting-strategy '(priority-down)))

(provide 'p3-config-org)

;;; p3-config-org.el ends here
