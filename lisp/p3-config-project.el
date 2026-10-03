;;; p3-config-project.el --- Native project configuration -*- lexical-binding: t; -*-

(require 'project)
(require 'p3-project)

(setq project-switch-commands 'p3/project-resume
      project-compilation-buffer-name-function #'p3/project-compilation-buffer-name)

(define-key project-prefix-map (kbd "c") #'p3/project-compile)

;; Route displayed visits into canonical project workspaces only while the tab
;; has one ordinary window.  A split is an explicit multi-project workspace:
;; current-window visits then stay local, and other-window visits are always
;; local.  Background `find-file-noselect' reads and reverts never route.
(dolist (command '(find-file find-file-other-window))
  (advice-remove command #'p3/project-route-file)
  (advice-remove command #'p3/project-with-file-routing)
  (advice-remove command #'p3/project-with-file-context))
(advice-add 'find-file :around #'p3/project-with-file-routing)
(advice-add 'find-file-other-window :around #'p3/project-with-file-context)

;; Apply the same distinction to already-open buffers.  Keep the lightweight
;; other-window advice so Consult can restore its preview layout before the
;; accepted buffer is displayed, without activating another project tab.
(dolist (command '(switch-to-buffer switch-to-buffer-other-window))
  (advice-remove command #'p3/project-route-buffer)
  (advice-remove command #'p3/project-keep-buffer-local))
(advice-add 'switch-to-buffer :before #'p3/project-route-buffer)
(advice-add 'switch-to-buffer-other-window :before #'p3/project-keep-buffer-local)

(advice-remove 'tab-bar-select-tab #'p3/project--after-tab-select)
(advice-add 'tab-bar-select-tab :after #'p3/project--after-tab-select)

(with-eval-after-load 'consult
  (dolist (command '(consult-buffer consult-buffer-other-window))
    (advice-remove command #'p3/project-with-buffer-preview-guard)
    (advice-add command :around #'p3/project-with-buffer-preview-guard)))

(global-set-key (kbd "C-c p") project-prefix-map)
(global-set-key (kbd "s-p") project-prefix-map)

(provide 'p3-config-project)

;;; p3-config-project.el ends here
