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

(provide 'p3-reference-reconstruction-test)

;;; p3-reference-reconstruction-test.el ends here
