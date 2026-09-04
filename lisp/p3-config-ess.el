;;; p3-config-ess.el --- ESS and R-mode configuration -*- lexical-binding: t; -*-

(require 'use-package)
(require 'p3-config-loader)

(p3/config-load-module 'p3-ess)
(declare-function p3/ess-setup "p3-ess" ())
(p3/ess-setup)

(p3/config-load-module 'p3-r-tools)

(defvar ansi-color-for-comint-mode)
(defvar company-backends)
(defvar ess-ask-for-ess-directory)
(defvar ess-style)
(defvar ess-eval-visibly)
(defvar ess-toggle-underscore)
(defvar ess-use-flymake)
(defvar ess-mode-map)
(defvar inferior-ess-r-mode-map)
(defvar flycheck-lintr-linters)
(defvar ess--command-default-timeout)
(defvar inferior-R-args)
(defvar ess-R-font-lock-keywords)
(defvar ess-gen-proc-buffer-name-function)
(defvar p3-r-command-map)

(declare-function smartparens-mode "smartparens" (&optional arg))

(keymap-global-set "C-c R" p3-r-command-map)

(defvar p3/r-company-backends
  '((:separate
     company-R-library company-R-args company-R-objects
     company-dabbrev-code
     :with company-yasnippet)
    company-capf)
  "Company completion backends used in ESS R buffers.")

(defun p3/ess-company-config ()
  "Configure Company completion for an ESS R buffer."
  (setq-local company-backends p3/r-company-backends))

(defun p3/ess-inferior-mode-setup ()
  "Apply personal defaults to an inferior ESS buffer."
  (setq-local ansi-color-for-comint-mode 'filter)
  (smartparens-mode 1))

(use-package ess-r-mode
  :ensure ess
  :hook ((inferior-ess-mode . p3/ess-inferior-mode-setup)
         (ess-r-post-run . p3-r-load-view-data-frame)
         (ess-r-mode . p3/ess-company-config)
         (ess-r-mode . p3/use-project-root-as-default-dir)
         ;; Treat "_" as part of a word when navigating across words.
         (ess-mode . (lambda () (modify-syntax-entry ?_ "w"))))
  :bind (:map ess-mode-map
              ;; Re-map ESS "run" to S-RET because of CUA mode.
              ("C-<return>" . nil)
              ("S-<return>" . ess-eval-region-or-line-visibly-and-step)
              ("C-." . p3-r-insert-pipe)
              ("C-c i" . p3-r-evaluate-library-section)
              ("C-c v" . p3-r-view-data-frame-at-point)
              ("C-c m" . p3-r-targets-make)
              ("C-c d" . p3-r-targets-make-debug)
              ("C-c l" . p3-r-targets-load-at-point)
         :map inferior-ess-r-mode-map
              ("C-c v" . p3-r-view-data-frame-at-point)
              ("C-c m" . p3-r-targets-make)
              ("C-c d" . p3-r-targets-make-debug)
              ("C-c l" . p3-r-targets-load-at-point))
  :config
  (setq ess-ask-for-ess-directory nil
        ess-style 'RStudio
        ess-eval-visibly t
        ess-toggle-underscore nil
        ess-use-flymake nil
        flycheck-lintr-linters
        "linters_with_defaults(object_name_linter(c('snake_case','camelCase')), commented_code_linter = NULL, line_length_linter(90), single_quotes_linter=NULL)"
        ess--command-default-timeout 1
        inferior-R-args "--no-save"
        ess-R-font-lock-keywords
        '((ess-R-fl-keyword:modifiers . t)
          (ess-R-fl-keyword:fun-defs . t)
          (ess-R-fl-keyword:keywords . t)
          (ess-R-fl-keyword:assign-ops)
          (ess-R-fl-keyword:constants . t)
          (ess-fl-keyword:fun-calls . t)
          (ess-fl-keyword:numbers . t)
          (ess-fl-keyword:operators . t)
          (ess-fl-keyword:delimiters . t)
          (ess-fl-keyword:= . t)
          (ess-R-fl-keyword:F&T . t)
          (ess-R-fl-keyword:%op% . t))
        ess-gen-proc-buffer-name-function
        'ess-gen-proc-buffer-name:project-or-directory))

(defun compile-rmd ()
  (set (make-local-variable 'compile-command)
       (concat "R -e \"rmarkdown::render('" buffer-file-name "')\"")))

(add-hook 'ess-mode-hook 'compile-rmd)
(add-hook 'markdown-mode-hook 'compile-rmd)

(provide 'p3-config-ess)

;;; p3-config-ess.el ends here
