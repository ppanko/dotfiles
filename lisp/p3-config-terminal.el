;;; p3-config-terminal.el --- Terminal configuration -*- lexical-binding: t; -*-

(require 'use-package)
(require 'p3-config-loader)

(defvar p3/project-shell-command-map)

(declare-function p3/windows-configure-shell "p3-platform" ())
(declare-function p3/project-shell "p3-terminal" (&optional new-session))
(declare-function eshell-syntax-highlighting-global-mode
                  "eshell-syntax-highlighting" (&optional arg))
(declare-function eat-eshell-mode "eat" (&optional arg))

(p3/config-load-module 'p3-terminal)

;; Keep ordinary `M-x shell' working on Windows.  The project-shell surface
;; below is Eshell-backed and no longer depends on this Comint configuration.
(p3/windows-configure-shell)

(use-package eshell-syntax-highlighting
  :after esh-mode
  :config
  (eshell-syntax-highlighting-global-mode 1))

(use-package eat
  :after eshell
  :custom
  (eat-eshell-fallback-if-stty-not-available t)
  :config
  (eat-eshell-mode 1))

(global-set-key (kbd "C-x C-u") #'p3/project-shell)
(keymap-global-set "C-c T" p3/project-shell-command-map)

(provide 'p3-config-terminal)

;;; p3-config-terminal.el ends here
