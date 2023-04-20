;; Configure package.el to include MELPA.
(require 'package)
(add-to-list 'package-archives '("melpa" . "https://melpa.org/packages/"))
(package-initialize)

;; Ensure that use-package is installed.
;;
;; If use-package isn't already installed, it's extremely likely that this is a
;; fresh installation! So we'll want to update the package repository and
;; install use-package before loading the literate configuration.
(when (not (package-installed-p 'use-package))
  (package-refresh-contents)
  (package-install 'use-package))

(org-babel-load-file "~/.emacs.d/config.org")
(custom-set-variables
 ;; custom-set-variables was added by Custom.
 ;; If you edit it by hand, you could mess it up, so be careful.
 ;; Your init file should contain only one such instance.
 ;; If there is more than one, they won't work right.
 '(org-agenda-files nil)
 '(package-selected-packages
   '(org-ref ivy-bibtex org-roam-bibtex org-agenda workgroups2 wgrep vlf visual-fill-column visual-fill use-package undo-tree transpose-frame telephone-line synosaurus super-save smex smartparens shell-pop restart-emacs rainbow-mode projectile poly-R org-tree-slide org-superstar org-roam org-present multiple-cursors magit ivy-rich hlinum hide-mode-line helm-core google-this git-gutter-fringe git-gutter-fringe+ flycheck ess-view-data elpy doom-themes doom-modeline counsel base16-theme auto-package-update auto-compile all-the-icons-ivy all-the-icons-dired ace-window)))
(custom-set-faces
 ;; custom-set-faces was added by Custom.
 ;; If you edit it by hand, you could mess it up, so be careful.
 ;; Your init file should contain only one such instance.
 ;; If there is more than one, they won't work right.
 )
