;;; p3-config-python.el --- Python configuration -*- lexical-binding: t; -*-

(require 'use-package)
(require 'p3-config-loader)

(p3/config-load-module 'p3-python)

(defvar python-mode-map)
(defvar python-ts-mode-map)
(defvar eglot-mode-map)
(defvar flycheck-python-flake8-executable)

(use-package python
  :ensure nil
  :bind (:map python-mode-map
              ("C-<return>" . nil)
              ("S-<return>" . python-shell-send-statement)
              ("C-c C-c" . p3/python-send-region-or-paragraph-and-step)
              ("C-<up>" . backward-paragraph)
              ("C-<down>" . forward-paragraph)
              ("C-c C-z" . p3/python-display-shell))
  :hook ((python-mode . p3/python-setup-project-interpreter)
         (python-mode . p3/python-eglot-ensure)
         (python-mode . p3/python-disable-flycheck))
  :custom
  (python-indent-guess-indent-offset t)
  (python-indent-guess-indent-offset-verbose nil)
  (python-shell-interpreter (if (eq system-type 'windows-nt) "python" "python3"))
  (python-shell-interpreter-args "-i"))

;; Emacs 29+ uses the tree-sitter mode when it is available.
(when (fboundp 'python-ts-mode)
  (add-to-list 'auto-mode-alist '("\\.py\\'" . python-ts-mode))
  (add-hook 'python-ts-mode-hook #'p3/python-setup-project-interpreter)
  (add-hook 'python-ts-mode-hook #'p3/python-eglot-ensure)
  (add-hook 'python-ts-mode-hook #'p3/python-disable-flycheck)
  (with-eval-after-load 'python
    (define-key python-ts-mode-map (kbd "C-<return>") nil)
    (define-key python-ts-mode-map (kbd "S-<return>") #'python-shell-send-statement)
    (define-key python-ts-mode-map (kbd "C-c C-c") #'p3/python-send-region-or-paragraph-and-step)
    (define-key python-ts-mode-map (kbd "C-<up>") #'backward-paragraph)
    (define-key python-ts-mode-map (kbd "C-<down>") #'forward-paragraph)
    (define-key python-ts-mode-map (kbd "C-c C-z") #'p3/python-display-shell)))

(use-package eglot
  :ensure t
  :commands eglot-ensure
  :bind (:map eglot-mode-map
              ("C-c l r" . eglot-rename)
              ("C-c l a" . eglot-code-actions)
              ("C-c l f" . eglot-format)))

(setq flycheck-python-flake8-executable "flake8")

(provide 'p3-config-python)

;;; p3-config-python.el ends here
