;;; p3-config-completion.el --- Completion and search configuration -*- lexical-binding: t; -*-

(require 'use-package)

(defvar company-dabbrev-downcase)
(defvar xref-show-xrefs-function)
(defvar xref-show-definitions-function)

(declare-function vertico-mode "vertico" (&optional arg))
(declare-function vertico-repeat-save "vertico-repeat" ())
(declare-function marginalia-mode "marginalia" (&optional arg))
(declare-function consult-line "consult" (&optional initial start))
(declare-function consult-line-multi "consult" (query &optional initial))
(declare-function consult-ripgrep "consult" (&optional directory initial))
(declare-function consult-xref "consult" (&rest args))
(declare-function consult-register-format "consult" (register preview))
(declare-function embark-prefix-help-command "embark" ())

(use-package savehist
  :ensure nil
  :custom
  (history-length 100)
  :init
  (savehist-mode 1))

(use-package vertico
  :custom
  (vertico-cycle t)
  (vertico-sort-function #'vertico-sort-history-length-alpha)
  :init
  (vertico-mode 1)
  :config
  (require 'vertico-repeat)
  (add-hook 'minibuffer-setup-hook #'vertico-repeat-save))

(use-package orderless
  :custom
  (completion-styles '(orderless basic))
  (completion-category-defaults nil)
  (completion-category-overrides
   '((file (styles partial-completion)))))

(use-package marginalia
  :bind (:map minibuffer-local-map
              ("M-A" . marginalia-cycle))
  :init
  (marginalia-mode 1))

(defun p3/consult-r-doc-chapter-search ()
  "Search the current buffer for an R documentation chapter marker."
  (interactive)
  (consult-line "#' ### [0-9]+\\."))

(defun p3/consult-line-all ()
  "Search for a matching line across all live buffers."
  (interactive)
  (consult-line-multi t))

(use-package consult
  :bind (("M-x" . execute-extended-command)
         ("M-X" . execute-extended-command-for-buffer)
         ("C-s" . consult-line)
         ("C-r" . p3/consult-line-all)
         ("C-c C-r" . vertico-repeat)
         ("C-c h" . p3/consult-r-doc-chapter-search)
         ("C-x b" . consult-buffer)
         ("C-x B" . consult-buffer-other-window)
         ("M-y" . consult-yank-pop))
  :init
  (setq register-preview-delay 0.5
        register-preview-function #'consult-register-format
        xref-show-xrefs-function #'consult-xref
        xref-show-definitions-function #'consult-xref))

(use-package embark
  :bind (("C-." . embark-act)
         ("C-;" . embark-dwim)
         ("C-h B" . embark-bindings))
  :init
  (setq prefix-help-command #'embark-prefix-help-command))

(use-package embark-consult
  :after (embark consult)
  :hook (embark-collect-mode . consult-preview-at-point-mode))

(use-package company
  :hook (after-init . global-company-mode)
  :config
  (setq company-dabbrev-downcase nil))

(provide 'p3-config-completion)

;;; p3-config-completion.el ends here
