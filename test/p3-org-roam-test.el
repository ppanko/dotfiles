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
                     '("a.org" "c.org")))
      (should (funcall (p3/org-roam-filter-by-tag "home")
                       (cadr nodes)))
      (should-not (funcall (p3/org-roam-filter-by-tag "home")
                           (car nodes))))))

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

(provide 'p3-org-roam-test)

;;; p3-org-roam-test.el ends here
