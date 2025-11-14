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
 '(package-selected-packages
   '(jupyter workgroups2 visual-fill-column vertico use-package unicode-fonts undo-tree transpose-frame synosaurus super-save stan-mode smex smartparens ripgrep rg restart-emacs request rainbow-mode projectile poly-R org-present nerd-icons multiple-cursors marginalia magit ivy-rich hide-mode-line gptel google-this gnu-elpa-keyring-update git-gutter-fringe+ flycheck ess elpy doom-themes doom-modeline counsel-tramp citar-org-roam auto-package-update auto-compile async all-the-icons-ivy all-the-icons-dired ace-window)))
(custom-set-faces
 ;; custom-set-faces was added by Custom.
 ;; If you edit it by hand, you could mess it up, so be careful.
 ;; Your init file should contain only one such instance.
 ;; If there is more than one, they won't work right.
 )
