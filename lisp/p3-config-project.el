;;; p3-config-project.el --- Native project configuration -*- lexical-binding: t; -*-

(require 'project)
(require 'p3-project)

(setq project-switch-commands 'p3/project-resume)

;; Route only file visits that are about to be displayed.  Background
;; `find-file-noselect' reads and reverts must not change workspaces.
(dolist (command '(find-file find-file-other-window find-file-read-only))
  (advice-remove command #'p3/project-route-file)
  (advice-add command :before #'p3/project-route-file))

(global-set-key (kbd "C-c p") project-prefix-map)
(global-set-key (kbd "s-p") project-prefix-map)

(provide 'p3-config-project)

;;; p3-config-project.el ends here
