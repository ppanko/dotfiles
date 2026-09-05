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

(provide 'p3-reference-test)

;;; p3-reference-test.el ends here
