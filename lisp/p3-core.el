;;; p3-core.el --- Shared helpers for the personal Emacs config -*- lexical-binding: t; -*-

(require 'p3-config-loader)

(defun p3/config-visit ()
  "Visit the authoritative literate Emacs configuration."
  (interactive)
  (find-file p3/config-source))

(defun p3/config-reload ()
  "Rebuild and reload the authoritative literate Emacs configuration."
  (interactive)
  (p3/config-build)
  (p3/config-load-generated)
  (message "Reloaded %s" p3/config-source))

(provide 'p3-core)

;;; p3-core.el ends here
