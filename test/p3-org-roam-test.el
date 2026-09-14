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

(provide 'p3-org-roam-test)

;;; p3-org-roam-test.el ends here
