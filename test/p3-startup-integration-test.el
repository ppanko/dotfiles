;;; p3-startup-integration-test.el --- Startup instrumentation integration tests -*- lexical-binding: t; -*-

(require 'ert)
(require 'cl-lib)

(defconst p3-startup-integration-test--root
  (file-name-directory
   (directory-file-name
    (file-name-directory (or load-file-name buffer-file-name))))
  "Root of the Emacs configuration under test.")

(add-to-list 'load-path
             (expand-file-name "lisp" p3-startup-integration-test--root))
(require 'p3-startup-profile)
(require 'p3-config-loader)

(defun p3-startup-integration-test--file-contents (path)
  "Return repository-relative PATH as a string."
  (with-temp-buffer
    (insert-file-contents
     (expand-file-name path p3-startup-integration-test--root))
    (buffer-string)))

(ert-deftest p3-startup-integration-package-boundaries-are-instrumented ()
  (let ((contents (p3-startup-integration-test--file-contents "init.el")))
    (dolist (needle '("p3/with-startup-profile-phase \"package-initialize\""
                      "p3/with-startup-profile-phase \"use-package-bootstrap\""
                      "p3/with-startup-profile-phase \"use-package-ensure\""))
      (should (string-match-p (regexp-quote needle) contents)))))

(ert-deftest p3-startup-integration-profiler-load-preserves-load-path-order ()
  (let* ((contents (p3-startup-integration-test--file-contents "init.el"))
         (profiler-load
          (string-match
           (regexp-quote
            "(load (expand-file-name \"lisp/p3-startup-profile.el\" user-emacs-directory)\n      nil 'nomessage)")
           contents))
         (package-init
          (string-match
           (regexp-quote
            "(p3/with-startup-profile-phase \"package-initialize\"")
           contents))
         (local-load-path
          (string-match
           (regexp-quote "(defconst p3/lisp-directory")
           contents)))
    (should profiler-load)
    (should package-init)
    (should local-load-path)
    (should (< profiler-load package-init))
    (should (< package-init local-load-path))))

(ert-deftest p3-startup-integration-local-module-boundary-records ()
  (let* ((directory (make-temp-file "p3-profiled-module-" t))
         (p3/config-lisp-directory directory)
         (source (expand-file-name "p3-profiled-module.el" directory))
         (p3/startup-profile-active t)
         (p3/startup-profile-phases nil))
    (unwind-protect
        (progn
          (with-temp-file source
            (insert "(provide 'p3-profiled-module)\n"))
          (p3/config-load-module 'p3-profiled-module)
          (should (assoc-string "module:p3-profiled-module"
                                p3/startup-profile-phases)))
      (setq features (delq 'p3-profiled-module features))
      (delete-directory directory t))))

(ert-deftest p3-startup-integration-current-cache-records-validate-and-load ()
  (let ((p3/startup-profile-active t)
        (p3/startup-profile-phases nil))
    (cl-letf (((symbol-function 'p3/config-cache-stale-p) (lambda () nil))
              ((symbol-function 'p3/config-load-generated) (lambda () t)))
      (p3/config-load))
    (should (assoc-string "config-cache-validate" p3/startup-profile-phases))
    (should (assoc-string "config-cache-load" p3/startup-profile-phases))
    (should-not (assoc-string "config-cache-build" p3/startup-profile-phases))))

(ert-deftest p3-startup-integration-stale-cache-records-build ()
  (let ((p3/startup-profile-active t)
        (p3/startup-profile-phases nil))
    (cl-letf (((symbol-function 'p3/config-cache-stale-p) (lambda () t))
              ((symbol-function 'p3/config-build) (lambda () t))
              ((symbol-function 'p3/config-load-generated) (lambda () t)))
      (p3/config-load))
    (should (assoc-string "config-cache-validate" p3/startup-profile-phases))
    (should (assoc-string "config-cache-build" p3/startup-profile-phases))
    (should (assoc-string "config-cache-load" p3/startup-profile-phases))))

(provide 'p3-startup-integration-test)

;;; p3-startup-integration-test.el ends here
