;;; p3-packages-test.el --- Tests for package lifecycle helpers -*- lexical-binding: t; -*-

(require 'ert)
(require 'cl-lib)
(require 'package)

(defconst p3-packages-test--root
  (file-name-directory
   (directory-file-name
    (file-name-directory (or load-file-name buffer-file-name))))
  "Root of the Emacs configuration under test.")

(let ((module (expand-file-name "lisp/p3-packages.el" p3-packages-test--root)))
  (when (file-exists-p module)
    (load module nil t)))

(defun p3-packages-test--require-function (symbol)
  "Fail clearly unless package lifecycle function SYMBOL exists."
  (should (fboundp symbol)))

(ert-deftest p3-packages-reads-use-package-targets-from-config ()
  (p3-packages-test--require-function 'p3/package-config-packages)
  (let ((config (make-temp-file "p3-packages-config-" nil ".el")))
    (unwind-protect
        (progn
          (with-temp-file config
            (insert "(use-package vertico)\n"
                    "(use-package package :ensure nil)\n"
                    "(use-package ess-r-mode :ensure ess)\n"
                    "(when t (use-package marginalia))\n"))
          (should (equal (p3/package-config-packages config)
                         '(vertico ess marginalia))))
      (delete-file config))))

(ert-deftest p3-packages-derives-minimum-versions-from-package-metadata ()
  (p3-packages-test--require-function 'p3/package-unsatisfied-requirements)
  (let ((descriptor
         (package-desc-create
          :name 'consumer
          :version '(1 0)
          :summary "test"
          :reqs '((compat (31 0)) (seq (2 0)))
          :kind 'single
          :archive "test"))
        calls)
    (cl-letf (((symbol-function 'package-installed-p)
               (lambda (package &optional minimum-version)
                 (push (list package minimum-version) calls)
                 (eq package 'seq))))
      (should (equal (p3/package-unsatisfied-requirements descriptor)
                     '((compat (31 0)))))
      (should (member '(compat (31 0)) calls))
      (should (member '(seq (2 0)) calls)))))

(ert-deftest p3-packages-selects-newest-archive-version-satisfying-requirement ()
  (p3-packages-test--require-function 'p3/package-archive-desc)
  (let* ((v30 (package-desc-create :name 'compat :version '(30 0)
                                   :summary "30" :reqs nil :kind 'single
                                   :archive "gnu"))
         (v31 (package-desc-create :name 'compat :version '(31 0)
                                   :summary "31" :reqs nil :kind 'single
                                   :archive "gnu"))
         (v32 (package-desc-create :name 'compat :version '(32 0)
                                   :summary "32" :reqs nil :kind 'single
                                   :archive "gnu"))
         (package-archive-contents `((compat ,v30 ,v32 ,v31))))
    (should (eq (p3/package-archive-desc 'compat '(31 0)) v32))
    (should-not (p3/package-archive-desc 'compat '(33 0)))))

(ert-deftest p3-packages-installs-versioned-requirement-from-archive-descriptor ()
  (p3-packages-test--require-function 'p3/package-install-resilient)
  (let* ((descriptor
          (package-desc-create :name 'compat :version '(31 0)
                               :summary "31" :reqs nil :kind 'single
                               :archive "gnu"))
         (package-archive-contents `((compat ,descriptor)))
         (p3/package-refresh-attempted nil)
         (p3/package-restart-required nil)
         installed
         upgrade-built-in-value
         marked)
    (cl-letf (((symbol-function 'package-installed-p)
               (lambda (&rest _args) nil))
              ((symbol-function 'package-install)
               (lambda (package &optional _dont-select)
                 (setq installed package
                       upgrade-built-in-value package-install-upgrade-built-in)))
              ((symbol-function 'p3/package-mark-rebuild-needed)
               (lambda () (setq marked t))))
      (p3/package-install-resilient 'compat '(31 0))
      (should (eq installed descriptor))
      (should upgrade-built-in-value)
      (should marked)
      (should p3/package-restart-required))))

(ert-deftest p3-packages-rebuild-marker-recompiles-on-fresh-startup ()
  (p3-packages-test--require-function 'p3/package-recompile-if-needed)
  (let ((p3/package-rebuild-marker (make-temp-file "p3-package-rebuild-"))
        (calls 0))
    (unwind-protect
        (cl-letf (((symbol-function 'package-recompile-all)
                   (lambda () (setq calls (1+ calls)))))
          (p3/package-recompile-if-needed)
          (should (= calls 1))
          (should-not (file-exists-p p3/package-rebuild-marker)))
      (when (file-exists-p p3/package-rebuild-marker)
        (delete-file p3/package-rebuild-marker)))))

(ert-deftest p3-packages-keeps-rebuild-marker-when-recompile-fails ()
  (p3-packages-test--require-function 'p3/package-recompile-if-needed)
  (let ((p3/package-rebuild-marker (make-temp-file "p3-package-rebuild-")))
    (unwind-protect
        (cl-letf (((symbol-function 'package-recompile-all)
                   (lambda () (error "compile failed"))))
          (should-error (p3/package-recompile-if-needed))
          (should (file-exists-p p3/package-rebuild-marker)))
      (when (file-exists-p p3/package-rebuild-marker)
        (delete-file p3/package-rebuild-marker)))))

(ert-deftest p3-packages-preflight-fails-closed-after-repair ()
  (p3-packages-test--require-function 'p3/package-preflight-config)
  (let ((p3/package-restart-required nil))
    (cl-letf (((symbol-function 'p3/package-config-packages)
               (lambda (_path) '(consumer)))
              ((symbol-function 'p3/package-install-resilient)
               (lambda (&rest _args) nil))
              ((symbol-function 'p3/package-ensure-requirements)
               (lambda (_package)
                 (setq p3/package-restart-required t))))
      (should-not (p3/package-preflight-config "ignored.el")))))

(ert-deftest p3-packages-package-menu-marks-rebuild-before-mutation ()
  (p3-packages-test--require-function
   'p3/package-menu-execute-with-rebuild-marker)
  (let (marked entered)
    (cl-letf (((symbol-function 'p3/package-mark-rebuild-needed)
               (lambda () (setq marked t))))
      (should-error
       (p3/package-menu-execute-with-rebuild-marker
        (lambda ()
          (setq entered marked)
          (error "simulated package failure"))))
      (should entered))))

(provide 'p3-packages-test)

;;; p3-packages-test.el ends here
