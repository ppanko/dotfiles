;; Keep machine-local Custom state out of the portable configuration.
;; Establish this before package.el can persist any Custom/package state.
(setq custom-file (expand-file-name "custom.el" user-emacs-directory))

;; Configure package.el.  Missing packages are bootstrapped automatically;
;; upgrades are deliberately handled through the package menu.
(require 'package)
(setq package-archives
      '(("gnu" . "https://elpa.gnu.org/packages/")
        ("nongnu" . "https://elpa.nongnu.org/nongnu/")
        ("melpa" . "https://melpa.org/packages/"))
      package-archive-priorities
      '(("gnu" . 30)
        ("nongnu" . 20)
        ("melpa" . 10)))
(package-initialize)

(defvar p3/package-refresh-attempted nil
  "Non-nil after this Emacs session has attempted an automatic archive refresh.")

(defun p3/package-refresh-once ()
  "Refresh package metadata at most once automatically per Emacs session."
  (unless p3/package-refresh-attempted
    (setq p3/package-refresh-attempted t)
    (package-refresh-contents)))

(defun p3/package-prepare-pinned-package (package)
  "Reload archive metadata needed for pinned PACKAGE, if any."
  (when (assoc package (bound-and-true-p package-pinned-packages))
    (package-read-all-archive-contents)))

(defun p3/package-install-resilient (package)
  "Install PACKAGE, refreshing stale archive metadata once on failure."
  (unless (package-installed-p package)
    (p3/package-prepare-pinned-package package)
    (condition-case _first-error
        (package-install package t)
      (error
       (p3/package-refresh-once)
       (p3/package-prepare-pinned-package package)
       (package-install package t)))))

;; Bootstrap use-package itself before loading the literate configuration.
(p3/package-install-resilient 'use-package)
(require 'use-package)
(require 'use-package-ensure)

(defun p3/use-package-ensure (name args _state)
  "Ensure packages requested by use-package NAME with normalized ARGS."
  (dolist (ensure args)
    (let ((package (if (eq ensure t)
                       (use-package-as-symbol name)
                     ensure)))
      (when package
        (when (consp package)
          (use-package-pin-package (car package) (cdr package))
          (setq package (car package)))
        (condition-case err
            (p3/package-install-resilient package)
          (error
           (display-warning
            'use-package
            (format "Failed to install %s: %s"
                    package
                    (error-message-string err))
            :error))))))
  t)

(setq use-package-ensure-function #'p3/use-package-ensure
      use-package-always-ensure t)

;; Keep the generated file as a cache, never as an independent source of
;; truth.  Tangling on every startup prevents config.el from drifting from
;; config.org, including after a checkout or a merge.
(require 'org)
(require 'ob-tangle)
(defconst p3/config-source
  (expand-file-name "config.org" user-emacs-directory))
(defconst p3/config-generated
  (expand-file-name "config.el" user-emacs-directory))
(defconst p3/lisp-directory
  (expand-file-name "lisp" user-emacs-directory))
(add-to-list 'load-path p3/lisp-directory)

(defun p3/load-config (&optional quiet)
  "Tangle and load the literate configuration from `p3/config-source'."
  (org-babel-tangle-file p3/config-source p3/config-generated)
  (load-file p3/config-generated)
  (unless quiet
    (message "Loaded %s" p3/config-source)))
(p3/load-config t)

(defun p3/recentf-record-current-buffer (&rest _)
  "Treat a completed Consult buffer switch as recent file access."
  (when buffer-file-name
    (require 'recentf)
    (recentf-add-file buffer-file-name)))

(with-eval-after-load 'consult
  (unless (advice-member-p #'p3/recentf-record-current-buffer #'consult-buffer)
    (advice-add #'consult-buffer :after #'p3/recentf-record-current-buffer)))

(load custom-file 'noerror 'nomessage)
