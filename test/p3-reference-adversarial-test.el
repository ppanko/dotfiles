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
          (should (equal (expand-file-name "alpha2020.org" directory)
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
