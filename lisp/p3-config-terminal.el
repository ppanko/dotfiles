;;; p3-config-terminal.el --- Terminal configuration -*- lexical-binding: t; -*-

(require 'p3-config-loader)

(defvar p3/project-shell-command-map)

(declare-function p3/windows-configure-shell "p3-platform" ())
(declare-function p3/project-shell "p3-terminal" (&optional new-session))

(p3/config-load-module 'p3-terminal)

(p3/windows-configure-shell)

(global-set-key (kbd "C-x C-u") #'p3/project-shell)
(keymap-global-set "C-c T" p3/project-shell-command-map)

(provide 'p3-config-terminal)

;;; p3-config-terminal.el ends here
