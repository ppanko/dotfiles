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

(ert-deftest p3-ess-project-aware-R-reuses-live-project-process ()
  (with-temp-buffer
    (let ((default-directory "/tmp/")
          (p3/ess-project-processes (make-hash-table :test #'equal))
          seen-process
          seen-directory)
      (puthash "/tmp/project/" "R:project" p3/ess-project-processes)
      (cl-letf (((symbol-function 'p3/project-root)
                 (lambda () "/tmp/project/"))
                ((symbol-function 'p3/ess-process-live-p)
                 (lambda (name) (equal name "R:project"))))
        (should
         (eq (p3/ess-project-aware-R
              (lambda (&optional _start-args)
                (setq seen-process ess-local-process-name
                      seen-directory default-directory)
                'reused))
             'reused))
        (should (equal seen-process "R:project"))
        (should (equal seen-directory "/tmp/project/"))))))

(ert-deftest p3-ess-project-aware-R-starts-new-process-at-project-root ()
  (with-temp-buffer
    (let ((default-directory "/tmp/")
          (p3/ess-project-processes (make-hash-table :test #'equal))
          seen-process
          seen-directory
          seen-args)
      (cl-letf (((symbol-function 'p3/project-root)
                 (lambda () "/tmp/project/")))
        (p3/ess-project-aware-R
         (lambda (&optional start-args)
           (setq seen-process ess-local-process-name
                 seen-directory default-directory
                 seen-args start-args))
         '(4))
        (should-not seen-process)
        (should (equal seen-directory "/tmp/project/"))
        (should (equal seen-args '(4)))))))

(ert-deftest p3-ess-source-context-caches-project-root-before-redisplay ()
  (should (fboundp 'p3/ess-cache-project-root))
  (with-temp-buffer
    (setq-local p3/ess-project-root-cache nil)
    (cl-letf (((symbol-function 'p3/project-root)
               (lambda () "/tmp/project/")))
      (p3/ess-cache-project-root)
      (should (equal p3/ess-project-root-cache "/tmp/project/")))))

(ert-deftest p3-ess-busy-state-uses-cached-project-registration-without-discovery ()
  (should (fboundp 'p3/ess-current-process-busy-p))
  (with-temp-buffer
    (let ((p3/ess-project-root-cache "/tmp/project/")
          (p3/ess-project-processes (make-hash-table :test #'equal)))
      (setq-local ess-local-process-name nil)
      (puthash "/tmp/project/" "R:project" p3/ess-project-processes)
      (cl-letf (((symbol-function 'p3/project-root)
                 (lambda () (ert-fail "project discovery during busy lookup")))
                ((symbol-function 'get-process)
                 (lambda (name) (and (equal name "R:project") 'fake-r-process)))
                ((symbol-function 'process-live-p)
                 (lambda (process) (eq process 'fake-r-process)))
                ((symbol-function 'process-get)
                 (lambda (process property)
                   (and (eq process 'fake-r-process)
                        (eq property 'busy)))))
        (should (p3/ess-current-process-busy-p))))))

(ert-deftest p3-ess-setup-caches-source-project-context ()
  (should (fboundp 'p3/ess-cache-project-root))
  (let ((features (cons 'ess-inf features))
        hooks)
    (cl-letf (((symbol-function 'add-hook)
               (lambda (hook function &rest _)
                 (push (cons hook function) hooks)))
              ((symbol-function 'p3/ess-install-process-advice)
               (lambda () nil)))
      (p3/ess-setup)
      (should (member '(ess-mode-hook . p3/ess-cache-project-root) hooks))
      (should (member '(inferior-ess-mode-hook . p3/ess-register-current-process)
                      hooks)))))

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

(ert-deftest p3-ess-install-R-advice-is-idempotent ()
  (let ((symbol 'p3-ess-test--R))
    (fset symbol (lambda (&optional _start-args) nil))
    (unwind-protect
        (cl-letf (((symbol-function 'p3/ess-R-command-symbol)
                   (lambda () symbol)))
          (p3/ess-install-R-advice)
          (p3/ess-install-R-advice)
          (should (advice-member-p #'p3/ess-project-aware-R symbol)))
      (advice-remove symbol #'p3/ess-project-aware-R)
      (fmakunbound symbol))))

(provide 'p3-ess-test)

;;; p3-ess-test.el ends here
