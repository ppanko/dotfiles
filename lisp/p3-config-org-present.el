;;; p3-config-org-present.el --- Org presentation configuration -*- lexical-binding: t; -*-

(require 'use-package)
(require 'p3-config-loader)

(defvar org-mode-map)
(defvar org-present-mode-keymap)
(defvar org-present-text-scale)

(use-package hide-mode-line
  :after (org-present))

(use-package visual-fill-column)

(p3/config-load-module 'p3-org-present)

(use-package org-present
  :bind ((:map org-mode-map
               ("C-c P" . p3/org-present-start))
         (:map org-present-mode-keymap
               ("C-c C-j" . p3/org-present-next)
               ("C-c C-k" . p3/org-present-prev)
               ("SPC" . p3/org-present-next)
               ("<backspace>" . p3/org-present-prev)
               ("n" . p3/org-present-next)
               ("p" . p3/org-present-prev)
               ("f" . p3/org-present-toggle-fullscreen)
               ("q" . org-present-quit)))
  :hook ((org-present-mode . p3/org-present-hook)
         (org-present-mode-quit . p3/org-present-quit-hook))
  :config
  (setq org-present-text-scale 4))

(provide 'p3-config-org-present)

;;; p3-config-org-present.el ends here
