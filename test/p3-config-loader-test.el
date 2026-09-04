;;; p3-config-loader-test.el --- Tests for config cache loading -*- lexical-binding: t; -*-

(require 'ert)
(require 'cl-lib)

(defconst p3-config-loader-test--root
  (file-name-directory
   (directory-file-name
    (file-name-directory (or load-file-name buffer-file-name))))
  "Root of the Emacs configuration under test.")

(add-to-list 'load-path (expand-file-name "lisp" p3-config-loader-test--root))
(require 'p3-config-loader)

(defconst p3-config-loader-test--org-loaded-by-loader-p (featurep 'org))
(defconst p3-config-loader-test--ob-tangle-loaded-by-loader-p (featurep 'ob-tangle))

(require 'org)
(require 'ob-tangle)

(defun p3-config-loader-test--digest (path)
  "Return the SHA-256 digest of PATH's exact bytes."
  (with-temp-buffer
    (set-buffer-multibyte nil)
    (insert-file-contents-literally path)
    (secure-hash 'sha256 (current-buffer))))

(defmacro p3-config-loader-test--with-files (source-content &rest body)
  "Run BODY with temporary config source/cache files."
  (declare (indent 1))
  `(let* ((directory (make-temp-file "p3-config-loader-test-" t))
          (p3/config-source (expand-file-name "config.org" directory))
          (p3/config-generated (expand-file-name "config.el" directory)))
     (unwind-protect
         (progn
           (with-temp-file p3/config-source
             (insert ,source-content))
           ,@body)
       (delete-directory directory t))))

(defun p3-config-loader-test--write-current-cache (body)
  "Write BODY to the current temporary cache with a matching fingerprint."
  (let ((digest (p3-config-loader-test--digest p3/config-source)))
    (with-temp-file p3/config-generated
      (insert ";; p3-config-source-sha256: " digest "\n" body))))

(defun p3-config-loader-test--stage-files (directory)
  "Return staged config-cache files remaining in DIRECTORY."
  (directory-files directory t "\\`\\.p3-config-stage-"))

(ert-deftest p3-config-loader-does-not-load-org-at-module-load ()
  (should-not p3-config-loader-test--org-loaded-by-loader-p)
  (should-not p3-config-loader-test--ob-tangle-loaded-by-loader-p))

(ert-deftest p3-config-loader-missing-cache-is-stale ()
  (p3-config-loader-test--with-files "source"
    (should (p3/config-cache-stale-p))))

(ert-deftest p3-config-loader-missing-fingerprint-is-stale ()
  (p3-config-loader-test--with-files "source"
    (with-temp-file p3/config-generated
      (insert "(setq p3-test-cache t)\n"))
    (should (p3/config-cache-stale-p))))

(ert-deftest p3-config-loader-malformed-fingerprint-is-stale ()
  (p3-config-loader-test--with-files "source"
    (with-temp-file p3/config-generated
      (insert ";; p3-config-source-sha256: not-a-digest\n"))
    (should (p3/config-cache-stale-p))))

(ert-deftest p3-config-loader-mismatched-fingerprint-is-stale-regardless-of-mtime ()
  (p3-config-loader-test--with-files "source-v1"
    (p3-config-loader-test--write-current-cache "(setq p3-test-cache t)\n")
    (with-temp-file p3/config-source
      (insert "source-v2"))
    (set-file-times p3/config-source (seconds-to-time 1000000000))
    (set-file-times p3/config-generated (seconds-to-time 2000000000))
    (should (p3/config-cache-stale-p))))

(ert-deftest p3-config-loader-matching-fingerprint-is-current-regardless-of-mtime ()
  (p3-config-loader-test--with-files "source"
    (p3-config-loader-test--write-current-cache "(setq p3-test-cache t)\n")
    (set-file-times p3/config-generated (seconds-to-time 1000000000))
    (set-file-times p3/config-source (seconds-to-time 2000000000))
    (should-not (p3/config-cache-stale-p))))

(ert-deftest p3-config-loader-load-generated-uses-exact-el-file ()
  (p3-config-loader-test--with-files "source"
    (p3-config-loader-test--write-current-cache
     "(setq p3-config-loader-test--loaded 'source)\n")
    (with-temp-file (concat p3/config-generated "c")
      (insert "(setq p3-config-loader-test--loaded 'compiled)\n"))
    (setq p3-config-loader-test--loaded nil)
    (p3/config-load-generated)
    (should (eq p3-config-loader-test--loaded 'source))))

(ert-deftest p3-config-loader-current-cache-loads-without-build-or-org-require ()
  (p3-config-loader-test--with-files "source"
    (p3-config-loader-test--write-current-cache
     "(setq p3-config-loader-test--loaded 'current)\n")
    (setq p3-config-loader-test--loaded nil)
    (let ((original-require (symbol-function 'require)))
      (cl-letf (((symbol-function 'p3/config-build)
                 (lambda () (ert-fail "Current cache attempted a rebuild")))
                ((symbol-function 'require)
                 (lambda (feature &rest args)
                   (when (memq feature '(org ob-tangle))
                     (ert-fail (format "Current cache required %S" feature)))
                   (apply original-require feature args))))
        (p3/config-load)))
    (should (eq p3-config-loader-test--loaded 'current))))

(ert-deftest p3-config-loader-rejects-property-tangle-before-writing ()
  (p3-config-loader-test--with-files
      "#+PROPERTY: header-args:emacs-lisp :tangle escaped.el\n#+begin_src emacs-lisp\n(setq p3-test t)\n#+end_src\n"
    (let ((escaped (expand-file-name "escaped.el"
                                     (file-name-directory p3/config-source))))
      (should-error (p3/config-build))
      (should-not (file-exists-p escaped))
      (should-not (file-exists-p p3/config-generated)))))

(ert-deftest p3-config-loader-rejects-block-tangle-before-writing ()
  (p3-config-loader-test--with-files
      "#+begin_src emacs-lisp :tangle escaped.el\n(setq p3-test t)\n#+end_src\n"
    (let ((escaped (expand-file-name "escaped.el"
                                     (file-name-directory p3/config-source))))
      (should-error (p3/config-build))
      (should-not (file-exists-p escaped))
      (should-not (file-exists-p p3/config-generated)))))

(ert-deftest p3-config-loader-build-admits-only-emacs-lisp ()
  (p3-config-loader-test--with-files
      "#+begin_src emacs-lisp\n(setq p3-config-loader-test--language 'elisp)\n#+end_src\n#+begin_src shell\necho SHOULD_NOT_APPEAR\n#+end_src\n"
    (p3/config-build)
    (with-temp-buffer
      (insert-file-contents p3/config-generated)
      (should (search-forward "p3-config-loader-test--language" nil t))
      (goto-char (point-min))
      (should-not (search-forward "SHOULD_NOT_APPEAR" nil t)))))

(ert-deftest p3-config-loader-tangle-failure-preserves-cache-and-cleans-stage ()
  (p3-config-loader-test--with-files
      "#+begin_src emacs-lisp\n(setq p3-test t)\n#+end_src\n"
    (with-temp-file p3/config-generated
      (insert "old-cache"))
    (let ((directory (file-name-directory p3/config-generated)))
      (cl-letf (((symbol-function 'org-babel-tangle-file)
                 (lambda (&rest _) (error "synthetic tangle failure"))))
        (should-error (p3/config-build)))
      (should (equal (with-temp-buffer
                       (insert-file-contents p3/config-generated)
                       (buffer-string))
                     "old-cache"))
      (should-not (p3-config-loader-test--stage-files directory)))))

(ert-deftest p3-config-loader-malformed-output-preserves-cache ()
  (p3-config-loader-test--with-files
      "#+begin_src emacs-lisp\n(setq p3-test t)\n#+end_src\n"
    (with-temp-file p3/config-generated
      (insert "old-cache"))
    (cl-letf (((symbol-function 'org-babel-tangle-file)
               (lambda (_source target _language)
                 (with-temp-file target (insert "(unclosed"))
                 (list target))))
      (should-error (p3/config-build)))
    (should (equal (with-temp-buffer
                     (insert-file-contents p3/config-generated)
                     (buffer-string))
                   "old-cache"))))

(ert-deftest p3-config-loader-rejects-unexpected-tangle-output ()
  (p3-config-loader-test--with-files
      "#+begin_src emacs-lisp\n(setq p3-test t)\n#+end_src\n"
    (with-temp-file p3/config-generated
      (insert "old-cache"))
    (cl-letf (((symbol-function 'org-babel-tangle-file)
               (lambda (_source target _language)
                 (with-temp-file target (insert "(setq p3-test t)\n"))
                 (list target
                       (expand-file-name "unexpected.el"
                                         (file-name-directory target)))))))
      (should-error (p3/config-build)))
    (should (equal (with-temp-buffer
                     (insert-file-contents p3/config-generated)
                     (buffer-string))
                   "old-cache"))))

(ert-deftest p3-config-loader-source-change-during-build-preserves-cache ()
  (p3-config-loader-test--with-files
      "#+begin_src emacs-lisp\n(setq p3-test 'old)\n#+end_src\n"
    (with-temp-file p3/config-generated
      (insert "old-cache"))
    (cl-letf (((symbol-function 'org-babel-tangle-file)
               (lambda (_source target _language)
                 (with-temp-file target (insert "(setq p3-test 'old)\n"))
                 (with-temp-file p3/config-source
                   (insert "#+begin_src emacs-lisp\n(setq p3-test 'new)\n#+end_src\n"))
                 (list target))))
      (should-error (p3/config-build)))
    (should (equal (with-temp-buffer
                     (insert-file-contents p3/config-generated)
                     (buffer-string))
                   "old-cache"))))

(ert-deftest p3-config-loader-build-replaces-existing-cache ()
  (p3-config-loader-test--with-files
      "#+begin_src emacs-lisp\n(setq p3-config-loader-test--replacement 'new)\n#+end_src\n"
    (with-temp-file p3/config-generated
      (insert "old-cache"))
    (let ((directory (file-name-directory p3/config-generated)))
      (should (equal (p3/config-build) p3/config-generated))
      (should (commandp #'p3/config-build))
      (should-not (p3/config-cache-stale-p))
      (with-temp-buffer
        (insert-file-contents p3/config-generated)
        (goto-char (point-min))
        (should (looking-at ";; p3-config-source-sha256: [0-9a-f]\\{64\\}$"))
        (should (search-forward "p3-config-loader-test--replacement" nil t)))
      (should-not (p3-config-loader-test--stage-files directory)))))

(ert-deftest p3-config-loader-missing-cache-rebuilds-before-load ()
  (p3-config-loader-test--with-files
      "#+begin_src emacs-lisp\n(setq p3-config-loader-test--loaded 'fresh)\n#+end_src\n"
    (setq p3-config-loader-test--loaded nil)
    (p3/config-load)
    (should (eq p3-config-loader-test--loaded 'fresh))
    (should-not (p3/config-cache-stale-p))))

(ert-deftest p3-config-loader-mismatched-cache-rebuilds-before-load ()
  (p3-config-loader-test--with-files
      "#+begin_src emacs-lisp\n(setq p3-config-loader-test--loaded 'fresh)\n#+end_src\n"
    (with-temp-file p3/config-generated
      (insert ";; p3-config-source-sha256: "
              (make-string 64 ?0)
              "\n(setq p3-config-loader-test--loaded 'stale)\n"))
    (setq p3-config-loader-test--loaded nil)
    (p3/config-load)
    (should (eq p3-config-loader-test--loaded 'fresh))
    (should-not (p3/config-cache-stale-p))))

(ert-deftest p3-config-loader-explicit-build-rebuilds-current-cache ()
  (p3-config-loader-test--with-files
      "#+begin_src emacs-lisp\n(setq p3-config-loader-test--explicit-build t)\n#+end_src\n"
    (p3/config-build)
    (should-not (p3/config-cache-stale-p))
    (let ((original-tangle (symbol-function 'org-babel-tangle-file))
          (calls 0))
      (cl-letf (((symbol-function 'org-babel-tangle-file)
                 (lambda (&rest args)
                   (setq calls (1+ calls))
                   (apply original-tangle args))))
        (p3/config-build))
      (should (= calls 1)))))

(provide 'p3-config-loader-test)

;;; p3-config-loader-test.el ends here
