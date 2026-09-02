;;; p3-project.el --- Shared project identity for the personal Emacs config -*- lexical-binding: t; -*-

(require 'project)

(unless (boundp 'project-vc-extra-root-markers)
  (error "P3 project support requires Emacs 29 or newer"))

(add-to-list 'project-vc-extra-root-markers ".projectile")

(defun p3/project-root ()
  "Return the current built-in `project.el' root, if any."
  (when-let ((project (project-current nil)))
    (project-root project)))

(defun p3/use-project-root-as-default-dir ()
  "Use the current project root as the buffer's default directory."
  (when-let ((root (p3/project-root)))
    (setq-local default-directory root)))

(provide 'p3-project)

;;; p3-project.el ends here
