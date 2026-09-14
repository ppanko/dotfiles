;;; p3-core.el --- Shared helpers for the personal Emacs config -*- lexical-binding: t; -*-

(require 'p3-config-loader)

(defun p3/state-directory ()
  "Return the durable machine-local state directory for this Emacs config."
  (let ((platform-root
         (cond
          ((eq system-type 'windows-nt) (getenv "LOCALAPPDATA"))
          ((eq system-type 'gnu/linux) (getenv "XDG_STATE_HOME")))))
    (file-name-as-directory
     (if (and platform-root (not (string= platform-root "")))
         (expand-file-name
          (if (eq system-type 'windows-nt) "Emacs" "emacs")
          platform-root)
       (expand-file-name "~/.local/state/emacs/")))))

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
