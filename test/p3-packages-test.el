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

(ert-deftest p3-packages-derives-minimum-versions-from-package-metadata ()
  (p3-packages-test--require-function 'p3/package-unsatisfied-requirements)
  (let ((descriptor
         (package-desc-create
          :name 'consumer
          :version '(1 0)
          :summary "test"
          :reqs '((foundation (5 0)) (seq (2 0)))
          :kind 'single
          :archive "test"))
        calls)
    (cl-letf (((symbol-function 'package-installed-p)
               (lambda (package &optional minimum-version)
                 (push (list package minimum-version) calls)
                 (eq package 'seq))))
      (should (equal (p3/package-unsatisfied-requirements descriptor)
                     '((foundation (5 0)))))
      (should (member '(foundation (5 0)) calls))
      (should (member '(seq (2 0)) calls)))))

(ert-deftest p3-packages-archive-selection-preserves-package-priority ()
  (p3-packages-test--require-function 'p3/package-archive-desc)
  (let* ((preferred
          (package-desc-create :name 'foundation :version '(5 0)
                               :summary "preferred" :reqs nil :kind 'single
                               :archive "preferred"))
         (newer
          (package-desc-create :name 'foundation :version '(6 0)
                               :summary "newer" :reqs nil :kind 'single
                               :archive "lower-priority"))
         (too-old
          (package-desc-create :name 'foundation :version '(4 0)
                               :summary "old" :reqs nil :kind 'single
                               :archive "preferred"))
         ;; package.el orders this list by archive/package priority, not solely
         ;; by version. Select the first entry that satisfies the requirement.
         (package-archive-contents
          `((foundation ,preferred ,newer ,too-old))))
    (should (eq (p3/package-archive-desc 'foundation '(5 0)) preferred))
    (should-not (p3/package-archive-desc 'foundation '(7 0)))))

(ert-deftest p3-packages-installs-versioned-requirement-from-archive-descriptor ()
  (p3-packages-test--require-function 'p3/package-install-resilient)
  (let* ((descriptor
          (package-desc-create :name 'foundation :version '(5 0)
                               :summary "5" :reqs nil :kind 'single
                               :archive "test"))
         (package-archive-contents `((foundation ,descriptor)))
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
               (lambda ()
                 (setq marked t
                       p3/package-restart-required t))))
      (p3/package-install-resilient 'foundation '(5 0))
      (should (eq installed descriptor))
      (should upgrade-built-in-value)
      (should marked)
      (should p3/package-restart-required))))

(ert-deftest p3-packages-uses-cached-archive-metadata-before-refreshing ()
  (p3-packages-test--require-function 'p3/package-install-resilient)
  (let* ((descriptor
          (package-desc-create :name 'foundation :version '(5 0)
                               :summary "cached" :reqs nil :kind 'single
                               :archive "test"))
         (package-archive-contents nil)
         (p3/package-refresh-attempted nil)
         (p3/package-restart-required nil)
         installed)
    (cl-letf (((symbol-function 'package-installed-p)
               (lambda (&rest _args) nil))
              ((symbol-function 'package-read-all-archive-contents)
               (lambda ()
                 (setq package-archive-contents
                       `((foundation ,descriptor)))))
              ((symbol-function 'package-refresh-contents)
               (lambda () (ert-fail "Network refresh should not be needed")))
              ((symbol-function 'package-install)
               (lambda (package &optional _dont-select)
                 (setq installed package)))
              ((symbol-function 'p3/package-mark-rebuild-needed)
               (lambda () (setq p3/package-restart-required t))))
      (p3/package-install-resilient 'foundation '(5 0))
      (should (eq installed descriptor)))))

(ert-deftest p3-packages-recompiles-only-active-user-installed-packages ()
  (p3-packages-test--require-function 'p3/package-recompile-user-packages)
  (let* ((user-root (make-temp-file "p3-package-user-" t))
         (system-root (make-temp-file "p3-package-system-" t))
         (package-user-dir user-root)
         (active-dir (expand-file-name "user-package-2.0" user-root))
         (old-dir (expand-file-name "user-package-1.0" user-root))
         (system-dir (expand-file-name "system-package-1.0" system-root))
         (active-desc
          (package-desc-create :name 'user-package :version '(2 0)
                               :summary "active" :reqs nil :kind 'single
                               :archive "test" :dir active-dir))
         (old-desc
          (package-desc-create :name 'user-package :version '(1 0)
                               :summary "old" :reqs nil :kind 'single
                               :archive "test" :dir old-dir))
         (system-desc
          (package-desc-create :name 'system-package :version '(1 0)
                               :summary "system" :reqs nil :kind 'single
                               :archive nil :dir system-dir))
         (package-alist `((user-package ,active-desc ,old-desc)
                          (system-package ,system-desc)))
         recompiled)
    (unwind-protect
        (progn
          (make-directory active-dir t)
          (make-directory old-dir t)
          (make-directory system-dir t)
          (cl-letf (((symbol-function 'package-recompile)
                     (lambda (descriptor) (push descriptor recompiled))))
            (p3/package-recompile-user-packages))
          (should (equal recompiled (list active-desc))))
      (delete-directory user-root t)
      (delete-directory system-root t))))

(ert-deftest p3-packages-rebuild-marker-recompiles-on-fresh-startup ()
  (p3-packages-test--require-function 'p3/package-recompile-if-needed)
  (let ((p3/package-rebuild-marker (make-temp-file "p3-package-rebuild-"))
        (calls 0))
    (unwind-protect
        (cl-letf (((symbol-function 'p3/package-recompile-user-packages)
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
        (cl-letf (((symbol-function 'p3/package-recompile-user-packages)
                   (lambda () (error "compile failed"))))
          (should-error (p3/package-recompile-if-needed))
          (should (file-exists-p p3/package-rebuild-marker)))
      (when (file-exists-p p3/package-rebuild-marker)
        (delete-file p3/package-rebuild-marker)))))

(ert-deftest p3-packages-preflight-fails-closed-after-repair ()
  (p3-packages-test--require-function 'p3/package-preflight-installed)
  (let ((p3/package-restart-required nil)
        (package-alist '((consumer))))
    (cl-letf (((symbol-function 'p3/package-ensure-requirements)
               (lambda (_package)
                 (setq p3/package-restart-required t))))
      (should-not (p3/package-preflight-installed)))))

(ert-deftest p3-packages-bootstrap-repairs-before-recompiling ()
  (p3-packages-test--require-function 'p3/package-bootstrap-ready-p)
  (let ((p3/package-restart-required nil)
        recompiled)
    (cl-letf (((symbol-function 'p3/package-preflight-installed)
               (lambda ()
                 (setq p3/package-restart-required t)
                 nil))
              ((symbol-function 'p3/package-recompile-if-needed)
               (lambda () (setq recompiled t))))
      (should-not (p3/package-bootstrap-ready-p))
      (should-not recompiled))))

(ert-deftest p3-packages-bootstrap-recompiles-only-after-healthy-preflight ()
  (p3-packages-test--require-function 'p3/package-bootstrap-ready-p)
  (let ((p3/package-restart-required nil)
        order)
    (cl-letf (((symbol-function 'p3/package-preflight-installed)
               (lambda () (push 'preflight order) t))
              ((symbol-function 'p3/package-install-resilient)
               (lambda (&rest _args) (push 'use-package order)))
              ((symbol-function 'p3/package-recompile-if-needed)
               (lambda () (push 'recompile order))))
      (should (p3/package-bootstrap-ready-p))
      (should (equal (nreverse order)
                     '(preflight use-package recompile))))))

(ert-deftest p3-packages-bootstrap-fails-closed-on-package-error ()
  (p3-packages-test--require-function 'p3/package-bootstrap-ready-p)
  (let ((p3/package-restart-required nil)
        warning)
    (cl-letf (((symbol-function 'p3/package-preflight-installed)
               (lambda () t))
              ((symbol-function 'p3/package-install-resilient)
               (lambda (&rest _args) (error "package failure")))
              ((symbol-function 'display-warning)
               (lambda (&rest args) (setq warning args))))
      (should-not (p3/package-bootstrap-ready-p))
      (should warning))))

(ert-deftest p3-packages-bootstrap-requires-restart-after-use-package-install ()
  (p3-packages-test--require-function 'p3/package-bootstrap-ready-p)
  (let ((p3/package-restart-required nil)
        recompiled)
    (cl-letf (((symbol-function 'p3/package-preflight-installed)
               (lambda () t))
              ((symbol-function 'p3/package-install-resilient)
               (lambda (&rest _args)
                 (setq p3/package-restart-required t)))
              ((symbol-function 'p3/package-recompile-if-needed)
               (lambda () (setq recompiled t))))
      (should-not (p3/package-bootstrap-ready-p))
      (should-not recompiled))))

(ert-deftest p3-packages-use-package-ensure-aborts-declaration-after-repair ()
  (p3-packages-test--require-function 'p3/use-package-ensure)
  (let ((p3/package-restart-required nil))
    (cl-letf (((symbol-function 'use-package-as-symbol)
               (lambda (_name) 'consumer))
              ((symbol-function 'p3/package-install-resilient)
               (lambda (&rest _args)
                 (setq p3/package-restart-required t)))
              ((symbol-function 'p3/package-ensure-requirements)
               (lambda (_package) nil)))
      (should-error (p3/use-package-ensure 'consumer '(t) nil)
                    :type 'p3/package-restart-needed))))

(ert-deftest p3-packages-use-package-ensure-propagates-install-failure ()
  (p3-packages-test--require-function 'p3/use-package-ensure)
  (let ((p3/package-restart-required nil))
    (cl-letf (((symbol-function 'use-package-as-symbol)
               (lambda (_name) 'consumer))
              ((symbol-function 'p3/package-install-resilient)
               (lambda (&rest _args) (error "install failed"))))
      (should-error (p3/use-package-ensure 'consumer '(t) nil)))))

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
