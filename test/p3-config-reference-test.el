;;; p3-config-reference-test.el --- Reference config boundary tests -*- lexical-binding: t; -*-

(require 'ert)
(require 'subr-x)

(defconst p3-config-reference-test--root
  (file-name-directory
   (directory-file-name
    (file-name-directory (or load-file-name buffer-file-name)))))

(defun p3-config-reference-test--contents ()
  (with-temp-buffer
    (insert-file-contents
     (expand-file-name "lisp/p3-config-reference.el"
                       p3-config-reference-test--root))
    (buffer-string)))

(ert-deftest p3-config-reference-preserves-current-data-roots ()
  (let ((contents (p3-config-reference-test--contents)))
    (should (string-match-p (regexp-quote "~/org/bib/main.bib") contents))
    (should (string-match-p (regexp-quote "~/org/lib/") contents))))

(ert-deftest p3-config-reference-loads-behavior-before-prefix-binding ()
  (let* ((contents (p3-config-reference-test--contents))
         (behavior (string-match
                    (regexp-quote "(p3/config-load-module 'p3-reference)")
                    contents))
         (binding (string-match
                   (regexp-quote
                    "(global-set-key (kbd \"C-c b\") p3/reference-command-map)")
                   contents)))
    (should behavior)
    (should binding)
    (should (< behavior binding))))

(ert-deftest p3-config-reference-wires-org-cite-citar-and-biblio ()
  (let ((contents (p3-config-reference-test--contents)))
    (dolist (needle '("org-cite-global-bibliography"
                      "org-cite-insert-processor 'citar"
                      "org-cite-follow-processor 'citar"
                      "org-cite-activate-processor 'citar"
                      "citar-bibliography"
                      "(use-package biblio"
                      "Save/enrich in P3 library"))
      (should (string-match-p (regexp-quote needle) contents)))))

(ert-deftest p3-config-reference-pdf-tools-is-lazy-and-never-installs-backend ()
  (let ((contents (p3-config-reference-test--contents)))
    (should (string-match-p (regexp-quote "(use-package pdf-tools") contents))
    (should-not (string-match-p "pdf-tools-install" contents))))

(ert-deftest p3-config-reference-has-no-old-citation-stack ()
  (let ((contents (p3-config-reference-test--contents)))
    (dolist (needle '("citar-org-roam" "reftex-default-bibliography"
                      "reftex-cite-format" "bib-files-directory"))
      (should-not (string-match-p (regexp-quote needle) contents)))))

(provide 'p3-config-reference-test)

;;; p3-config-reference-test.el ends here
