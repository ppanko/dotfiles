;;; p3-reference-adversarial-test.el --- Adversarial reference regressions -*- lexical-binding: t; -*-

(require 'ert)
(require 'cl-lib)
(require 'subr-x)

(defconst p3-reference-adversarial-test--root
  (file-name-directory
   (directory-file-name
    (file-name-directory (or load-file-name buffer-file-name)))))
(add-to-list 'load-path
             (expand-file-name "lisp" p3-reference-adversarial-test--root))
(require 'p3-reference)

(defvar citar-bibliography)
(defvar org-roam-directory)

(defmacro p3-reference-adversarial-test--with-library (content &rest body)
  (declare (indent 1))
  `(let* ((directory (make-temp-file "p3-reference-adversarial-" t))
          (p3/reference-bibliography-file
           (expand-file-name "references.bib" directory))
          (p3/reference-pdf-directory
           (expand-file-name "papers/" directory)))
     (unwind-protect
         (progn
           (when ,content
             (with-temp-file p3/reference-bibliography-file
               (insert ,content)))
           ,@body)
       (delete-directory directory t))))

(ert-deftest p3-reference-new-import-rejects-casefold-path-collision ()
  (p3-reference-adversarial-test--with-library
      "@article{Smith2024, title={First}}\n"
    (should-error
     (p3/reference-import-bibtex
      "@article{smith2024, title={Second}}")
     :type 'user-error)))

(ert-deftest p3-reference-finalization-rejects-casefold-path-collision ()
  (p3-reference-adversarial-test--with-library
      "@article{Smith2024, title={Existing}}\n@article{p3-inbox-1, title={New}}\n"
    (cl-letf (((symbol-function 'p3/reference--propose-citekey)
               (lambda (_key) "smith2024"))
              ((symbol-function 'read-string)
               (lambda (&rest _) "smith2024")))
      (should-error
       (p3/reference-finalize "p3-inbox-1")
       :type 'user-error))))

(ert-deftest p3-reference-pdf-path-rejects-casefold-ambiguous-legacy-library ()
  (p3-reference-adversarial-test--with-library
      "@article{Smith2024, title={First}}\n@article{smith2024, title={Second}}\n"
    (should-error
     (p3/reference-pdf-path "smith2024")
     :type 'user-error)))

(ert-deftest p3-reference-entry-lookup-is-case-sensitive ()
  (p3-reference-adversarial-test--with-library
      "@article{Smith2024, title={Upper}}\n@article{smith2024, title={Lower}}\n"
    (should (equal "Upper"
                   (cdr (assoc "title"
                               (p3/reference--entry-alist "Smith2024")))))
    (should (equal "Lower"
                   (cdr (assoc "title"
                               (p3/reference--entry-alist "smith2024")))))))

(ert-deftest p3-reference-project-removal-is-case-sensitive ()
  (let ((file (make-temp-file
               "p3-project-case-" nil ".org"
               "#+title: Example\n#+filetags: :project:\n\n* References\n\n[cite:@Smith2024]\n[cite:@smith2024]\n")))
    (unwind-protect
        (cl-letf (((symbol-function 'p3/reference--project-file)
                   (lambda (_node) file))
                  ((symbol-function 'p3/reference--project-node-p)
                   (lambda (_node) t)))
          (p3/reference-remove-project-association "smith2024" 'project-node)
          (with-temp-buffer
            (insert-file-contents file)
            (let ((case-fold-search nil))
              (should (search-forward "[cite:@Smith2024]" nil t))
              (goto-char (point-min))
              (should-not (search-forward "[cite:@smith2024]" nil t)))))
      (delete-file file))))

(ert-deftest p3-reference-selector-is-confined-to-canonical-bibliography ()
  (p3-reference-adversarial-test--with-library
      "@article{alpha2020, title={Canonical}}\n"
    (let (seen-bibliography seen-mode seen-filter)
      (cl-letf (((symbol-function 'require) (lambda (&rest _) t))
                ((symbol-function 'citar-select-ref)
                 (lambda (&rest args)
                   (setq seen-bibliography citar-bibliography
                         seen-mode major-mode
                         seen-filter (plist-get args :filter))
                   "alpha2020")))
        (should (equal "alpha2020" (p3/reference--select-key)))
        (should (equal (list p3/reference-bibliography-file)
                       seen-bibliography))
        (should (eq 'fundamental-mode seen-mode))
        (should (funcall seen-filter "alpha2020"))
        (should-not (funcall seen-filter "local-only"))))))

(ert-deftest p3-reference-display-title-prefers-canonical-entry ()
  (p3-reference-adversarial-test--with-library
      "@article{alpha2020, title={Canonical title}}\n"
    (cl-letf (((symbol-function 'require) (lambda (&rest _) t))
              ((symbol-function 'citar-get-value)
               (lambda (&rest _) "Shadow title")))
      (should (equal "Canonical title"
                     (p3/reference--display-title "alpha2020"))))))

(ert-deftest p3-reference-open-url-prefers-canonical-entry ()
  (p3-reference-adversarial-test--with-library
      "@online{alpha2020, title={Canonical}, url={https://canonical.example/paper}}\n"
    (let (opened)
      (cl-letf (((symbol-function 'require) (lambda (&rest _) t))
                ((symbol-function 'citar-get-value)
                 (lambda (field _key)
                   (when (equal field "url") "https://shadow.example/paper")))
                ((symbol-function 'browse-url)
                 (lambda (url &rest _) (setq opened url))))
        (p3/reference-open-url "alpha2020")
        (should (equal "https://canonical.example/paper" opened))))))

(ert-deftest p3-reference-edit-entry-opens-canonical-bibliography ()
  (p3-reference-adversarial-test--with-library
      "@article{Smith2024, title={Upper}}\n@article{smith2024, title={Lower}}\n"
    (let (bibliography-buffer)
      (unwind-protect
          (cl-letf (((symbol-function 'require) (lambda (&rest _) t))
                    ((symbol-function 'citar-open-entry)
                     (lambda (&rest _)
                       (ert-fail "Citar must not choose the bibliography file"))))
            (p3/reference-edit-entry "smith2024")
            (setq bibliography-buffer (current-buffer))
            (should (file-equal-p p3/reference-bibliography-file
                                  (buffer-file-name bibliography-buffer)))
            (should (equal "smith2024"
                           (cdr (assoc "=key=" (bibtex-parse-entry t))))))
        (when (buffer-live-p bibliography-buffer)
          (set-buffer-modified-p nil)
          (kill-buffer bibliography-buffer))))))

(ert-deftest p3-reference-note-rejects-unrelated-existing-citekey-file ()
  (let* ((directory (make-temp-file "p3-note-collision-" t))
         (org-roam-directory directory)
         (path (expand-file-name "alpha2020.org" directory)))
    (unwind-protect
        (progn
          (with-temp-file path
            (insert "#+title: Unrelated note\n\nNo reference property here.\n"))
          (cl-letf (((symbol-function 'require) (lambda (&rest _) t))
                    ((symbol-function 'org-roam-node-from-ref) (lambda (_ref) nil))
                    ((symbol-function 'citar-get-value) (lambda (&rest _) "Alpha Study")))
            (should-error
             (p3/reference-note "alpha2020")
             :type 'user-error))
          (with-temp-buffer
            (insert-file-contents path)
            (should (equal "#+title: Unrelated note\n\nNo reference property here.\n"
                           (buffer-string)))))
      (delete-directory directory t))))

(ert-deftest p3-reference-note-prefers-citar-key-at-point-over-prompt ()
  (let (looked-up visited)
    (cl-letf (((symbol-function 'require) (lambda (&rest _) t))
              ((symbol-function 'citar-key-at-point) (lambda () "alpha2020"))
              ((symbol-function 'p3/reference--select-key)
               (lambda (&rest _) (ert-fail "Reference selector should not run")))
              ((symbol-function 'org-roam-node-from-ref)
               (lambda (ref) (setq looked-up ref) 'existing-node))
              ((symbol-function 'org-roam-node-visit)
               (lambda (node &rest _) (setq visited node))))
      (p3/reference-note)
      (should (equal "@alpha2020" looked-up))
      (should (eq 'existing-node visited)))))

(ert-deftest p3-reference-new-note-leaves-point-in-body ()
  (let* ((directory (make-temp-file "p3-note-body-" t))
         (org-roam-directory directory)
         note-buffer)
    (unwind-protect
        (cl-letf (((symbol-function 'require) (lambda (&rest _) t))
                  ((symbol-function 'org-roam-node-from-ref) (lambda (_ref) nil))
                  ((symbol-function 'org-id-new) (lambda () "note-id"))
                  ((symbol-function 'citar-get-value)
                   (lambda (field _key)
                     (if (equal field "title") "Alpha Study" nil))))
          (p3/reference-note "alpha2020")
          (setq note-buffer (current-buffer))
          (should (file-equal-p (expand-file-name "alpha2020.org" directory)
                                (buffer-file-name note-buffer)))
          (should (= (point) (point-max)))
          (should (> (point)
                     (save-excursion
                       (goto-char (point-min))
                       (re-search-forward "^#\\+filetags:" nil t)
                       (point)))))
      (when (buffer-live-p note-buffer)
        (set-buffer-modified-p nil)
        (kill-buffer note-buffer))
      (delete-directory directory t))))

(ert-deftest p3-reference-config-registers-biblio-action-at-core-load-boundary ()
  (let ((contents
         (with-temp-buffer
           (insert-file-contents
            (expand-file-name "lisp/p3-config-reference.el"
                              p3-reference-adversarial-test--root))
           (buffer-string))))
    (should
     (string-match-p
      (regexp-quote "(with-eval-after-load 'biblio-core") contents))
    (should
     (string-match-p
      (regexp-quote "Save/enrich in P3 library") contents))))

(provide 'p3-reference-adversarial-test)

;;; p3-reference-adversarial-test.el ends here
