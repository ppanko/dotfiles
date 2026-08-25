;;; p3-core.el --- Shared helpers for the personal Emacs config -*- lexical-binding: t; -*-

(require 'project)

(declare-function projectile-project-root "projectile")
(declare-function p3/load-config nil (&optional quiet))

(defun p3/project-root ()
  "Return the current Projectile or built-in project root, if any."
  (or (and (fboundp 'projectile-project-root)
           (ignore-errors (projectile-project-root)))
      (when-let ((project (project-current nil)))
        (project-root project))))

(defun p3/use-project-root-as-default-dir ()
  "Use the current project root as the buffer's default directory."
  (when-let ((root (p3/project-root)))
    (setq-local default-directory root)))

(defun p3/config-visit ()
  "Visit the authoritative literate Emacs configuration."
  (interactive)
  (find-file
   (if (boundp 'p3/config-source)
       p3/config-source
     (expand-file-name "config.org" user-emacs-directory))))

(defun p3/config-reload ()
  "Tangle and reload the authoritative literate Emacs configuration."
  (interactive)
  (unless (fboundp 'p3/load-config)
    (user-error "Config loader is unavailable"))
  (p3/load-config))

(provide 'p3-core)

;;; p3-core.el ends here
