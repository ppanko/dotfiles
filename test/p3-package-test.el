;;; p3-package-test.el --- Tests for resilient package bootstrap -*- lexical-binding: t; -*-

(require 'ert)
(require 'cl-lib)
(require 'package)
(require 'p3-package)

(defun p3-package-test--write-package (directory)
  "Write a minimal p3-broken package into DIRECTORY without autoloads."
  (make-directory directory t)
  (with-temp-file (expand-file-name "p3-broken-pkg.el" directory)
    (insert "(define-package \"p3-broken\" \"1.0\" \"Broken package fixture\" nil)\n"))
  (with-temp-file (expand-file-name "p3-broken.el" directory)
    (insert ";;; p3-broken.el --- Test fixture\n\n"
            ";;;###autoload\n"
            "(defun p3-broken-command () t)\n\n"
            "(provide 'p3-broken)\n"))
  directory)

(ert-deftest p3-package-repairs-installed-package-with-missing-autoloads ()
  (let* ((root (make-temp-file "p3-package-test-" t))
         (package-user-dir root)
         (package-directory-list nil)
         (package-alist nil)
         (package-activated-list nil)
         (package--initialized t)
         (p3/package-refresh-attempted nil)
         (directory (expand-file-name "p3-broken-1.0" root))
         (autoload-file (expand-file-name "p3-broken-autoloads.el" directory)))
    (unwind-protect
        (progn
          (p3-package-test--write-package directory)
          (package-load-descriptor directory)

          ;; package.el sees the descriptor and reports the package installed,
          ;; even though activation cannot load its generated autoload file.
          (should (package-installed-p 'p3-broken))
          (should-not (file-exists-p autoload-file))
          (should-not (p3/package-installation-healthy-p 'p3-broken))

          (cl-letf (((symbol-function 'package-install)
                     (lambda (&rest _)
                       (ert-fail
                        "repairable package unexpectedly reached package-install")))
                    ((symbol-function 'package-refresh-contents)
                     (lambda ()
                       (ert-fail
                        "repairable package unexpectedly refreshed archives"))))
            (should (eq (p3/package-install-resilient 'p3-broken)
                        'p3-broken)))

          (should (file-readable-p autoload-file))
          (should (p3/package-installation-healthy-p 'p3-broken))
          (should (memq 'p3-broken package-activated-list)))
      (delete-directory root t))))

(ert-deftest p3-package-reinstalls-when-recorded-package-directory-is-gone ()
  (let* ((root (make-temp-file "p3-package-test-" t))
         (package-user-dir root)
         (package-directory-list nil)
         (package-alist nil)
         (package-activated-list nil)
         (package--initialized t)
         (p3/package-refresh-attempted nil)
         (directory (expand-file-name "p3-broken-1.0" root))
         installed)
    (unwind-protect
        (progn
          (p3-package-test--write-package directory)
          (package-load-descriptor directory)
          (delete-directory directory t)

          ;; A stale descriptor is enough for package-installed-p to succeed.
          (should (package-installed-p 'p3-broken))
          (should-not (p3/package-installation-healthy-p 'p3-broken))

          (cl-letf (((symbol-function 'package-install)
                     (lambda (package dont-select)
                       (setq installed (list package dont-select))
                       (p3-package-test--write-package directory)
                       (package-load-descriptor directory)
                       (package-generate-autoloads package directory))))
            (should (eq (p3/package-install-resilient 'p3-broken)
                        'p3-broken)))

          (should (equal installed '(p3-broken t)))
          (should (p3/package-installation-healthy-p 'p3-broken)))
      (delete-directory root t))))

(ert-deftest p3-use-package-ensure-stops-after-bootstrap-failure ()
  (cl-letf (((symbol-function 'p3/package-install-resilient)
             (lambda (_package)
               (error "simulated bootstrap failure"))))
    (let ((err (should-error
                (p3/use-package-ensure 'demo '(demo) nil)
                :type 'error)))
      (should
       (string-match-p
        (regexp-quote
         "Package bootstrap failed for `demo': simulated bootstrap failure")
        (error-message-string err))))))

(provide 'p3-package-test)

;;; p3-package-test.el ends here
