;;; p3-config-git.el --- Git and Magit configuration -*- lexical-binding: t; -*-

(require 'use-package)
(require 'p3-config-loader)
(p3/config-load-module 'p3-git)

(defvar git-gutter-fr+-side)
(declare-function global-git-gutter+-mode "git-gutter-fringe+" (&optional arg))

(global-set-key (kbd "C-c C-g") #'p3/git-commit-and-push-emacs-config)

(defvar p3/magit-command-map
  (let ((map (make-sparse-keymap)))
    ;; Keep the shortcuts from the personal Magit notes, with a few
    ;; read-only/navigation commands alongside them.
    (define-key map (kbd "s") #'magit-stage-files)
    (define-key map (kbd "c") #'magit-commit-create)
    (define-key map (kbd "f") #'magit-pull)
    (define-key map (kbd "m") #'magit-merge)
    (define-key map (kbd "P") #'magit-push-current-to-pushremote)
    (define-key map (kbd "a") #'magit-remote-add)
    (define-key map (kbd "g") #'magit-status)
    (define-key map (kbd "l") #'magit-log-current)
    (define-key map (kbd "d") #'magit-diff)
    (define-key map (kbd "b") #'magit-blame)
    (define-key map (kbd "q") #'close-magit-buffers)
    map)
  "Personal shortcuts for common Magit commands.")

(use-package magit
  :defer t
  :bind ("C-c m" . p3/magit-command-map)
  :config
  (with-eval-after-load 'magit-mode
    (add-hook 'after-save-hook 'magit-after-save-refresh-status t)))

(use-package git-gutter-fringe+
  :init (global-git-gutter+-mode)
  :diminish git-gutter+-mode
  :config (setq git-gutter-fr+-side 'right-fringe))

(setq-default right-fringe-width 20)

(provide 'p3-config-git)

;;; p3-config-git.el ends here
