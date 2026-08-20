;; Configure package.el.  Missing packages are bootstrapped automatically;
;; upgrades are deliberately handled through the package menu.
(require 'package)
(add-to-list 'package-archives '("gnu" . "https://elpa.gnu.org/packages/") t)
(add-to-list 'package-archives '("melpa" . "https://melpa.org/packages/"))
(package-initialize)

;; Keep machine-local Custom state out of the portable configuration.
(setq custom-file (expand-file-name "custom.el" user-emacs-directory))

;; Ensure that use-package is installed.
;;
;; If use-package isn't already installed, it's extremely likely that this is a
;; fresh installation! So we'll want to update the package repository and
;; install use-package before loading the literate configuration.
(unless (package-installed-p 'use-package)
  (unless package-archive-contents
    (package-refresh-contents))
  (package-install 'use-package))

;; Keep the generated file as a cache, never as an independent source of
;; truth.  Tangling on every startup prevents config.el from drifting from
;; config.org, including after a checkout or a merge.
(require 'org)
(require 'ob-tangle)
(defconst p3/config-source
  (expand-file-name "config.org" user-emacs-directory))
(defconst p3/config-generated
  (expand-file-name "config.el" user-emacs-directory))
(defun p3/load-config (&optional quiet)
  "Tangle and load the literate configuration from `p3/config-source'."
  (org-babel-tangle-file p3/config-source p3/config-generated)
  (load-file p3/config-generated)
  (unless quiet
    (message "Loaded %s" p3/config-source)))
(p3/load-config t)
(load custom-file 'noerror 'nomessage)
