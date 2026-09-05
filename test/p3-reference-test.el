;;; p3-reference-test.el --- Reference workflow tests -*- lexical-binding: t; -*-

(require 'ert)
(require 'cl-lib)

(defconst p3-reference-test--root
  (file-name-directory
   (directory-file-name
    (file-name-directory (or load-file-name buffer-file-name)))))
(add-to-list 'load-path (expand-file-name "lisp" p3-reference-test--root))
(require 'p3-reference)

(defmacro p3-reference-test--with-library (content &rest body)
  (declare (indent 1))
  `(let* ((directory (make-temp-file "p3-reference-" t))
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

(defconst p3-reference-test--two-entries
  "@article{alpha2020,\n  title = {Alpha},\n  doi = {10.1000/alpha}\n}\n\n% keep this comment exactly\n@article{beta2021,\n  title = {Beta}\n}\n")

(ert-deftest p3-reference-provisional-state-is-key-prefix-only ()
  (should (p3/reference-provisional-key-p "p3-inbox-20260905-140501"))
  (should-not (p3/reference-provisional-key-p "smith2026"))
  (should-not (p3/reference-provisional-key-p nil)))

(ert-deftest p3-reference-new-provisional-keys-are-reserved-and-distinct ()
  (let ((first (p3/reference--new-provisional-key))
        (second (p3/reference--new-provisional-key)))
    (should (string-prefix-p "p3-inbox-" first))
    (should (string-prefix-p "p3-inbox-" second))
    (should-not (equal first second))))

(ert-deftest p3-reference-load-does-not-create-bibliography ()
  (p3-reference-test--with-library nil
    (should-not (file-exists-p p3/reference-bibliography-file))
    (should (featurep 'p3-reference))
    (should-not (file-exists-p p3/reference-bibliography-file))))

(ert-deftest p3-reference-validation-rejects-duplicate-keys ()
  (should-error
   (p3/reference--validate-content
    "@article{x, title={A}}\n@book{x, title={B}}\n")))

(ert-deftest p3-reference-validation-rejects-malformed-bibtex ()
  (should-error
   (p3/reference--validate-content "@article{x, title={Unclosed}\n")))

(ert-deftest p3-reference-transaction-leaves-original-on-failure ()
  (p3-reference-test--with-library p3-reference-test--two-entries
    (let ((before (with-temp-buffer
                    (insert-file-contents p3/reference-bibliography-file)
                    (buffer-string))))
      (should-error
       (p3/reference--transaction
        (lambda ()
          (goto-char (point-max))
          (insert "\n@article{alpha2020, title={Duplicate}}\n"))))
      (with-temp-buffer
        (insert-file-contents p3/reference-bibliography-file)
        (should (equal before (buffer-string)))))))

(ert-deftest p3-reference-targeted-edit-preserves-unrelated-tail ()
  (p3-reference-test--with-library p3-reference-test--two-entries
    (let ((tail "% keep this comment exactly\n@article{beta2021,\n  title = {Beta}\n}\n"))
      (p3/reference--transaction
       (lambda ()
         (should (p3/reference--goto-entry "alpha2020"))
         (bibtex-set-field "title" "Alpha revised")))
      (with-temp-buffer
        (insert-file-contents p3/reference-bibliography-file)
        (should (string-suffix-p tail (buffer-string)))))))

(ert-deftest p3-reference-normalizes-doi-and-url ()
  (should (equal (p3/reference-normalize-doi
                  " https://doi.org/10.1000/ABC ")
                 "10.1000/abc"))
  (should (equal (p3/reference-normalize-url
                  "HTTPS://Example.COM/paper/#section")
                 "https://example.com/paper")))

(ert-deftest p3-reference-import-doi-duplicate-does-not-append ()
  (p3-reference-test--with-library
      "@article{alpha2020, title={Alpha}, doi={10.1000/alpha}}\n"
    (should
     (equal "alpha2020"
            (p3/reference-import-bibtex
             "@article{other, title={Other}, doi={https://doi.org/10.1000/ALPHA}}")))
    (with-temp-buffer
      (insert-file-contents p3/reference-bibliography-file)
      (should (= 1 (how-many "^@" (point-min) (point-max)))))))

(ert-deftest p3-reference-import-url-duplicate-does-not-append ()
  (p3-reference-test--with-library
      "@online{alpha2020, title={Alpha}, url={https://example.com/paper/}}\n"
    (should
     (equal "alpha2020"
            (p3/reference-import-bibtex
             "@online{other, title={Other}, url={HTTPS://EXAMPLE.COM/paper#top}}")))))

(ert-deftest p3-reference-title-match-never-auto-merges ()
  (p3-reference-test--with-library
      "@article{alpha2020, title={A Useful Study}}\n"
    (cl-letf (((symbol-function 'y-or-n-p) (lambda (&rest _) nil)))
      (should-error
       (p3/reference-import-bibtex
        "@article{beta2021, title={A useful study!}}")))
    (with-temp-buffer
      (insert-file-contents p3/reference-bibliography-file)
      (should-not (search-forward "beta2021" nil t)))))

(ert-deftest p3-reference-status-inbox-is-not-technical-provisional-state ()
  (should-not (p3/reference-provisional-key-p "alpha2020")))

(ert-deftest p3-reference-keywords-are-entry-local-and-idempotent ()
  (p3-reference-test--with-library p3-reference-test--two-entries
    (p3/reference-add-keyword "alpha2020" "quantitative-methods")
    (p3/reference-add-keyword "alpha2020" "quantitative-methods")
    (let ((entry (p3/reference--entry-alist "alpha2020")))
      (should (equal "quantitative-methods"
                     (cdr (assoc "keywords" entry)))))
    (should (equal "Beta"
                   (cdr (assoc "title"
                               (p3/reference--entry-alist "beta2021")))))))

(ert-deftest p3-reference-finalize-leaves-mature-key-unchanged ()
  (p3-reference-test--with-library "@article{alpha2020, title={Alpha}}\n"
    (should (equal "alpha2020" (p3/reference-finalize "alpha2020")))))

(ert-deftest p3-reference-finalize-needs-usable-generated-key ()
  (p3-reference-test--with-library
      "@online{p3-inbox-1, url={https://example.com}}\n"
    (cl-letf (((symbol-function 'p3/reference--propose-citekey)
               (lambda (_key) nil)))
      (should-error (p3/reference-finalize "p3-inbox-1")))))

(ert-deftest p3-reference-finalize-renames-only-provisional-head ()
  (p3-reference-test--with-library
      "@article{p3-inbox-1, title={Alpha}, author={Ada Alpha}, year={2020}}\n@article{beta2021, title={Beta}}\n"
    (cl-letf (((symbol-function 'p3/reference--propose-citekey)
               (lambda (_key) "alpha2020"))
              ((symbol-function 'read-string)
               (lambda (&rest _) "alpha2020")))
      (should (equal "alpha2020" (p3/reference-finalize "p3-inbox-1"))))
    (should (p3/reference--entry-alist "alpha2020"))
    (should (p3/reference--entry-alist "beta2021"))
    (should-not (p3/reference--entry-alist "p3-inbox-1"))))

(ert-deftest p3-reference-finalize-rejects-colliding-key ()
  (p3-reference-test--with-library
      "@article{p3-inbox-1, title={Alpha}}\n@article{alpha2020, title={Existing}}\n"
    (cl-letf (((symbol-function 'p3/reference--propose-citekey)
               (lambda (_key) "alpha2020"))
              ((symbol-function 'read-string)
               (lambda (&rest _) "alpha2020")))
      (should-error (p3/reference-finalize "p3-inbox-1")))))

(provide 'p3-reference-test)

;;; p3-reference-test.el ends here
