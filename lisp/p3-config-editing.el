;;; p3-config-editing.el --- Generic editing configuration -*- lexical-binding: t; -*-

(require 'use-package)
(require 'p3-commands)

(defvar cua-auto-tabify-rectangles)
(defvar undo-tree-visualizer-timestamps)
(defvar undo-tree-visualizer-diff)
(defvar undo-tree-history-directory-alist)
(defvar super-save-auto-save-when-idle)

(declare-function global-undo-tree-mode "undo-tree" (&optional arg))
(declare-function super-save-mode "super-save" (&optional arg))

(delete-selection-mode t)
(add-hook 'before-save-hook 'whitespace-cleanup)
(cua-mode t)
(setq cua-auto-tabify-rectangles nil)

(setq-default indent-tabs-mode nil)
(setq default-input-method "cyrillic-translit")

(use-package smartparens
  :hook (prog-mode . smartparens-mode))

(global-set-key "\C-xc" 'compile)
(global-unset-key (kbd "C-x C-z"))

(global-set-key (kbd "C-s") 'isearch-forward-regexp)
(global-set-key (kbd "C-r") 'isearch-backward-regexp)
(global-set-key (kbd "C-M-s") 'isearch-forward)
(global-set-key (kbd "C-M-r") 'isearch-backward)

(global-set-key (kbd "C-c a")
                (lambda ()
                  (interactive)
                  (align-regexp (region-beginning) (region-end)
                                "\\(\\s-*\\)\\(<-\\|=\\)" 1 1 nil)))

(global-set-key (kbd "C-c s") 'p3/region-suffix)
(global-set-key (kbd "C-c C-SPC") 'p3/newline-after-comma-or-space)
(global-set-key (kbd "C-c q") 'p3/force-quotes)
(global-set-key (kbd "M-<up>") #'move-line-up)
(global-set-key (kbd "M-<down>") #'move-line-down)

(use-package google-this)

(use-package wgrep)

(use-package undo-tree
  :diminish undo-tree-mode
  :config
  (progn
    (global-undo-tree-mode)
    (setq undo-tree-visualizer-timestamps t)
    (setq undo-tree-visualizer-diff t)
    (setq undo-tree-history-directory-alist '(("." . "~/.emacs.d/undo")))))

(use-package super-save
  :defer 1
  :diminish super-save-mode
  :config
  (super-save-mode +1)
  (setq super-save-auto-save-when-idle t))

(use-package multiple-cursors
  :bind (("C-S-c C-S-c" . mc/edit-lines)
         ("C-{" . mc/mark-next-like-this)
         ("C-}" . mc/mark-previous-like-this)
         ("C-|" . mc/mark-all-like-this)))

(provide 'p3-config-editing)

;;; p3-config-editing.el ends here
