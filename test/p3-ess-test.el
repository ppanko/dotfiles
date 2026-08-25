;;; p3-ess-test.el --- Tests for p3-ess -*- lexical-binding: t; -*-

(require 'ert)
(require 'cl-lib)

(defconst p3-ess-test--root
  (file-name-directory
   (directory-file-name
    (file-name-directory (or load-file-name buffer-file-name))))
  "Root of the Emacs configuration under test.")

(add-to-list 'load-path (expand-file-name "lisp" p3-ess-test--root))

(require 'p3-core)
(require 'p3-ess)

(ert-deftest p3-ess-project-root-uses-shared-project-root ()
  (with-temp-buffer
    (let ((default-directory "/tmp/fallback/")
          (p3/ess-project-root-cache nil))
      (cl-letf (((symbol-function 'p3/project-root)
                 (lambda () "/tmp/shared-project/")))
        (should (equal (p3/ess-project-root) "/tmp/shared-project/"))))))

(ert-deftest p3-ess-project-root-falls-back-to-default-directory ()
  (with-temp-buffer
    (let ((default-directory "/tmp/fallback/")
          (p3/ess-project-root-cache nil))
      (cl-letf (((symbol-function 'p3/project-root) (lambda () nil)))
        (should (equal (p3/ess-project-root) "/tmp/fallback/"))))))

(ert-deftest p3-ess-project-process-discards-stale-registration ()
  (with-temp-buffer
    (let ((p3/ess-project-root-cache "/tmp/project/")
          (p3/ess-project-processes (make-hash-table :test #'equal)))
      (puthash "/tmp/project/" "R:stale" p3/ess-project-processes)
      (cl-letf (((symbol-function 'p3/ess-process-live-p)
                 (lambda (_name) nil)))
        (should-not (p3/ess-project-process))
        (should-not (gethash "/tmp/project/" p3/ess-project-processes))))))

(ert-deftest p3-ess-register-current-process-uses-canonical-project-root ()
  (with-temp-buffer
    (let ((p3/ess-project-processes (make-hash-table :test #'equal)))
      (setq-local ess-local-process-name "R:project")
      (cl-letf (((symbol-function 'derived-mode-p)
                 (lambda (&rest _modes) t))
                ((symbol-function 'p3/ess-project-root)
                 (lambda () "/tmp/project/")))
        (p3/ess-register-current-process)
        (should (equal (gethash "/tmp/project/" p3/ess-project-processes)
                       "R:project"))))))

(ert-deftest p3-ess-ensure-project-process-reuses-live-process ()
  (with-temp-buffer
    (let ((started nil))
      (setq-local ess-local-process-name nil)
      (cl-letf (((symbol-function 'p3/ess-project-process)
                 (lambda () "R:project"))
                ((symbol-function 'R)
                 (lambda () (interactive) (setq started t))))
        (p3/ess-ensure-project-process)
        (should (equal (buffer-local-value
                        'ess-local-process-name (current-buffer))
                       "R:project"))
        (should-not started)))))

(ert-deftest p3-ess-ensure-project-process-starts-R-lazily ()
  (with-temp-buffer
    (let ((lookup-count 0)
          (started nil))
      (setq-local ess-local-process-name nil)
      (cl-letf (((symbol-function 'p3/ess-project-process)
                 (lambda ()
                   (setq lookup-count (1+ lookup-count))
                   (and (> lookup-count 1) "R:new")))
                ((symbol-function 'R)
                 (lambda () (interactive) (setq started t))))
        (p3/ess-ensure-project-process)
        (should started)
        (should (equal (buffer-local-value
                        'ess-local-process-name (current-buffer))
                       "R:new"))))))

(ert-deftest p3-ess-install-advice-is-idempotent ()
  (let ((symbol 'p3-ess-test--force-current))
    (fset symbol (lambda (&rest _args) nil))
    (unwind-protect
        (cl-letf (((symbol-function 'p3/ess-force-buffer-current-symbol)
                   (lambda () symbol)))
          (p3/ess-install-process-advice)
          (p3/ess-install-process-advice)
          (should (advice-member-p #'p3/ess-ensure-project-process symbol)))
      (advice-remove symbol #'p3/ess-ensure-project-process)
      (fmakunbound symbol))))

(provide 'p3-ess-test)

;;; p3-ess-test.el ends here
