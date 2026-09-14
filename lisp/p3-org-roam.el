;;; p3-org-roam.el --- Org-roam workflow helpers

(require 'org)
(require 'p3-project)
(require 'seq)
(require 'subr-x)

(defvar org-agenda-files)
(defvar org-roam-capture-templates)
(defvar org-roam-directory)

(defvar p3/org-roam-project-associations nil
  "Machine-local normalized project-root to Org-roam hub-ID mappings.")

(declare-function consult-ripgrep "consult" (dir &optional initial))
(declare-function org-agenda "org-agenda" (&optional arg keys restriction))
(declare-function org-roam-node-file "org-roam-node" (node))
(declare-function org-roam-node-from-id "org-roam-node" (id))
(declare-function org-roam-node-id "org-roam-node" (node))
(declare-function org-roam-node-insert "org-roam-node" (&optional arg &rest args))
(declare-function org-roam-node-level "org-roam-node" (node))
(declare-function org-roam-node-list "org-roam-node" ())
(declare-function org-roam-node-properties "org-roam-node" (node))
(declare-function org-roam-node-read "org-roam-node" (&optional initial-input filter-fn sort-fn require-match prompt))
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

(defun p3/org-roam-project-hub-id-for-root (root)
  "Return the Org-roam hub ID associated with local project ROOT."
  (when-let ((normalized (p3/project-normalize-root root)))
    (cdr (assoc normalized p3/org-roam-project-associations))))

(defun p3/org-roam-project-associate-root (root hub-id &optional replace)
  "Associate local project ROOT with HUB-ID.
When REPLACE is non-nil, replace an existing different mapping explicitly."
  (let ((normalized (p3/project-normalize-root root)))
    (unless normalized
      (user-error "Project root does not exist: %s" root))
    (unless (and (stringp hub-id) (not (string-empty-p hub-id)))
      (user-error "Project hub ID is unavailable"))
    (let ((existing (assoc normalized p3/org-roam-project-associations)))
      (cond
       ((not existing)
        (push (cons normalized hub-id) p3/org-roam-project-associations))
       ((equal (cdr existing) hub-id))
       (replace
        (setcdr existing hub-id))
       (t
        (user-error "Project root is already associated with another hub"))))
    hub-id))

(defun p3/org-roam--node-file-project-id (node)
  "Return NODE's file-level P3_PROJECT value, or nil."
  (when (and node (zerop (or (org-roam-node-level node) 0)))
    (cdr (assoc-string "P3_PROJECT" (org-roam-node-properties node)))))

(defun p3/org-roam-project-hub-p (node)
  "Return non-nil when NODE is a self-marked project hub file node."
  (when node
    (let ((id (org-roam-node-id node)))
      (and (zerop (or (org-roam-node-level node) 0))
           (stringp id)
           (not (string-empty-p id))
           (equal id (p3/org-roam--node-file-project-id node))))))

(defun p3/org-roam--hub-node (hub-id)
  "Return the live self-marked Org-roam hub node for HUB-ID.
Signal `user-error' when the stored identity is stale or invalid."
  (let ((node (and hub-id (org-roam-node-from-id hub-id))))
    (unless (p3/org-roam-project-hub-p node)
      (user-error "Org-roam project hub is missing or no longer self-marked: %s"
                  hub-id))
    node))

(defun p3/org-roam--nearest-heading-project-id ()
  "Return nearest explicit heading P3_PROJECT at point or an ancestor."
  (when (derived-mode-p 'org-mode)
    (save-excursion
      (unless (org-before-first-heading-p)
        (org-back-to-heading t)
        (catch 'project
          (while t
            (when-let ((project-id
                        (org-entry-get (point) "P3_PROJECT" nil)))
              (throw 'project project-id))
            (unless (org-up-heading-safe)
              (throw 'project nil))))))))

(defun p3/org-roam--file-project-id-live ()
  "Return the current Org buffer's explicit file-level P3_PROJECT value."
  (when (derived-mode-p 'org-mode)
    (save-excursion
      (goto-char (point-min))
      (org-entry-get (point) "P3_PROJECT" nil))))

(defun p3/org-roam-project-context ()
  "Return the current durable literate-project hub ID, or nil."
  (or (p3/org-roam--nearest-heading-project-id)
      (p3/org-roam--file-project-id-live)
      (when-let ((root (p3/project-root)))
        (p3/org-roam-project-hub-id-for-root root))))

(defun p3/org-roam--read-hub-node ()
  "Read an existing self-marked project hub node."
  (org-roam-node-read nil #'p3/org-roam-project-hub-p nil t "Project hub: "))

(defun p3/org-roam--heading-project-id-explicit ()
  "Return the explicit P3_PROJECT value on the current heading, or nil."
  (when (and (derived-mode-p 'org-mode)
             (not (org-before-first-heading-p)))
    (save-excursion
      (org-back-to-heading t)
      (org-entry-get (point) "P3_PROJECT" nil))))

(defun p3/org-roam--set-heading-project-id (hub-id)
  "Set explicit heading-level P3_PROJECT to HUB-ID in the live buffer."
  (unless (and (derived-mode-p 'org-mode)
               (not (org-before-first-heading-p)))
    (user-error "Point is not on an Org heading"))
  (save-excursion
    (org-back-to-heading t)
    (org-entry-put (point) "P3_PROJECT" hub-id)))

(defun p3/org-roam--remove-heading-project-id ()
  "Remove explicit heading-level P3_PROJECT from the current heading."
  (unless (and (derived-mode-p 'org-mode)
               (not (org-before-first-heading-p)))
    (user-error "Point is not on an Org heading"))
  (save-excursion
    (org-back-to-heading t)
    (org-entry-delete (point) "P3_PROJECT")))

(defun p3/org-roam--set-file-project-id (hub-id)
  "Set file-level P3_PROJECT to HUB-ID in the current live Org buffer."
  (unless (derived-mode-p 'org-mode)
    (user-error "Current buffer is not an Org buffer"))
  (save-excursion
    (goto-char (point-min))
    (org-entry-put (point) "P3_PROJECT" hub-id)))

(defun p3/org-roam--remove-file-project-id ()
  "Remove file-level P3_PROJECT from the current live Org buffer."
  (unless (derived-mode-p 'org-mode)
    (user-error "Current buffer is not an Org buffer"))
  (save-excursion
    (goto-char (point-min))
    (org-entry-delete (point) "P3_PROJECT")))

(defun p3/org-roam--association-hub-node ()
  "Return a valid hub node for an association operation."
  (or (when-let ((hub-id (p3/org-roam-project-context)))
        (condition-case nil
            (p3/org-roam--hub-node hub-id)
          (user-error nil)))
      (p3/org-roam--read-hub-node)))

(defun p3/org-roam-project-associate (&optional whole-file)
  "Associate, change, or remove project membership at point.
By default target the current Org heading.  When WHOLE-FILE is non-nil,
or point is before the first heading, target the file-level property."
  (interactive "P")
  (unless (derived-mode-p 'org-mode)
    (user-error "Current buffer is not an Org buffer"))
  (let* ((file-scope (or whole-file (org-before-first-heading-p)))
         (current-id (if file-scope
                         (p3/org-roam--file-project-id-live)
                       (p3/org-roam--heading-project-id-explicit)))
         (setter (if file-scope
                     #'p3/org-roam--set-file-project-id
                   #'p3/org-roam--set-heading-project-id))
         (remover (if file-scope
                      #'p3/org-roam--remove-file-project-id
                    #'p3/org-roam--remove-heading-project-id)))
    (if (not current-id)
        (funcall setter
                 (org-roam-node-id (p3/org-roam--association-hub-node)))
      (pcase (completing-read "Project association: "
                              '("change" "remove") nil t)
        ("remove"
         (funcall remover))
        ("change"
         (let* ((node (p3/org-roam--read-hub-node))
                (new-id (org-roam-node-id node)))
           (when (and (not (equal current-id new-id))
                      (yes-or-no-p
                       (format "Change project association from %s to %s? "
                               current-id new-id)))
             (funcall setter new-id))))))))

(provide 'p3-org-roam)

;;; p3-org-roam.el ends here
