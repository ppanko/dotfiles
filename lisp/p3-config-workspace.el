;;; p3-config-workspace.el --- Window, buffer, and navigation configuration -*- lexical-binding: t; -*-

(require 'use-package)
(require 'p3-commands)

(declare-function winner-mode "winner" (&optional arg))

(use-package transpose-frame
  :defer t
  :bind ("C-c t" . transpose-frame))

(add-to-list
 'display-buffer-alist
 '((major-mode . inferior-ess-r-mode)
   (display-buffer-reuse-mode-window
    display-buffer-in-side-window)
   (side . right)
   (slot . 1)
   (window-width . 0.5)
   (reusable-frames . visible)))

(use-package ace-window
  :bind ("M-o" . ace-window))

(use-package winner
  :ensure nil
  :init
  (winner-mode 1))

(use-package restart-emacs)

(use-package avy
  :bind (("M-s" . avy-goto-word-1)))

(when (eq system-type 'windows-nt)
  (progn
    (global-set-key (kbd "C-M-<left>") 'shrink-window-horizontally)
    (global-set-key (kbd "C-M-<right>") 'enlarge-window-horizontally)
    (global-set-key (kbd "C-M-<down>") 'shrink-window)
    (global-set-key (kbd "C-M-<up>") 'enlarge-window)))

(when (eq system-type 'gnu/linux)
  (progn
    (global-set-key (kbd "C-s-<left>") 'shrink-window-horizontally)
    (global-set-key (kbd "C-s-<right>") 'enlarge-window-horizontally)
    (global-set-key (kbd "C-s-<down>") 'shrink-window)
    (global-set-key (kbd "C-s-<up>") 'enlarge-window)))

(global-set-key (kbd "C-c k") 'kill-buffer-and-window)
(global-set-key (kbd "C-x C-k") 'p3/save-kill-other-buffers)

(provide 'p3-config-workspace)

;;; p3-config-workspace.el ends here
