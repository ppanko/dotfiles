;;; p3-config-terminal.el --- Terminal configuration -*- lexical-binding: t; -*-

(require 'seq)
(require 'subr-x)
(require 'use-package)
(require 'p3-config-loader)

(defvar p3/vterm-command-map)
(defvar vterm-always-compile-module)
(defvar vterm-copy-mode-map)
(defvar vterm-environment)
(defvar vterm-kill-buffer-on-exit)
(defvar vterm-max-scrollback)
(defvar vterm-mode-map)
(defvar vterm-shell)

(declare-function p3/windows-configure-shell "p3-platform" ())
(declare-function p3/blesh-file "p3-terminal" ())
(declare-function p3/vterm "p3-terminal" (&optional new-session))
(declare-function p3/vterm-enter-copy-mode "p3-terminal" ())
(declare-function p3/vterm-mode-setup "p3-terminal" ())

(p3/config-load-module 'p3-terminal)

(p3/windows-configure-shell)

(when (eq system-type 'windows-nt)
  (global-set-key (kbd "C-x C-u") #'shell))

(when (eq system-type 'gnu/linux)
  (keymap-global-set "C-c T" p3/vterm-command-map)

  (use-package vterm
    :commands (vterm vterm-other-window)
    :hook (vterm-mode . p3/vterm-mode-setup)
    :bind (("C-x C-u" . p3/vterm)
           :map vterm-mode-map
           ("C-y" . vterm-yank)
           ("M-y" . vterm-yank-pop)
           ("C-S-v" . vterm-yank)
           ("C-S-c" . p3/vterm-enter-copy-mode)
           :map vterm-copy-mode-map
           ("C-S-c" . vterm-copy-mode-done))
    :custom
    (vterm-max-scrollback 100000)
    (vterm-kill-buffer-on-exit t)
    (vterm-always-compile-module t)
    :init
    (setq vterm-environment
          (cons (format "P3_BLESH_FILE=%s" (p3/blesh-file))
                (seq-remove
                 (lambda (entry) (string-prefix-p "P3_BLESH_FILE=" entry))
                 (and (boundp 'vterm-environment) vterm-environment)))
          vterm-shell
          (format "%s --noprofile --rcfile %s -i"
                  (shell-quote-argument "/usr/bin/bash")
                  (shell-quote-argument
                   (expand-file-name "vterm-bashrc"
                                     user-emacs-directory))))))

(provide 'p3-config-terminal)

;;; p3-config-terminal.el ends here
