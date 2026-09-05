;;; p3-config-editing.el --- Generic editing configuration -*- lexical-binding: t; -*-

(require 'use-package)
(require 'p3-commands)

(defvar cua-auto-tabify-rectangles)
(defvar undo-tree-visualizer-timestamps)
(defvar undo-tree-visualizer-diff)
(defvar undo-tree-history-directory-alist)
(defvar super-save-auto-save-when-idle)
(defvar synosaurus-choose-method)
(defvar yas-snippet-dirs)
(defvar flycheck-global-modes)
(defvar flycheck-checker-error-threshold)
(defvar p3/windows-hunspell-program)
(defvar p3/windows-hunspell-dictionary-directory)
(defvar ispell-program-name)
(defvar ispell-local-dictionary)
(defvar ispell-dictionary)
(defvar ispell-local-dictionary-alist)

(declare-function global-undo-tree-mode "undo-tree" (&optional arg))
(declare-function super-save-mode "super-save" (&optional arg))
(declare-function synosaurus-mode "synosaurus" (&optional arg))
(declare-function yas-global-mode "yasnippet" (&optional arg))
(declare-function global-flycheck-mode "flycheck" (&optional arg))
(declare-function rainbow-mode "rainbow-mode" (&optional arg))

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

(defun p3/config-editing-setup-thesaurus-and-snippets ()
  "Configure generic thesaurus and snippet support."
  (use-package synosaurus
    :diminish synosaurus-mode
    :init    (synosaurus-mode)
    :config  (setq synosaurus-choose-method 'popup))

  (use-package yasnippet
    :init
    (yas-global-mode 1)
    :config
    (add-to-list 'yas-snippet-dirs "~/.emacs.d/snippets")))

(defun p3/config-editing-setup-diagnostics ()
  "Configure global Flycheck behavior."
  (use-package flycheck
    :hook (after-init . global-flycheck-mode)
    :config
    (setq flycheck-global-modes '(not LaTeX-mode latex-mode org-mode))
    (setq flycheck-checker-error-threshold 1000)))

(defun p3/config-editing-setup-color-helper ()
  "Configure color previews for programming buffers."
  (use-package rainbow-mode
    :config
    (add-hook 'prog-mode-hook #'rainbow-mode)))

(defun p3/config-editing-setup-spelling ()
  "Configure platform-specific Hunspell and Ispell behavior."
  (use-package ispell
    :defer nil
    :ensure nil
    :init
    (cond
     ((eq system-type 'windows-nt)
      (when p3/windows-hunspell-program
        (setq ispell-program-name p3/windows-hunspell-program))
      (when p3/windows-hunspell-dictionary-directory
        (setenv "DICTPATH" p3/windows-hunspell-dictionary-directory))
      (setenv "DICTIONARY" "en_US"))
     ((eq system-type 'gnu/linux)
      (setq ispell-program-name "hunspell")))
    :config
    (setq ispell-local-dictionary "en_US"
          ispell-dictionary "english"
          ispell-local-dictionary-alist
          '(("en_US" "[[:alpha:]]" "[^[:alpha:]]" "[']" nil ("-d" "en_US") nil utf-8)))))

(provide 'p3-config-editing)

;;; p3-config-editing.el ends here
