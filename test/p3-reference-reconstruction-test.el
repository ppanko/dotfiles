;;; p3-reference-reconstruction-test.el --- Durable reference-state regression -*- lexical-binding: t; -*-

(require 'ert)

(defconst p3-reference-reconstruction-test--root
  (file-name-directory
   (directory-file-name
    (file-name-directory (or load-file-name buffer-file-name)))))
(add-to-list 'load-path
             (expand-file-name "lisp" p3-reference-reconstruction-test--root))
(require 'p3-reference)

(ert-deftest p3-reference-durable-state-is-reconstructable-from-bib-and-org ()
  (let* ((directory (make-temp-file "p3-reconstruct-" t))
         (bib (expand-file-name "references.bib" directory))
         (project (expand-file-name "project.org" directory))
         (note (expand-file-name "literature.org" directory)))
    (unwind-protect
        (progn
          (with-temp-file bib
            (insert "@article{alpha2020, title={Alpha Study}, author={Alpha, Ada}, year={2020}}\n"))
          (with-temp-file project
            (insert "#+title: Project\n#+filetags: :project:\n\n* References\n[cite:@alpha2020]\n"))
          (with-temp-file note
            (insert ":PROPERTIES:\n:ID: literature-alpha\n:ROAM_REFS: @alpha2020\n:END:\n#+title: Alpha Study\n#+filetags: :literature:\n"))
          (let ((p3/reference-bibliography-file bib))
            (should (p3/reference--entry-alist "alpha2020")))
          (with-temp-buffer
            (insert-file-contents project)
            (should (string-match-p (regexp-quote "[cite:@alpha2020]")
                                    (buffer-string))))
          (with-temp-buffer
            (insert-file-contents note)
            (should (string-match-p (regexp-quote ":ROAM_REFS: @alpha2020")
                                    (buffer-string)))))
      (delete-directory directory t))))

(ert-deftest p3-reference-direct-doi-recognition-never-truncates-legacy-suffix ()
  (let* ((doi "10.1002/(SICI)1521-3951(199911)216:1<135::AID-PSSB135>3.0.CO;2-#")
         (normalized (downcase doi)))
    (should (equal normalized (p3/reference--doi-in-string doi)))
    (should (eq 'doi (p3/reference--input-kind doi)))
    (should-not
     (p3/reference--doi-in-string (concat "See " doi " for details")))))

(ert-deftest p3-reference-url-only-capture-reuses-normalized-url-duplicate ()
  (let* ((directory (make-temp-file "p3-url-duplicate-" t))
         (p3/reference-bibliography-file
          (expand-file-name "references.bib" directory)))
    (unwind-protect
        (progn
          (with-temp-file p3/reference-bibliography-file
            (insert "@online{alpha2020, url={https://example.org/article/}}\n"))
          (should
           (equal "alpha2020"
                  (p3/reference--capture-url
                   "HTTPS://EXAMPLE.ORG/article/#fragment")))
          (with-temp-buffer
            (insert-file-contents p3/reference-bibliography-file)
            (should (= 1 (how-many "^@" (point-min) (point-max))))))
      (delete-directory directory t))))

(ert-deftest p3-reference-project-association-updates-live-project-buffer ()
  (let* ((directory (make-temp-file "p3-live-project-" t))
         (project (expand-file-name "project.org" directory))
         buffer)
    (unwind-protect
        (progn
          (with-temp-file project
            (insert "#+title: Project\n#+filetags: :project:\n"))
          (setq buffer (find-file-noselect project))
          (with-current-buffer buffer
            (goto-char (point-max))
            (insert "\nUnsaved local project edit\n")
            (cl-letf (((symbol-function 'p3/reference--project-file)
                       (lambda (_node) project))
                      ((symbol-function 'p3/reference--project-node-p)
                       (lambda (_node) t)))
              (p3/reference-associate-project "alpha2020" 'project-node))
            (should (buffer-modified-p))
            (should (save-excursion
                      (goto-char (point-min))
                      (search-forward "[cite:@alpha2020]" nil t)))
            (save-buffer))
          (with-temp-buffer
            (insert-file-contents project)
            (should (search-forward "Unsaved local project edit" nil t))
            (should (search-forward "[cite:@alpha2020]" nil t))))
      (when (buffer-live-p buffer)
        (kill-buffer buffer))
      (delete-directory directory t))))

(ert-deftest p3-reference-project-removal-updates-live-project-buffer ()
  (let* ((directory (make-temp-file "p3-live-project-" t))
         (project (expand-file-name "project.org" directory))
         buffer)
    (unwind-protect
        (progn
          (with-temp-file project
            (insert "#+title: Project\n#+filetags: :project:\n\n* References\n\n[cite:@alpha2020]\n"))
          (setq buffer (find-file-noselect project))
          (with-current-buffer buffer
            (goto-char (point-max))
            (insert "\nUnsaved local project edit\n")
            (cl-letf (((symbol-function 'p3/reference--project-file)
                       (lambda (_node) project))
                      ((symbol-function 'p3/reference--project-node-p)
                       (lambda (_node) t)))
              (p3/reference-remove-project-association
               "alpha2020" 'project-node))
            (should (buffer-modified-p))
            (should-not (save-excursion
                          (goto-char (point-min))
                          (search-forward "[cite:@alpha2020]" nil t)))
            (save-buffer))
          (with-temp-buffer
            (insert-file-contents project)
            (should (search-forward "Unsaved local project edit" nil t))
            (goto-char (point-min))
            (should-not (search-forward "[cite:@alpha2020]" nil t))))
      (when (buffer-live-p buffer)
        (kill-buffer buffer))
      (delete-directory directory t))))

(ert-deftest p3-reference-finalization-offers-portable-citekey-default ()
  (let* ((directory (make-temp-file "p3-portable-key-" t))
         (p3/reference-bibliography-file
          (expand-file-name "references.bib" directory))
         offered)
    (unwind-protect
        (progn
          (with-temp-file p3/reference-bibliography-file
            (insert "@article{p3-inbox-1, title={Alpha Study}}\n"))
          (cl-letf (((symbol-function 'p3/reference--propose-citekey)
                     (lambda (_key) "alpha2020:_study"))
                    ((symbol-function 'read-string)
                     (lambda (_prompt initial &rest _)
                       (setq offered initial)
                       initial)))
            (let ((result (p3/reference-finalize "p3-inbox-1")))
              (should (equal offered result))
              (should (string-match-p
                       "\\`[A-Za-z0-9][A-Za-z0-9._-]*\\'" result)))))
      (delete-directory directory t))))

(ert-deftest p3-reference-finalization-rejects-nonportable-citekey ()
  (let* ((directory (make-temp-file "p3-portable-key-" t))
         (p3/reference-bibliography-file
          (expand-file-name "references.bib" directory)))
    (unwind-protect
        (progn
          (with-temp-file p3/reference-bibliography-file
            (insert "@article{p3-inbox-1, title={Alpha Study}}\n"))
          (cl-letf (((symbol-function 'p3/reference--propose-citekey)
                     (lambda (_key) "alpha2020"))
                    ((symbol-function 'read-string)
                     (lambda (&rest _) "alpha:2020")))
            (should-error
             (p3/reference-finalize "p3-inbox-1")
             :type 'user-error)))
      (delete-directory directory t))))

(ert-deftest p3-reference-import-rejects-new-nonportable-mature-citekey ()
  (let* ((directory (make-temp-file "p3-import-portable-" t))
         (p3/reference-bibliography-file
          (expand-file-name "references.bib" directory)))
    (unwind-protect
        (progn
          (should-error
           (p3/reference-import-bibtex
            "@article{alpha:2020, title={Alpha Study}}")
           :type 'user-error)
          (should-not (file-exists-p p3/reference-bibliography-file)))
      (delete-directory directory t))))

(ert-deftest p3-reference-pdf-path-rejects-legacy-nonportable-mature-citekey ()
  (let* ((directory (make-temp-file "p3-pdf-portable-" t))
         (p3/reference-pdf-directory directory))
    (unwind-protect
        (should-error
         (p3/reference-pdf-path "alpha:2020")
         :type 'user-error)
      (delete-directory directory t))))

(ert-deftest p3-reference-note-rejects-legacy-nonportable-mature-citekey ()
  (let* ((directory (make-temp-file "p3-note-portable-" t))
         (org-roam-directory directory))
    (unwind-protect
        (cl-letf (((symbol-function 'require) (lambda (&rest _) t))
                  ((symbol-function 'org-roam-node-from-ref) (lambda (_ref) nil))
                  ((symbol-function 'org-id-new) (lambda () "note-id"))
                  ((symbol-function 'citar-get-value) (lambda (&rest _) "Alpha Study"))
                  ((symbol-function 'find-file) #'ignore))
          (should-error
           (p3/reference-note "alpha:2020")
           :type 'user-error))
      (delete-directory directory t))))

(ert-deftest p3-reference-live-modified-bibliography-preserves-unsaved-edits ()
  (let* ((directory (make-temp-file "p3-live-bib-modified-" t))
         (p3/reference-bibliography-file
          (expand-file-name "references.bib" directory))
         buffer)
    (unwind-protect
        (progn
          (with-temp-file p3/reference-bibliography-file
            (insert "@article{alpha2020, title={Alpha Study}}\n"))
          (setq buffer (find-file-noselect p3/reference-bibliography-file))
          (with-current-buffer buffer
            (goto-char (point-max))
            (insert "\n% unsaved local bibliography edit\n")
            (p3/reference-add-keyword "alpha2020" "topic/live")
            (should (buffer-modified-p))
            (should (save-excursion
                      (goto-char (point-min))
                      (search-forward "topic/live" nil t)))
            (should (save-excursion
                      (goto-char (point-min))
                      (search-forward "unsaved local bibliography edit" nil t))))
          (with-temp-buffer
            (insert-file-contents p3/reference-bibliography-file)
            (should-not (search-forward "topic/live" nil t))
            (should-not (search-forward "unsaved local bibliography edit" nil t)))
          (with-current-buffer buffer
            (save-buffer))
          (with-temp-buffer
            (insert-file-contents p3/reference-bibliography-file)
            (should (search-forward "topic/live" nil t))
            (should (search-forward "unsaved local bibliography edit" nil t))))
      (when (buffer-live-p buffer)
        (kill-buffer buffer))
      (delete-directory directory t))))

(ert-deftest p3-reference-live-clean-bibliography-persists-and-stays-clean ()
  (let* ((directory (make-temp-file "p3-live-bib-clean-" t))
         (p3/reference-bibliography-file
          (expand-file-name "references.bib" directory))
         buffer)
    (unwind-protect
        (progn
          (with-temp-file p3/reference-bibliography-file
            (insert "@article{alpha2020, title={Alpha Study}}\n"))
          (setq buffer (find-file-noselect p3/reference-bibliography-file))
          (with-current-buffer buffer
            (should-not (buffer-modified-p))
            (p3/reference-add-keyword "alpha2020" "topic/live")
            (should-not (buffer-modified-p))
            (should (save-excursion
                      (goto-char (point-min))
                      (search-forward "topic/live" nil t))))
          (with-temp-buffer
            (insert-file-contents p3/reference-bibliography-file)
            (should (search-forward "topic/live" nil t))))
      (when (buffer-live-p buffer)
        (kill-buffer buffer))
      (delete-directory directory t))))

(provide 'p3-reference-reconstruction-test)

;;; p3-reference-reconstruction-test.el ends here
