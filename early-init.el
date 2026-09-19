;;; early-init.el --- Early startup policy -*- lexical-binding: t; -*-

;; The package bootstrap in init.el repairs incomplete ELPA installs before
;; activation.  Prevent Emacs from activating packages before init.el runs.
(setq package-enable-at-startup nil)

;;; early-init.el ends here
