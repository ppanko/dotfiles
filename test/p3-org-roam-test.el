;;; p3-org-roam-test.el --- Tests for p3-org-roam -*- lexical-binding: t; -*-

(require 'cl-lib)
(require 'ert)

(defvar org-roam-directory nil)

(defconst p3-org-roam-test--root
  (file-name-directory
   (directory-file-name
    (file-name-directory (or load-file-name buffer-file-name))))
  "Root of the Emacs configuration under test.")

(add-to-list 'load-path (expand-file-name "lisp" p3-org-roam-test--root))
(require 'p3-org-roam)

(ert-deftest p3-org-roam-preserves-tangled-config-dynamic-binding ()
  (with-temp-buffer
    (insert-file-contents
     (expand-file-name "lisp/p3-org-roam.el" p3-org-roam-test--root))
    (goto-char (point-min))
    (should-not
     (re-search-forward "lexical-binding:[ \t]*t"
                        (line-end-position) t))))

(ert-deftest p3-org-roam-tagged-header-preserves-blank-output ()
  (cl-letf (((symbol-function 'read-string)
             (lambda (&rest _) "")))
    (should
     (equal
      (org-roam-generate-tagged-header)
      "#+title: ${title}\n#+category:${title}\n#+created: %U\n#+last_modified: %U\n"))))

(ert-deftest p3-org-roam-tagged-header-preserves-trailing-hash ()
  (cl-letf (((symbol-function 'read-string)
             (lambda (&rest _) "work")))
    (should
     (equal
      (org-roam-generate-tagged-header)
      "#+title: ${title}\n#+category:${title}\n#+filetags: work\n#+created: %U\n#+last_modified: %U\n#"))))

(ert-deftest p3-org-roam-listing-and-tag-filtering-preserve-current-behavior ()
  (let ((nodes '((:file "a.org" :tags ("work" "x"))
                 (:file "b.org" :tags ("home"))
                 (:file "c.org" :tags ("work")))))
    (cl-letf (((symbol-function 'org-roam-node-list)
               (lambda () nodes))
              ((symbol-function 'org-roam-node-file)
               (lambda (node) (plist-get node :file)))
              ((symbol-function 'org-roam-node-tags)
               (lambda (node) (plist-get node :tags))))
      (should (equal (p3/org-roam-list-notes)
                     '("a.org" "b.org" "c.org")))
      (should (equal (p3/org-roam-list-notes-by-tag "work")
                     '("a.org" "c.org"))))))

(ert-deftest p3-org-roam-agenda-uses-all-notes-for-blank-tag ()
  (let (agenda-called
        org-agenda-files)
    (cl-letf (((symbol-function 'read-string)
               (lambda (&rest _) ""))
              ((symbol-function 'p3/org-roam-list-notes)
               (lambda () '("a.org" "b.org")))
              ((symbol-function 'org-agenda)
               (lambda (&rest _)
                 (setq agenda-called t))))
      (p3/org-roam-get-agenda)
      (should agenda-called)
      (should (equal org-agenda-files '("a.org" "b.org"))))))

(ert-deftest p3-org-roam-agenda-filters-notes-for-nonblank-tag ()
  (let (agenda-called
        seen-tag
        org-agenda-files)
    (cl-letf (((symbol-function 'read-string)
               (lambda (&rest _) "work"))
              ((symbol-function 'p3/org-roam-list-notes-by-tag)
               (lambda (tag)
                 (setq seen-tag tag)
                 '("work.org")))
              ((symbol-function 'org-agenda)
               (lambda (&rest _)
                 (setq agenda-called t))))
      (p3/org-roam-get-agenda)
      (should agenda-called)
      (should (equal seen-tag "work"))
      (should (equal org-agenda-files '("work.org"))))))

(ert-deftest p3-org-roam-search-delegates-to-consult-ripgrep ()
  (let ((org-roam-directory "/tmp/roam")
        seen)
    (cl-letf (((symbol-function 'consult-ripgrep)
               (lambda (directory &optional initial)
                 (setq seen (list directory initial)))))
      (org-roam-rg-search)
      (should (equal seen '("/tmp/roam" nil))))))

(ert-deftest p3-org-roam-immediate-insert-preserves-tagged-template ()
  (let (seen-args
        seen-templates)
    (cl-letf (((symbol-function 'org-roam-node-insert)
               (lambda (&rest args)
                 (setq seen-args args
                       seen-templates org-roam-capture-templates))))
      (org-roam-node-insert-immediate-with-tag 4 'extra)
      (should (equal seen-args '(4 extra)))
      (should (= (length seen-templates) 1))
      (let ((template (car seen-templates)))
        (should (equal (seq-take template 4)
                       '("t" "tagged" plain "%?")))
        (should (equal (plist-get (nthcdr 4 template) :immediate-finish)
                       t))
        (should (equal (plist-get (nthcdr 4 template) :unnarrowed)
                       t))))))

(ert-deftest p3-org-roam-project-root-association-normalizes-and-rejects-conflict ()
  (let ((p3/org-roam-project-associations nil))
    (cl-letf (((symbol-function 'p3/project-normalize-root)
               (lambda (_root) "/tmp/repo/")))
      (should (equal (p3/org-roam-project-associate-root "/tmp/repo" "hub-a")
                     "hub-a"))
      (should (equal (p3/org-roam-project-hub-id-for-root "/tmp/repo/")
                     "hub-a"))
      (should-error
       (p3/org-roam-project-associate-root "/tmp/repo" "hub-b")
       :type 'user-error))))

(ert-deftest p3-org-roam-project-root-association-can-replace-explicitly ()
  (let ((p3/org-roam-project-associations '(("/tmp/repo/" . "hub-a"))))
    (cl-letf (((symbol-function 'p3/project-normalize-root)
               (lambda (_root) "/tmp/repo/")))
      (should (equal (p3/org-roam-project-associate-root
                      "/tmp/repo" "hub-b" t)
                     "hub-b"))
      (should (equal p3/org-roam-project-associations
                     '(("/tmp/repo/" . "hub-b")))))))

(ert-deftest p3-org-roam-project-one-hub-may-own-multiple-roots ()
  (let ((p3/org-roam-project-associations nil))
    (cl-letf (((symbol-function 'p3/project-normalize-root)
               (lambda (root) (file-name-as-directory root))))
      (p3/org-roam-project-associate-root "/tmp/a" "hub")
      (p3/org-roam-project-associate-root "/tmp/b" "hub")
      (should (= (length p3/org-roam-project-associations) 2)))))

(ert-deftest p3-org-roam-project-hub-requires-self-marked-file-node ()
  (cl-letf (((symbol-function 'org-roam-node-id)
             (lambda (node) (plist-get node :id)))
            ((symbol-function 'org-roam-node-level)
             (lambda (node) (plist-get node :level)))
            ((symbol-function 'org-roam-node-properties)
             (lambda (node) (plist-get node :properties))))
    (should (p3/org-roam-project-hub-p
             '(:id "hub" :level 0 :properties (("P3_PROJECT" . "hub")))))
    (should-not
     (p3/org-roam-project-hub-p
      '(:id "hub" :level 0 :properties (("P3_PROJECT" . "other")))))
    (should-not
     (p3/org-roam-project-hub-p
      '(:id "hub" :level 1 :properties (("P3_PROJECT" . "hub")))))))

(ert-deftest p3-org-roam-project-context-prefers-nearest-heading ()
  (with-temp-buffer
    (org-mode)
    (insert ":PROPERTIES:\n:P3_PROJECT: file-project\n:END:\n"
            "* Parent\n:PROPERTIES:\n:P3_PROJECT: parent-project\n:END:\n"
            "** Child\n:PROPERTIES:\n:P3_PROJECT: child-project\n:END:\n"
            "*** TODO Work\n")
    (goto-char (point-max))
    (cl-letf (((symbol-function 'p3/project-root) (lambda () nil)))
      (should (equal (p3/org-roam-project-context) "child-project")))))

(ert-deftest p3-org-roam-project-context-inherits-nearest-ancestor-before-file ()
  (with-temp-buffer
    (org-mode)
    (insert ":PROPERTIES:\n:P3_PROJECT: file-project\n:END:\n"
            "* Parent\n:PROPERTIES:\n:P3_PROJECT: parent-project\n:END:\n"
            "** TODO Work\n")
    (goto-char (point-max))
    (cl-letf (((symbol-function 'p3/project-root) (lambda () nil)))
      (should (equal (p3/org-roam-project-context) "parent-project")))))

(ert-deftest p3-org-roam-project-context-falls-back-to-file-property ()
  (with-temp-buffer
    (org-mode)
    (insert ":PROPERTIES:\n:P3_PROJECT: file-project\n:END:\n* TODO Work\n")
    (goto-char (point-max))
    (cl-letf (((symbol-function 'p3/project-root) (lambda () nil)))
      (should (equal (p3/org-roam-project-context) "file-project")))))

(ert-deftest p3-org-roam-project-context-falls-back-to-root-map ()
  (let ((p3/org-roam-project-associations '(("/tmp/repo/" . "root-project"))))
    (with-temp-buffer
      (cl-letf (((symbol-function 'p3/project-root)
                 (lambda () "/tmp/repo/"))
                ((symbol-function 'p3/project-normalize-root)
                 (lambda (_root) "/tmp/repo/")))
        (should (equal (p3/org-roam-project-context) "root-project"))))))

(ert-deftest p3-org-roam-project-context-is-nil-without-any-source ()
  (let ((p3/org-roam-project-associations nil))
    (with-temp-buffer
      (cl-letf (((symbol-function 'p3/project-root) (lambda () nil)))
        (should-not (p3/org-roam-project-context))))))

(ert-deftest p3-org-roam-project-heading-remove-reveals-file-membership ()
  (with-temp-buffer
    (org-mode)
    (insert ":PROPERTIES:\n:P3_PROJECT: file-project\n:END:\n"
            "* TODO Work\n:PROPERTIES:\n:P3_PROJECT: other-project\n:END:\n")
    (goto-char (point-max))
    (org-back-to-heading t)
    (p3/org-roam--remove-heading-project-id)
    (should (equal (p3/org-roam-project-context) "file-project"))))

(ert-deftest p3-org-roam-project-file-remove-preserves-heading-membership ()
  (with-temp-buffer
    (org-mode)
    (insert ":PROPERTIES:\n:P3_PROJECT: file-project\n:END:\n"
            "* TODO Work\n:PROPERTIES:\n:P3_PROJECT: heading-project\n:END:\n")
    (p3/org-roam--remove-file-project-id)
    (goto-char (point-max))
    (org-back-to-heading t)
    (should (equal (org-entry-get (point) "P3_PROJECT" nil)
                   "heading-project"))))

(ert-deftest p3-org-roam-project-ordinary-association-does-not-save-buffer ()
  (with-temp-buffer
    (org-mode)
    (insert "* TODO Work\n")
    (goto-char (point-min))
    (set-buffer-modified-p t)
    (let (saved)
      (cl-letf (((symbol-function 'save-buffer)
                 (lambda (&rest _) (setq saved t))))
        (p3/org-roam--set-heading-project-id "hub")
        (should-not saved)
        (should (equal (org-entry-get (point) "P3_PROJECT" nil) "hub"))))))

(ert-deftest p3-org-roam-project-associate-defaults-to-heading-scope ()
  (with-temp-buffer
    (org-mode)
    (insert "* TODO Work\n")
    (goto-char (point-min))
    (let (heading-set file-set)
      (cl-letf (((symbol-function 'p3/org-roam--heading-project-id-explicit)
                 (lambda () nil))
                ((symbol-function 'p3/org-roam-project-context)
                 (lambda () "hub"))
                ((symbol-function 'p3/org-roam--hub-node)
                 (lambda (_id) 'hub-node))
                ((symbol-function 'org-roam-node-id)
                 (lambda (_node) "hub"))
                ((symbol-function 'p3/org-roam--set-heading-project-id)
                 (lambda (id) (setq heading-set id)))
                ((symbol-function 'p3/org-roam--set-file-project-id)
                 (lambda (id) (setq file-set id))))
        (p3/org-roam-project-associate nil)
        (should (equal heading-set "hub"))
        (should-not file-set)))))

(ert-deftest p3-org-roam-project-associate-prefix-targets-file-scope ()
  (with-temp-buffer
    (org-mode)
    (insert "* TODO Work\n")
    (goto-char (point-min))
    (let (heading-set file-set)
      (cl-letf (((symbol-function 'p3/org-roam--file-project-id-live)
                 (lambda () nil))
                ((symbol-function 'p3/org-roam-project-context)
                 (lambda () "hub"))
                ((symbol-function 'p3/org-roam--hub-node)
                 (lambda (_id) 'hub-node))
                ((symbol-function 'org-roam-node-id)
                 (lambda (_node) "hub"))
                ((symbol-function 'p3/org-roam--set-heading-project-id)
                 (lambda (id) (setq heading-set id)))
                ((symbol-function 'p3/org-roam--set-file-project-id)
                 (lambda (id) (setq file-set id))))
        (p3/org-roam-project-associate '(4))
        (should-not heading-set)
        (should (equal file-set "hub"))))))

(ert-deftest p3-org-roam-project-promote-saves-indexes-before-mapping ()
  (with-temp-buffer
    (let (calls)
      (cl-letf (((symbol-function 'p3/org-roam-project-hub-p)
                 (lambda (_node) nil))
                ((symbol-function 'p3/org-roam--node-file-project-id)
                 (lambda (_node) nil))
                ((symbol-function 'org-roam-node-id)
                 (lambda (_node) "hub"))
                ((symbol-function 'org-roam-node-file)
                 (lambda (_node) "/tmp/hub.org"))
                ((symbol-function 'find-file-noselect)
                 (lambda (_file) (current-buffer)))
                ((symbol-function 'buffer-modified-p)
                 (lambda (&optional _buffer) nil))
                ((symbol-function 'p3/org-roam--set-file-project-id)
                 (lambda (_id) (push 'write calls)))
                ((symbol-function 'save-buffer)
                 (lambda (&rest _) (push 'save calls)))
                ((symbol-function 'org-roam-db-update-file)
                 (lambda (&optional _file) (push 'index calls)))
                ((symbol-function 'p3/org-roam-project-associate-root)
                 (lambda (&rest _) (push 'map calls) "hub")))
        (should (equal (p3/org-roam--promote-node-to-hub
                        'node "/tmp/repo" nil)
                       "hub"))
        (should (equal (nreverse calls) '(write save index map)))))))

(ert-deftest p3-org-roam-project-promote-refuses-preexisting-unsaved-edits ()
  (with-temp-buffer
    (let (wrote mapped)
      (cl-letf (((symbol-function 'p3/org-roam-project-hub-p)
                 (lambda (_node) nil))
                ((symbol-function 'p3/org-roam--node-file-project-id)
                 (lambda (_node) nil))
                ((symbol-function 'org-roam-node-id)
                 (lambda (_node) "hub"))
                ((symbol-function 'org-roam-node-file)
                 (lambda (_node) "/tmp/hub.org"))
                ((symbol-function 'find-file-noselect)
                 (lambda (_file) (current-buffer)))
                ((symbol-function 'buffer-modified-p)
                 (lambda (&optional _buffer) t))
                ((symbol-function 'p3/org-roam--set-file-project-id)
                 (lambda (_id) (setq wrote t)))
                ((symbol-function 'p3/org-roam-project-associate-root)
                 (lambda (&rest _) (setq mapped t))))
        (should-error
         (p3/org-roam--promote-node-to-hub 'node "/tmp/repo" nil)
         :type 'user-error)
        (should-not wrote)
        (should-not mapped)))))

(ert-deftest p3-org-roam-project-promote-save-failure-never-maps-root ()
  (with-temp-buffer
    (let (mapped)
      (cl-letf (((symbol-function 'p3/org-roam-project-hub-p)
                 (lambda (_node) nil))
                ((symbol-function 'p3/org-roam--node-file-project-id)
                 (lambda (_node) nil))
                ((symbol-function 'org-roam-node-id)
                 (lambda (_node) "hub"))
                ((symbol-function 'org-roam-node-file)
                 (lambda (_node) "/tmp/hub.org"))
                ((symbol-function 'find-file-noselect)
                 (lambda (_file) (current-buffer)))
                ((symbol-function 'buffer-modified-p)
                 (lambda (&optional _buffer) nil))
                ((symbol-function 'p3/org-roam--set-file-project-id) #'ignore)
                ((symbol-function 'save-buffer)
                 (lambda (&rest _) (error "save failed")))
                ((symbol-function 'p3/org-roam-project-associate-root)
                 (lambda (&rest _) (setq mapped t))))
        (should-error
         (p3/org-roam--promote-node-to-hub 'node "/tmp/repo" nil))
        (should-not mapped)))))

(ert-deftest p3-org-roam-project-existing-hub-maps-without-forced-save ()
  (let (saved mapped)
    (cl-letf (((symbol-function 'p3/org-roam-project-hub-p)
               (lambda (_node) t))
              ((symbol-function 'org-roam-node-id)
               (lambda (_node) "hub"))
              ((symbol-function 'save-buffer)
               (lambda (&rest _) (setq saved t)))
              ((symbol-function 'p3/org-roam-project-associate-root)
               (lambda (_root id replace)
                 (setq mapped (list id replace))
                 id)))
      (should (equal (p3/org-roam--promote-node-to-hub
                      'node "/tmp/repo" t)
                     "hub"))
      (should-not saved)
      (should (equal mapped '("hub" t))))))

(ert-deftest p3-org-roam-project-create-hub-maps-after-durable-capture ()
  (with-temp-buffer
    (let (calls template)
      (cl-letf (((symbol-function 'read-string)
                 (lambda (&rest _) "New Hub"))
                ((symbol-function 'org-id-new)
                 (lambda () "new-hub"))
                ((symbol-function 'org-roam-node-create)
                 (lambda (&rest args) args))
                ((symbol-function 'org-roam-capture-)
                 (lambda (&rest args)
                   (setq template (car (plist-get args :templates)))
                   (setq buffer-file-name "/tmp/new-hub.org")
                   (push 'capture calls)))
                ((symbol-function 'org-roam-db-update-file)
                 (lambda (&optional _file) (push 'index calls)))
                ((symbol-function 'p3/org-roam--hub-node)
                 (lambda (_id) 'hub-node))
                ((symbol-function 'p3/org-roam-project-associate-root)
                 (lambda (&rest _) (push 'map calls) "new-hub")))
        (should (equal (p3/org-roam--create-hub "/tmp/repo" nil)
                       "new-hub"))
        (should (equal (nreverse calls) '(capture index map)))
        (should (equal (plist-get (nthcdr 4 template) :immediate-finish) t))
        (should (string-match-p
                 "P3_PROJECT: new-hub"
                 (nth 2 (plist-get (nthcdr 4 template) :if-new))))))))

(ert-deftest p3-org-roam-project-note-repairs-stale-root-mapping-explicitly ()
  (let ((p3/org-roam-project-associations '(("/tmp/repo/" . "stale")))
        repaired visited)
    (cl-letf (((symbol-function 'p3/org-roam-project-context)
               (lambda () "stale"))
              ((symbol-function 'p3/project-root)
               (lambda () "/tmp/repo/"))
              ((symbol-function 'p3/project-normalize-root)
               (lambda (_root) "/tmp/repo/"))
              ((symbol-function 'p3/org-roam--hub-node)
               (lambda (id)
                 (if (equal id "stale")
                     (user-error "stale")
                   'new-hub-node)))
              ((symbol-function 'yes-or-no-p)
               (lambda (&rest _) t))
              ((symbol-function 'p3/org-roam--establish-hub-for-root)
               (lambda (_root replace-root)
                 (setq repaired replace-root)
                 "new-hub"))
              ((symbol-function 'org-roam-node-visit)
               (lambda (node &rest _) (setq visited node))))
      (p3/org-roam-project-note)
      (should repaired)
      (should (eq visited 'new-hub-node)))))

(ert-deftest p3-org-roam-project-node-filter-requires-file-scope-and-hub-id ()
  (cl-letf (((symbol-function 'org-roam-node-level)
             (lambda (node) (plist-get node :level)))
            ((symbol-function 'org-roam-node-properties)
             (lambda (node) (plist-get node :properties))))
    (should
     (p3/org-roam--project-node-p
      '(:level 0 :properties (("P3_PROJECT" . "hub"))) "hub"))
    (should-not
     (p3/org-roam--project-node-p
      '(:level 0 :properties (("P3_PROJECT" . "other"))) "hub"))
    (should-not
     (p3/org-roam--project-node-p
      '(:level 2 :properties (("P3_PROJECT" . "hub"))) "hub"))))

(ert-deftest p3-org-roam-project-find-note-uses-required-filtered-completion ()
  (let (seen-filter seen-require visited)
    (cl-letf (((symbol-function 'p3/org-roam-project-context)
               (lambda () "hub"))
              ((symbol-function 'p3/org-roam--hub-node)
               (lambda (_id) 'hub-node))
              ((symbol-function 'org-roam-node-read)
               (lambda (_initial filter _sort require-match)
                 (setq seen-filter filter
                       seen-require require-match)
                 'chosen-node))
              ((symbol-function 'org-roam-node-visit)
               (lambda (node &rest _) (setq visited node))))
      (p3/org-roam-project-find-note)
      (should (functionp seen-filter))
      (should seen-require)
      (should (eq visited 'chosen-node)))))

(ert-deftest p3-org-roam-project-new-note-errors-without-context ()
  (cl-letf (((symbol-function 'p3/org-roam-project-context)
             (lambda () nil)))
    (should-error (p3/org-roam-project-new-note) :type 'user-error)))

(ert-deftest p3-org-roam-project-new-note-injects-project-file-property ()
  (let (template)
    (cl-letf (((symbol-function 'p3/org-roam-project-context)
               (lambda () "hub"))
              ((symbol-function 'p3/org-roam--hub-node)
               (lambda (_id) 'hub-node))
              ((symbol-function 'read-string)
               (lambda (&rest _) "Project Note"))
              ((symbol-function 'org-roam-node-create)
               (lambda (&rest args) args))
              ((symbol-function 'org-roam-capture-)
               (lambda (&rest args)
                 (setq template (car (plist-get args :templates))))))
      (p3/org-roam-project-new-note)
      (let* ((plist (nthcdr 4 template))
             (target (plist-get plist :if-new))
             (head (nth 2 target)))
        (should (string-match-p "P3_PROJECT: hub" head))
        (should-not (plist-get plist :immediate-finish))))))

(ert-deftest p3-org-roam-project-todos-scopes-agenda-state ()
  (let ((org-agenda-files '("global.org"))
        (org-use-property-inheritance '("GLOBAL"))
        seen-files seen-inheritance seen-match seen-todo-only)
    (cl-letf (((symbol-function 'p3/org-roam-list-notes)
               (lambda () '("a.org" "a.org" "b.org")))
              ((symbol-function 'org-tags-view)
               (lambda (todo-only match)
                 (setq seen-files org-agenda-files
                       seen-inheritance org-use-property-inheritance
                       seen-match match
                       seen-todo-only todo-only)
                 (get-buffer-create "*p3-project-agenda-test*"))))
      (unwind-protect
          (progn
            (p3/org-roam--project-todos "hub")
            (should (equal seen-files '("a.org" "b.org")))
            (should (equal seen-inheritance '("P3_PROJECT")))
            (should (equal seen-match "P3_PROJECT=\"hub\""))
            (should seen-todo-only)
            (should (equal org-agenda-files '("global.org")))
            (should (equal org-use-property-inheritance '("GLOBAL"))))
        (when-let ((buffer (get-buffer "*p3-project-agenda-test*")))
          (kill-buffer buffer))))))

(ert-deftest p3-org-roam-project-agenda-buffer-stores-explicit-refresh-state ()
  (let ((buffer (get-buffer-create "*p3-project-agenda-state-test*")))
    (unwind-protect
        (cl-letf (((symbol-function 'p3/org-roam-list-notes)
                   (lambda () '("a.org")))
                  ((symbol-function 'org-tags-view)
                   (lambda (&rest _) buffer)))
          (p3/org-roam--project-todos "hub")
          (with-current-buffer buffer
            (should (equal p3/org-roam-project-agenda-hub-id "hub"))
            (should (equal org-agenda-redo-command
                           '(p3/org-roam-project-agenda-redo)))))
      (kill-buffer buffer))))

(ert-deftest p3-org-roam-project-agenda-redo-uses-buffer-local-hub-id ()
  (with-temp-buffer
    (setq-local p3/org-roam-project-agenda-hub-id "hub-a")
    (let (seen)
      (cl-letf (((symbol-function 'p3/org-roam--project-todos)
                 (lambda (hub-id) (setq seen hub-id))))
        (p3/org-roam-project-agenda-redo)
        (should (equal seen "hub-a"))))))

(provide 'p3-org-roam-test)

;;; p3-org-roam-test.el ends here
