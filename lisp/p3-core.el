;;; p3-core.el --- Shared helpers for the personal Emacs config -*- lexical-binding: t; -*-

(declare-function p3/load-config nil (&optional quiet))

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
