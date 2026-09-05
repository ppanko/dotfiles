;;; p3-config-org-roam.el --- Org-roam configuration -*- lexical-binding: t; -*-

(require 'use-package)
(require 'p3-config-loader)

(defvar org-roam-capture-templates)
(defvar org-roam-completion-everywhere)
(defvar org-roam-completion-system)
(defvar org-roam-dailies-capture-templates)
(defvar org-roam-dailies-directory)
(defvar org-roam-database-connector)
(defvar org-roam-directory)
(defvar org-roam-node-display-template)

(declare-function org-roam-db-autosync-mode "org-roam-db" (&optional arg))
(declare-function org-roam-node-insert-immediate-with-tag "p3-org-roam" (arg &rest args))
(declare-function org-roam-rg-search "p3-org-roam" ())
(declare-function p3/org-roam-get-agenda "p3-org-roam" ())

(p3/config-load-module 'p3-org-roam)

(use-package org-roam
  :hook
  (after-init . org-roam-mode)
  :custom
  (org-roam-database-connector 'sqlite-builtin)
  (org-roam-directory "~/org/notes/roam/")
  (org-roam-completion-everywhere t)
  (org-roam-completion-system 'default)
  (org-roam-capture-templates
   '(("d" "default" plain "%?"
      :if-new
      (file+head "%<%Y%m%d%H%M%S>-${slug}.org"
                 "#+title: ${title}\n#+category:${title}\n#+created: %U\n#+last_modified: %U\n")
      :unnarrowed t)
     ("n" "literature note" plain "* Heading\n %?"
      :target
      (file+head
       "%(expand-file-name (or citar-org-roam-subdir \"\") org-roam-directory)/${citar-citekey}.org"
       "#+title: ${citar-citekey} (${citar-date}). ${note-title}.\n#+created: %U\n#+last_modified: %U\n\n")
      :unnarrowed t)))
  (org-roam-dailies-directory "journal/")
  (org-roam-dailies-capture-templates
   '(("d" "default" entry "* %<%I:%M %p>: %?"
      :target
      (file+head "%<%Y-%m-%d>.org"
                 "#+title: %<%Y-%m-%d %a>\n#+created: %U\n#+last_modified: %U\n"))))
  :bind (("C-c n l" . org-roam-buffer-toggle)
         ("C-c n f" . org-roam-node-find)
         ("C-c n g" . org-roam-graph)
         ("C-c n i" . org-roam-node-insert)
         ("C-c n c" . org-roam-capture)
         ("C-c n n" . org-roam-node-insert-immediate-with-tag)
         ("C-c n s" . org-roam-rg-search)
         ("C-c n d" . org-roam-dailies-goto-today)
         ("C-c n t" . org-roam-dailies-capture-today)
         ("C-c n C-t" . org-roam-tag-add)
         ("C-c n a" . p3/org-roam-get-agenda))
  :config
  (setq org-roam-node-display-template
        (concat "${title:*} "
                (propertize "${tags:10}" 'face 'org-tag)))
  (org-roam-db-autosync-mode))

(provide 'p3-config-org-roam)

;;; p3-config-org-roam.el ends here
