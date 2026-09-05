;;; p3-org-roam.el --- Org-roam workflow helpers -*- lexical-binding: t; -*-

(require 'seq)
(require 'subr-x)

(defvar org-agenda-files)
(defvar org-roam-capture-templates)
(defvar org-roam-directory)

(declare-function consult-ripgrep "consult" (dir &optional initial))
(declare-function org-agenda "org-agenda" (&optional arg keys restriction))
(declare-function org-roam-node-file "org-roam-node" (node))
(declare-function org-roam-node-insert "org-roam-node" (&optional arg &rest args))
(declare-function org-roam-node-list "org-roam-node" ())
(declare-function org-roam-node-tags "org-roam-node" (node))

(defun org-roam-generate-tagged-header ()
  (let ((tag (read-string "Enter tag: ")))
    (if (string-empty-p tag)
        (concat "#+title: ${title}\n#+category:${title}\n#+created: %U\n#+last_modified: %U\n")
      (concat "#+title: ${title}\n#+category:${title}\n#+filetags: " tag
              "\n#+created: %U\n#+last_modified: %U\n#"))))

(defun org-roam-node-insert-immediate-with-tag (arg &rest args)
  (interactive "p")
  (let ((args (cons arg args))
        (org-roam-capture-templates
         (list
          (append
           (car
            '(("t" "tagged" plain "%?"
               :if-new
               (file+head "%<%Y%m%d%H%M%S>-${slug}.org"
                          org-roam-generate-tagged-header)
               :unnarrowed t)))
           '(:immediate-finish t)))))
    (apply #'org-roam-node-insert args)))

(defun org-roam-rg-search ()
  "Search org-roam directory using consult-ripgrep. With live-preview."
  (interactive)
  (consult-ripgrep org-roam-directory))

(defun p3/org-roam-filter-by-tag (tag-name)
  (lambda (node)
    (member tag-name (org-roam-node-tags node))))

(defun p3/org-roam-list-notes ()
  (mapcar #'org-roam-node-file
          (org-roam-node-list)))

(defun p3/org-roam-list-notes-by-tag (tag-name)
  (mapcar #'org-roam-node-file
          (seq-filter
           (p3/org-roam-filter-by-tag tag-name)
           (org-roam-node-list))))

(defun p3/org-roam-get-agenda ()
  (interactive)
  (let ((tag (read-string "Enter tag: ")))
    (if (string-empty-p tag)
        (setq org-agenda-files (p3/org-roam-list-notes))
      (setq org-agenda-files (p3/org-roam-list-notes-by-tag tag))))
  (org-agenda))

(provide 'p3-org-roam)

;;; p3-org-roam.el ends here
