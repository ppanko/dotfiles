;;; p3-package-test.el --- Tests for resilient package bootstrap -*- lexical-binding: t; -*-

(require 'ert)
(require 'cl-lib)
(require 'package)
(require 'p3-package)

(defun p3-package-test--write-package (directory &optional version)
  "Write a minimal p3-broken package into DIRECTORY."
  (setq version (or version "1.0"))
  (make-directory directory t)
  (with-temp-file (expand-file-name "p3-broken-pkg.el" directory)
    (insert (format "(define-package \"p3-broken\" \"%s\" \"Package fixture\" nil)\n"
                    version)))
  (with-temp-file (expand-file-name "p3-broken.el" directory)
    (insert ";;; p3-broken.el --- Test fixture\n\n"
            ";;;###autoload\n"
            "(defun p3-broken-command () t)\n\n"
            "(provide 'p3-broken)\n"))
  directory)

(ert-deftest p3-package-setup-repairs-before-activation ()
  (let* ((root (make-temp-file "p3-package-test-" t))
         (package-user-dir root)
         (package-directory-list nil)
         (package-alist nil)
         (package-activated-list nil)
         (package-archive-contents nil)
         (package-selected-packages nil)
         (package-pinned-packages nil)
         (package-load-list '(all))
         (package--initialized nil)
         (load-path (copy-sequence load-path))
         (directory (expand-file-name "p3-broken-1.0" root))
         (autoload-file (expand-file-name "p3-broken-autoloads.el" directory)))
    (unwind-protect
        (progn
          (p3-package-test--write-package directory)
          (package-load-descriptor directory)
          (should-not (file-exists-p autoload-file))

          ;; Exercise the same setup ordering used by init.el: initialize
          ;; package records without activation, repair, then activate.
          (p3/package-setup)

          (should (file-readable-p autoload-file))
          (should (memq 'p3-broken package-activated-list))
          (should (p3/package-autoloads-healthy-p 'p3-broken)))
      (delete-directory root t))))

(ert-deftest p3-package-setup-reinstalls-when-startup-repair-fails ()
  (let* ((root (make-temp-file "p3-package-test-" t))
         (package-user-dir root)
         (package-directory-list nil)
         (package-alist nil)
         (package-activated-list nil)
         (package-archive-contents nil)
         (package-selected-packages nil)
         (package-pinned-packages nil)
         (package-load-list '(all))
         (package--initialized nil)
         (load-path (copy-sequence load-path))
         (directory (expand-file-name "p3-broken-1.0" root))
         installed)
    (unwind-protect
        (progn
          (p3-package-test--write-package directory)
          (package-load-descriptor directory)
          (cl-letf (((symbol-function 'package-generate-autoloads)
                     (lambda (&rest _)
                       (error "simulated unrecoverable autoload failure")))
                    ((symbol-function 'package-install)
                     (lambda (package _dont-select)
                       (setq installed package)
                       (p3-package-test--write-package directory)
                       (package-load-descriptor directory)
                       (with-temp-file
                           (expand-file-name "p3-broken-autoloads.el" directory)
                         (insert ";;; repaired fixture\n")))))
            (p3/package-setup))
          (should (eq installed 'p3-broken))
          (should (p3/package-autoloads-healthy-p 'p3-broken))
          (should (memq 'p3-broken package-activated-list)))
      (delete-directory root t))))

(ert-deftest p3-package-repairs-installed-package-with-missing-autoloads ()
  (let* ((root (make-temp-file "p3-package-test-" t))
         (package-user-dir root)
         (package-directory-list nil)
         (package-alist nil)
         (package-activated-list nil)
         (package-archive-contents nil)
         (package-selected-packages nil)
         (package-load-list '(all))
         (package--initialized t)
         (load-path (copy-sequence load-path))
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
          (should-not (p3/package-autoloads-healthy-p 'p3-broken))

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
          (should (p3/package-autoloads-healthy-p 'p3-broken))
          (should (memq 'p3-broken package-activated-list)))
      (delete-directory root t))))

(ert-deftest p3-package-reinstalls-broken-newest-version ()
  (let* ((root (make-temp-file "p3-package-test-" t))
         (package-user-dir root)
         (package-directory-list nil)
         (package-alist nil)
         (package-activated-list nil)
         (package-archive-contents nil)
         (package-selected-packages nil)
         (package-load-list '(all))
         (package--initialized t)
         (load-path (copy-sequence load-path))
         (p3/package-refresh-attempted nil)
         (old-directory (expand-file-name "p3-broken-1.0" root))
         (new-directory (expand-file-name "p3-broken-2.0" root))
         installed)
    (unwind-protect
        (progn
          (p3-package-test--write-package old-directory "1.0")
          (package-load-descriptor old-directory)
          (p3-package-test--write-package new-directory "2.0")
          (package-load-descriptor new-directory)
          ;; The newest descriptor is recorded but its package directory is gone.
          ;; This is unrecoverable, so it must not fall back to 1.0.
          (delete-directory new-directory t)
          (should (equal (package-desc-version
                          (car (p3/package--descriptors 'p3-broken)))
                         '(2 0)))
          (should-not (p3/package-autoloads-healthy-p 'p3-broken))

          (cl-letf (((symbol-function 'package-install)
                     (lambda (package _dont-select)
                       (setq installed package)
                       (p3-package-test--write-package new-directory "2.0")
                       (package-load-descriptor new-directory)
                       (package-generate-autoloads package new-directory))))
            (should (eq (p3/package-install-resilient 'p3-broken)
                        'p3-broken)))

          ;; Do not silently accept the healthy 1.0 installation after removing
          ;; the broken 2.0 descriptor.
          (should (eq installed 'p3-broken))
          (should (file-readable-p
                   (expand-file-name "p3-broken-autoloads.el" new-directory)))
          (should (equal (package-desc-version
                          (car (p3/package--descriptors 'p3-broken)))
                         '(2 0))))
      (delete-directory root t))))

(ert-deftest p3-package-reinstalls-when-recorded-package-directory-is-gone ()
  (let* ((root (make-temp-file "p3-package-test-" t))
         (package-user-dir root)
         (package-directory-list nil)
         (package-alist nil)
         (package-activated-list nil)
         (package-archive-contents nil)
         (package-selected-packages nil)
         (package-load-list '(all))
         (package--initialized t)
         (load-path (copy-sequence load-path))
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
          (should-not (p3/package-autoloads-healthy-p 'p3-broken))

          (cl-letf (((symbol-function 'package-install)
                     (lambda (package dont-select)
                       (setq installed (list package dont-select))
                       (p3-package-test--write-package directory)
                       (package-load-descriptor directory)
                       (package-generate-autoloads package directory))))
            (should (eq (p3/package-install-resilient 'p3-broken)
                        'p3-broken)))

          (should (equal installed '(p3-broken t)))
          (should (p3/package-autoloads-healthy-p 'p3-broken)))
      (delete-directory root t))))

(ert-deftest p3-package-does-not-repair-system-wide-package ()
  (let* ((root (make-temp-file "p3-package-test-" t))
         (system-root (make-temp-file "p3-package-system-" t))
         (package-user-dir root)
         (package-directory-list (list system-root))
         (package-alist nil)
         (package-activated-list nil)
         (package-archive-contents nil)
         (package-selected-packages nil)
         (package-load-list '(all))
         (package--initialized nil)
         (load-path (copy-sequence load-path))
         (directory (expand-file-name "p3-broken-1.0" system-root))
         (autoload-file (expand-file-name "p3-broken-autoloads.el" directory)))
    (unwind-protect
        (progn
          (p3-package-test--write-package directory)
          (package-load-descriptor directory)
          (should-not (file-exists-p autoload-file))
          (p3/package--repair-incomplete-installed-packages)
          (should-not (file-exists-p autoload-file)))
      (delete-directory root t)
      (delete-directory system-root t))))


(ert-deftest p3-package-rejects-user-package-symlink-outside-package-dir ()
  (let* ((root (make-temp-file "p3-package-test-" t))
         (outside (make-temp-file "p3-package-outside-" t))
         (package-user-dir root)
         (package-directory-list nil)
         (package-alist nil)
         (package-activated-list nil)
         (package-load-list '(all))
         (directory (expand-file-name "p3-broken-1.0" root))
         (outside-directory (expand-file-name "p3-broken-1.0" outside)))
    (unwind-protect
        (progn
          (p3-package-test--write-package outside-directory)
          (condition-case err
              (progn
                (make-symbolic-link outside-directory directory 't)
                (should-not (p3/package--user-package-directory-p directory)))
            (file-error
             ;; Symlink creation may be unavailable on restricted Windows CI.
             (message "Skipping symlink test: %s" (error-message-string err)))))
      (delete-directory root t)
      (delete-directory outside t))))

(ert-deftest p3-use-package-ensure-returns-success-after-ensuring-packages ()
  (cl-letf (((symbol-function 'p3/package-install-resilient)
             (lambda (_package) 'demo)))
    (should (eq (p3/use-package-ensure 'demo '(demo) nil) t))))

(ert-deftest p3-use-package-ensure-stops-after-bootstrap-failure ()
  (cl-letf (((symbol-function 'p3/package-install-resilient)
             (lambda (_package)
               (error "simulated bootstrap failure"))))
    (let ((err (should-error
                (p3/use-package-ensure 'demo '(demo) nil)
                :type 'error)))
      (let ((message (error-message-string err)))
        (should (string-match-p
                 (regexp-quote "Package bootstrap failed for")
                 message))
        (should (string-match-p (regexp-quote "demo") message))
        (should (string-match-p
                 (regexp-quote "simulated bootstrap failure")
                 message))))))

(provide 'p3-package-test)

;;; p3-package-test.el ends here
