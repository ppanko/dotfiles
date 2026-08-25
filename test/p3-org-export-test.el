;;; p3-org-export-test.el --- Tests for p3-org-export -*- lexical-binding: t; -*-

(require 'ert)
(require 'org)

(defconst p3-org-export-test--config-directory
  (file-name-directory
   (directory-file-name
    (file-name-directory (or load-file-name buffer-file-name))))
  "Root of the Emacs configuration under test.")

(add-to-list 'load-path
             (expand-file-name "lisp" p3-org-export-test--config-directory))

(require 'p3-org-export)

(defmacro p3-org-export-test--with-temp-directory (binding &rest body)
  "Bind BINDING to a temporary directory while evaluating BODY."
  (declare (indent 1) (debug (symbolp body)))
  `(let ((,binding (make-temp-file "p3-org-export-test-" t)))
     (unwind-protect
         (progn ,@body)
       (delete-directory ,binding t))))

(defun p3-org-export-test--contents (path)
  "Return the contents of PATH."
  (with-temp-buffer
    (insert-file-contents path)
    (buffer-string)))

(ert-deftest p3-org-export-profiles-preserve-office-and-add-markdown ()
  (dolist (profile '(docx gfm pptx))
    (should (p3-org-export--profile profile)))
  (should (equal (plist-get (p3-org-export--profile 'gfm) :extension) "md"))
  (should (equal (plist-get (p3-org-export--profile 'gfm) :format) "gfm")))

(ert-deftest p3-org-export-output-file-respects-export-file-name ()
  (p3-org-export-test--with-temp-directory directory
    (with-temp-buffer
      (setq buffer-file-name (expand-file-name "notes.org" directory)
            default-directory directory)
      (insert "#+EXPORT_FILE_NAME: final-report\n\n* Heading\n")
      (org-mode)
      (should
       (equal (p3-org-export--output-file 'gfm)
              (expand-file-name "final-report.md" directory))))))

(ert-deftest p3-org-export-gfm-arguments-preserve-metadata-and-disable-wrapping ()
  (let ((source "/tmp/report.org")
        (output "/tmp/report.md"))
    (should
     (equal
      (p3-org-export--arguments 'gfm source output nil)
      (list "--from=org" "--to=gfm" "--standalone" "--wrap=none"
            source "-o" output)))))

(ert-deftest p3-org-export-docx-arguments-use-reference-document ()
  (let ((source "/tmp/report.org")
        (output "/tmp/report.docx")
        (reference "/tmp/reference.docx"))
    (should
     (equal
      (p3-org-export--arguments 'docx source output reference)
      (list "--from=org" "--to=docx"
            source "-o" output
            "--reference-doc=/tmp/reference.docx")))))

(ert-deftest p3-org-export-reference-defaults-are-profile-specific ()
  (let ((p3-org-export-reference-docx "/tmp/reference.docx")
        (p3-org-export-reference-pptx "/tmp/reference.pptx"))
    (should (equal (p3-org-export--default-reference 'docx)
                   "/tmp/reference.docx"))
    (should (equal (p3-org-export--default-reference 'pptx)
                   "/tmp/reference.pptx"))
    (should-not (p3-org-export--default-reference 'gfm))))

(ert-deftest p3-org-export-rejects-unreadable-reference-document ()
  (should-error
   (p3-org-export--validate-reference "/path/that/does/not/exist.docx")
   :type 'user-error))

(ert-deftest p3-org-export-setup-restores-org-open-and-adds-export-binding ()
  (p3-org-export-setup)
  (should (eq (lookup-key org-mode-map (kbd "C-c C-o"))
              #'org-open-at-point))
  (should (eq (lookup-key org-mode-map (kbd "C-c E"))
              #'p3/org-export)))

(ert-deftest p3-org-export-updates-keybinding-atlas-without-duplicates ()
  (let ((p3/keybinding-sections
         '(("Org"
            ("C-c b" . "insert citation")
            ("C-c C-o" . "export to Office")
            ("C-c E" . "stale export entry")
            ("C-c P" . "start presentation")))))
    (p3-org-export--update-keybinding-atlas)
    (let* ((org-section (cdr (assoc "Org" p3/keybinding-sections)))
           (open-entry (assoc "C-c C-o" org-section))
           (export-entries
            (seq-filter (lambda (entry) (equal (car entry) "C-c E"))
                        org-section)))
      (should (equal (cdr open-entry) "open link at point"))
      (should (= (length export-entries) 1))
      (should (equal (cdar export-entries) "export Org file")))))

(ert-deftest p3-org-export-gfm-runs-through-pandoc-when-available ()
  (skip-unless (executable-find "pandoc"))
  (p3-org-export-test--with-temp-directory directory
    (let ((source (expand-file-name "report.org" directory)))
      (with-temp-file source
        (insert "#+TITLE: Export Test\n\n* Heading\n\nBody text.\n"))
      (with-current-buffer (find-file-noselect source)
        (unwind-protect
            (progn
              (org-mode)
              (let* ((output (p3-org-export-run 'gfm nil))
                     (contents (p3-org-export-test--contents output)))
                (should (file-exists-p output))
                (should (string-match-p "# Heading" contents))
                (should (string-match-p "title:.*Export Test" contents))))
          (set-buffer-modified-p nil)
          (kill-buffer (current-buffer)))))))

(provide 'p3-org-export-test)

;;; p3-org-export-test.el ends here
