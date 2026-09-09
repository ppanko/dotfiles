;;; p3-config-project.el --- Native project configuration -*- lexical-binding: t; -*-

(require 'project)
(require 'p3-project)

(setq project-switch-commands 'p3/project-resume)

(add-hook 'find-file-hook #'p3/project-route-current-file t)

(global-set-key (kbd "C-c p") project-prefix-map)
(global-set-key (kbd "s-p") project-prefix-map)

(provide 'p3-config-project)

;;; p3-config-project.el ends here
