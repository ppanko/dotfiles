;;; p3-config-project.el --- Native project configuration -*- lexical-binding: t; -*-

(require 'project)
(require 'p3-project)

(setq project-switch-commands 'p3/project-resume
      project-compilation-buffer-name-function #'p3/project-compilation-buffer-name)

(define-key project-prefix-map (kbd "c") #'p3/project-compile)

;; Route only file visits that are about to be displayed.  Keep the resolved
;; project root dynamically available while the visit runs so downstream
;; project-aware hooks can reuse it.  Background `find-file-noselect' reads and
;; reverts must not change workspaces.
(dolist (command '(find-file find-file-other-window))
  (advice-remove command #'p3/project-route-file)
  (advice-remove command #'p3/project-with-file-routing)
  (advice-add command :around #'p3/project-with-file-routing))

;; Route already-open file buffers as they are displayed.  Consult preview
;; switches use `norecord' and are guarded separately below.
(dolist (command '(switch-to-buffer switch-to-buffer-other-window))
  (advice-remove command #'p3/project-route-buffer)
  (advice-add command :before #'p3/project-route-buffer))

(with-eval-after-load 'consult
  (dolist (command '(consult-buffer consult-buffer-other-window))
    (advice-remove command #'p3/project-with-buffer-preview-guard)
    (advice-add command :around #'p3/project-with-buffer-preview-guard)))

(global-set-key (kbd "C-c p") project-prefix-map)
(global-set-key (kbd "s-p") project-prefix-map)

(provide 'p3-config-project)

;;; p3-config-project.el ends here
