;;; p3-r-alignment-test.el --- R assignment alignment regressions -*- lexical-binding: t; -*-

(require 'ert)
(require 'bytecomp)

(defconst p3-r-alignment-test--root
  (file-name-directory
   (directory-file-name
    (file-name-directory (or load-file-name buffer-file-name)))))

(add-to-list 'load-path (expand-file-name "lisp" p3-r-alignment-test--root))

(defconst p3-r-alignment-test--loaded
  (require 'p3-r-alignment nil t)
  "Non-nil when the R alignment behavior module is available.")

(defun p3-r-alignment-test--contents (relative)
  "Return contents of RELATIVE under the repository root."
  (with-temp-buffer
    (insert-file-contents (expand-file-name relative p3-r-alignment-test--root))
    (buffer-string)))

(defun p3-r-alignment-test--syntax-table ()
  "Return the R syntax subset needed by alignment tests."
  (let ((table (make-syntax-table)))
    (modify-syntax-entry ?# "<" table)
    (modify-syntax-entry ?\n ">" table)
    (modify-syntax-entry ?\" "\"" table)
    (modify-syntax-entry ?' "\"" table)
    (modify-syntax-entry ?\( "()" table)
    (modify-syntax-entry ?\) ")(" table)
    (modify-syntax-entry ?\[ "(]" table)
    (modify-syntax-entry ?\] ")[" table)
    (modify-syntax-entry ?{ "(}" table)
    (modify-syntax-entry ?} "){" table)
    table))

(defmacro p3-r-alignment-test--with-buffer (text &rest body)
  "Evaluate BODY in a temporary R-like buffer containing TEXT."
  (declare (indent 1) (debug t))
  `(with-temp-buffer
     (set-syntax-table (p3-r-alignment-test--syntax-table))
     (insert ,text)
     (goto-char (point-min))
     ,@body))

(ert-deftest p3-r-alignment-module-byte-compiles-cleanly ()
  (should p3-r-alignment-test--loaded)
  (let* ((source (expand-file-name "lisp/p3-r-alignment.el"
                                   p3-r-alignment-test--root))
         (compiled (byte-compile-dest-file source))
         (byte-compile-error-on-warn t))
    (unwind-protect
        (should (byte-compile-file source))
      (when (file-exists-p compiled)
        (delete-file compiled)))))

(ert-deftest p3-r-alignment-aligns-outer-and-nested-scopes-independently ()
  (should p3-r-alignment-test--loaded)
  (p3-r-alignment-test--with-buffer
      (concat "a <- 1\n"
              "long_name <- 2\n"
              "\n"
              "result <- list(\n"
              "  x = 1,\n"
              "  longer_name = 2\n"
              ")\n")
    (p3-r-align-assignments)
    (should
     (equal
      (buffer-string)
      (concat "a         <- 1\n"
              "long_name <- 2\n"
              "\n"
              "result <- list(\n"
              "  x           = 1,\n"
              "  longer_name = 2\n"
              ")\n")))))

(ert-deftest p3-r-alignment-does-not-cross-scope-with-the-same-operator ()
  (should p3-r-alignment-test--loaded)
  (p3-r-alignment-test--with-buffer
      (concat "outer <- {\n"
              "  x <- 1\n"
              "  longer_name <- 2\n"
              "}\n")
    (p3-r-align-assignments)
    (should
     (equal
      (buffer-string)
      (concat "outer <- {\n"
              "  x           <- 1\n"
              "  longer_name <- 2\n"
              "}\n")))))

(ert-deftest p3-r-alignment-keeps-operator-classes-and-separators-independent ()
  (should p3-r-alignment-test--loaded)
  (let ((source
         (concat "a <- 1\n"
                 "long_name = 2\n"
                 "b <- 3\n"
                 "\n"
                 "single <- 4\n"
                 "# separator\n"
                 "much_longer <- 5\n")))
    (p3-r-alignment-test--with-buffer source
      (p3-r-align-assignments)
      (should (equal (buffer-string) source)))))

(ert-deftest p3-r-alignment-ignores-comparisons-comments-and-string-contents ()
  (should p3-r-alignment-test--loaded)
  (p3-r-alignment-test--with-buffer
      (concat "x <- 1\n"
              "long_name <- 2\n"
              "flag <- x == long_name\n"
              "text <- \"fake = operator\"\n"
              "# pretend <- assignment\n")
    (p3-r-align-assignments)
    (should
     (equal
      (buffer-string)
      (concat "x         <- 1\n"
              "long_name <- 2\n"
              "flag      <- x == long_name\n"
              "text      <- \"fake = operator\"\n"
              "# pretend <- assignment\n")))))

(ert-deftest p3-r-alignment-is-idempotent ()
  (should p3-r-alignment-test--loaded)
  (p3-r-alignment-test--with-buffer "a <- 1\nlong_name <- 2\n"
    (p3-r-align-assignments)
    (let ((once (buffer-string)))
      (p3-r-align-assignments)
      (should (equal (buffer-string) once)))))

(ert-deftest p3-r-alignment-on-save-hook-is-buffer-local-and-optional ()
  (should p3-r-alignment-test--loaded)
  (p3-r-alignment-test--with-buffer "a <- 1\nlong_name <- 2\n"
    (setq-local before-save-hook nil)
    (let ((p3-r-align-on-save t))
      (p3-r-enable-alignment-on-save)
      (should (local-variable-p 'before-save-hook))
      (should (memq #'p3-r-align-before-save before-save-hook))
      (run-hooks 'before-save-hook)
      (should (equal (buffer-string)
                     "a         <- 1\nlong_name <- 2\n"))))
  (p3-r-alignment-test--with-buffer "a <- 1\nlong_name <- 2\n"
    (setq-local before-save-hook nil)
    (let ((p3-r-align-on-save nil))
      (p3-r-enable-alignment-on-save)
      (run-hooks 'before-save-hook)
      (should (equal (buffer-string)
                     "a <- 1\nlong_name <- 2\n")))))

(ert-deftest p3-r-alignment-setup-registers-only-the-r-mode-hook ()
  (should p3-r-alignment-test--loaded)
  (let ((was-bound (boundp 'ess-r-mode-hook))
        (original (and (boundp 'ess-r-mode-hook)
                       (default-value 'ess-r-mode-hook))))
    (unwind-protect
        (progn
          (set-default 'ess-r-mode-hook nil)
          (p3-r-alignment-setup)
          (should
           (equal (default-value 'ess-r-mode-hook)
                  '(p3-r-enable-alignment-on-save))))
      (if was-bound
          (set-default 'ess-r-mode-hook original)
        (makunbound 'ess-r-mode-hook)))))

(ert-deftest p3-r-alignment-ess-config-enables-module ()
  (let ((config (p3-r-alignment-test--contents "lisp/p3-config-ess.el")))
    (should
     (string-match-p
      (regexp-quote "(p3/config-load-module 'p3-r-alignment)") config))
    (should
     (string-match-p
      (regexp-quote "(p3-r-alignment-setup)") config))))

(provide 'p3-r-alignment-test)

;;; p3-r-alignment-test.el ends here
