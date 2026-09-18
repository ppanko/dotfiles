;; Keep machine-local Custom state out of the portable configuration.
;; Establish this before package.el can persist any Custom/package state.
(setq custom-file (expand-file-name "custom.el" user-emacs-directory))

;; Local bootstrap helpers must be available before package.el decides whether
;; an existing ELPA directory is healthy enough to reuse.
(defconst p3/lisp-directory
  (expand-file-name "lisp" user-emacs-directory))
(add-to-list 'load-path p3/lisp-directory)

(require 'p3-package)
(p3/package-setup)

;; Bootstrap use-package itself before loading the literate configuration.
(p3/package-install-resilient 'use-package)
(require 'use-package)
(require 'use-package-ensure)

(setq use-package-ensure-function #'p3/use-package-ensure
      use-package-always-ensure t)

;; Local .elc files are machine-local and may lag tracked source after an update.
;; Prefer newer source before requiring any local startup library.
(setq load-prefer-newer t)

;; Establish native project semantics before the literate config or any
;; project-aware package has a chance to populate `project.el' caches.
(require 'p3-project)

;; Load the generated literate-config cache, rebuilding it only when its
;; embedded source fingerprint no longer matches config.org.
(require 'p3-config-loader)
(p3/config-load)

(defun p3/recentf-record-current-buffer (&rest _)
  "Treat a completed Consult buffer switch as recent file access."
  (when buffer-file-name
    (require 'recentf)
    (recentf-add-file buffer-file-name)))

(with-eval-after-load 'consult
  (unless (advice-member-p #'p3/recentf-record-current-buffer #'consult-buffer)
    (advice-add #'consult-buffer :after #'p3/recentf-record-current-buffer)))

(load custom-file 'noerror 'nomessage)
