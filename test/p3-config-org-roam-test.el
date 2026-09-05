;;; p3-config-org-roam-test.el --- Org-roam config boundary tests -*- lexical-binding: t; -*-

(require 'ert)
(require 'seq)

(defconst p3-config-org-roam-test--root
  (file-name-directory
   (directory-file-name
    (file-name-directory (or load-file-name buffer-file-name))))
  "Root of the Emacs configuration under test.")

(defun p3-config-org-roam-test--path (relative)
  "Return RELATIVE under the repository root."
  (expand-file-name relative p3-config-org-roam-test--root))

(defun p3-config-org-roam-test--forms ()
  "Read all top-level forms from the Org-roam config module."
  (with-temp-buffer
    (insert-file-contents
     (p3-config-org-roam-test--path "lisp/p3-config-org-roam.el"))
    (goto-char (point-min))
    (let (forms)
      (condition-case nil
          (while t
            (push (read (current-buffer)) forms))
        (end-of-file nil))
      (nreverse forms))))

(defun p3-config-org-roam-test--use-package-form ()
  "Return the top-level Org-roam `use-package' form."
  (seq-find
   (lambda (form)
     (and (consp form)
          (eq (car form) 'use-package)
          (eq (cadr form) 'org-roam)))
   (p3-config-org-roam-test--forms)))

(defun p3-config-org-roam-test--keyword-values (keyword)
  "Return values following KEYWORD in the Org-roam `use-package' form."
  (let* ((form (p3-config-org-roam-test--use-package-form))
         (tail (memq keyword (cddr form)))
         values)
    (should tail)
    (setq tail (cdr tail))
    (while (and tail (not (keywordp (car tail))))
      (push (car tail) values)
      (setq tail (cdr tail)))
    (nreverse values)))

(ert-deftest p3-config-org-roam-loads-behavior-before-package-wiring ()
  (let* ((forms (p3-config-org-roam-test--forms))
         (behavior (seq-position
                    forms '(p3/config-load-module 'p3-org-roam) #'equal))
         (package (seq-position
                   forms (p3-config-org-roam-test--use-package-form) #'equal)))
    (should (integerp behavior))
    (should (integerp package))
    (should (< behavior package))))

(ert-deftest p3-config-org-roam-preserves-hook-and-custom-values ()
  (should (equal (p3-config-org-roam-test--keyword-values :hook)
                 '((after-init . org-roam-mode))))
  (should
   (equal
    (p3-config-org-roam-test--keyword-values :custom)
    '((org-roam-database-connector 'sqlite-builtin)
      (org-roam-directory "~/org/notes/roam/")
      (org-roam-completion-everywhere t)
      (org-roam-completion-system 'default)
      (org-roam-capture-templates
       '(("d" "default" plain "%?"
          :if-new
          (file+head "%<%Y%m%d%H%M%S>-${slug}.org"
                     "#+title: ${title}\n#+category:${title}\n#+created: %U\n#+last_modified: %U\n")
          :unnarrowed t)))
      (org-roam-dailies-directory "journal/")
      (org-roam-dailies-capture-templates
       '(("d" "default" entry "* %<%I:%M %p>: %?"
          :target
          (file+head "%<%Y-%m-%d>.org"
                     "#+title: %<%Y-%m-%d %a>\n#+created: %U\n#+last_modified: %U\n"))))))))

(ert-deftest p3-config-org-roam-has-no-citar-dependent-literature-template ()
  (let ((contents
         (with-temp-buffer
           (insert-file-contents
            (p3-config-org-roam-test--path "lisp/p3-config-org-roam.el"))
           (buffer-string))))
    (dolist (needle '("citar-org-roam-subdir" "citar-citekey"
                      "citar-date" "note-title"))
      (should-not (string-match-p (regexp-quote needle) contents)))))

(ert-deftest p3-config-org-roam-preserves-bindings ()
  (should
   (equal
    (p3-config-org-roam-test--keyword-values :bind)
    '((("C-c n l" . org-roam-buffer-toggle)
       ("C-c n f" . org-roam-node-find)
       ("C-c n g" . org-roam-graph)
       ("C-c n i" . org-roam-node-insert)
       ("C-c n c" . org-roam-capture)
       ("C-c n n" . org-roam-node-insert-immediate-with-tag)
       ("C-c n s" . org-roam-rg-search)
       ("C-c n d" . org-roam-dailies-goto-today)
       ("C-c n t" . org-roam-dailies-capture-today)
       ("C-c n C-t" . org-roam-tag-add)
       ("C-c n a" . p3/org-roam-get-agenda))))))

(ert-deftest p3-config-org-roam-preserves-display-and-autosync-config ()
  (should
   (equal
    (p3-config-org-roam-test--keyword-values :config)
    '((setq org-roam-node-display-template
            (concat "${title:*} "
                    (propertize "${tags:10}" 'face 'org-tag)))
      (org-roam-db-autosync-mode)))))

(provide 'p3-config-org-roam-test)

;;; p3-config-org-roam-test.el ends here
