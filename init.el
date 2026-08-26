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

(defconst p3/lisp-directory
  (expand-file-name "lisp" user-emacs-directory))
(add-to-list 'load-path p3/lisp-directory)
(require 'p3-packages)
(p3/package-install-update-advice)

;; Package mutations can leave bytecode compiled against dependencies that
;; were still loaded from the old package graph.  Rebuild that bytecode only
;; in a fresh process, before loading the normal configuration.
(defvar p3/package-bootstrap-ready
  (condition-case err
      (progn
        (p3/package-recompile-if-needed)
        t)
    (error
     (display-warning
      'p3/package
      (format "Package recompilation failed; loading stock Emacs only: %s"
              (error-message-string err))
      :error)
     nil))
  "Non-nil when package state is safe for normal configuration loading.")

;; Bootstrap use-package itself.  If this changes package state, the package
;; preflight below deliberately leaves normal configuration loading for the
;; next fresh Emacs process.
(when p3/package-bootstrap-ready
  (p3/package-install-resilient 'use-package))

;; Keep the generated file as a cache, never as an independent source of
;; truth.  Tangling on every startup prevents config.el from drifting from
;; config.org, including after a checkout or a merge.
(require 'org)
(require 'ob-tangle)
(defconst p3/config-source
  (expand-file-name "config.org" user-emacs-directory))
(defconst p3/config-generated
  (expand-file-name "config.el" user-emacs-directory))

(defun p3/tangle-config ()
  "Tangle `p3/config-source' into `p3/config-generated'."
  (org-babel-tangle-file p3/config-source p3/config-generated))

(defun p3/load-config (&optional quiet)
  "Load the generated configuration cache."
  (load-file p3/config-generated)
  (unless quiet
    (message "Loaded %s" p3/config-source)))

(p3/tangle-config)
(if (and p3/package-bootstrap-ready
         (p3/package-preflight-config p3/config-generated))
    (progn
      (require 'use-package)
      (require 'use-package-ensure)
      (setq use-package-ensure-function #'p3/use-package-ensure
            use-package-always-ensure t)
      (p3/load-config t))
  (display-warning
   'p3/package
   (concat
    "Package state changed or could not be validated; normal configuration "
    "was not loaded. Restart Emacs after package repair; stock Emacs "
    "commands remain available in this session.")
   :warning))

(defun p3/recentf-record-current-buffer (&rest _)
  "Treat a completed Consult buffer switch as recent file access."
  (when buffer-file-name
    (require 'recentf)
    (recentf-add-file buffer-file-name)))

(with-eval-after-load 'consult
  (unless (advice-member-p #'p3/recentf-record-current-buffer #'consult-buffer)
    (advice-add #'consult-buffer :after #'p3/recentf-record-current-buffer)))

(load custom-file 'noerror 'nomessage)
