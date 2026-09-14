;;; p3-integration-cleanup-test.el --- Cross-module integration cleanup tests -*- lexical-binding: t; -*-

(require 'ert)
(require 'cl-lib)
(require 'subr-x)

(defconst p3-integration-cleanup-test--root
  (file-name-directory
   (directory-file-name
    (file-name-directory (or load-file-name buffer-file-name))))
  "Root of the Emacs configuration under test.")

(add-to-list 'load-path (expand-file-name "lisp" p3-integration-cleanup-test--root))

(require 'p3-project)
(require 'p3-ess)
(require 'p3-gptel)
(require 'p3-python)

(defun p3-integration-cleanup-test--contents (relative)
  "Return repository file RELATIVE as a string."
  (with-temp-buffer
    (insert-file-contents
     (expand-file-name relative p3-integration-cleanup-test--root))
    (buffer-string)))

(ert-deftest p3-integration-ess-canonicalizes-local-project-identity ()
  (skip-unless (not (eq system-type 'windows-nt)))
  (let* ((parent (make-temp-file "p3-ess-canonical-" t))
         (real (expand-file-name "real" parent))
         (alias (expand-file-name "alias" parent)))
    (unwind-protect
        (progn
          (make-directory real)
          (make-symbolic-link real alias)
          (with-temp-buffer
            (let ((p3/ess-project-root-cache nil))
              (cl-letf (((symbol-function 'p3/project-root)
                         (lambda () (file-name-as-directory alias))))
                (should
                 (equal (p3/ess-project-root)
                        (p3/project-normalize-root real)))))))
      (delete-directory parent t))))

(ert-deftest p3-integration-gptel-canonicalizes-local-project-identity ()
  (skip-unless (not (eq system-type 'windows-nt)))
  (let* ((parent (make-temp-file "p3-gptel-canonical-" t))
         (real (expand-file-name "real" parent))
         (alias (expand-file-name "alias" parent))
         (chat (generate-new-buffer " *p3-gptel-canonical-chat*")))
    (unwind-protect
        (progn
          (make-directory real)
          (make-symbolic-link real alias)
          (cl-letf (((symbol-function 'project-current)
                     (lambda (&optional _maybe-prompt) 'project))
                    ((symbol-function 'project-root)
                     (lambda (_project) (file-name-as-directory alias)))
                    ((symbol-function 'gptel)
                     (lambda () (interactive) chat)))
            (should (eq (p3/gptel-project-chat) chat)))
          (with-current-buffer chat
            (should
             (equal p3/gptel-project-root
                    (p3/project-normalize-root real)))
            (should
             (equal default-directory
                    (p3/project-normalize-root real)))))
      (when (buffer-live-p chat)
        (kill-buffer chat))
      (delete-directory parent t))))

(ert-deftest p3-integration-rmarkdown-compile-uses-shared-r-and-only-rmd ()
  (with-temp-buffer
    (setq buffer-file-name "/tmp/report with spaces.Rmd")
    (cl-letf (((symbol-function 'p3/r-program)
               (lambda () "/opt/R tools/bin/R")))
      (p3/ess-configure-rmarkdown-compile))
    (should (local-variable-p 'compile-command))
    (should
     (string-match-p
      (regexp-quote (shell-quote-argument "/opt/R tools/bin/R"))
      compile-command))
    (should (string-match-p "--args" compile-command))
    (should
     (string-match-p
      (regexp-quote (shell-quote-argument "/tmp/report with spaces.Rmd"))
      compile-command)))
  (with-temp-buffer
    (setq buffer-file-name "/tmp/report.md")
    (setq-local compile-command "make -k")
    (cl-letf (((symbol-function 'p3/r-program)
               (lambda () "/opt/R tools/bin/R")))
      (p3/ess-configure-rmarkdown-compile))
    (should (equal compile-command "make -k"))))

(ert-deftest p3-integration-python-bootstrap-failure-is-latched ()
  (let* ((tools (make-temp-file "p3-python-bootstrap-" t))
         (p3/python-language-server-bootstrap-failed nil)
         (calls 0))
    (unwind-protect
        (cl-letf (((symbol-function 'executable-find)
                   (lambda (_program) "/usr/bin/python3"))
                  ((symbol-function 'p3/python-tools-path)
                   (lambda (file) (expand-file-name file tools)))
                  ((symbol-function 'call-process)
                   (lambda (&rest _args)
                     (setq calls (1+ calls))
                     1))
                  ((symbol-function 'display-warning)
                   (lambda (&rest _args) nil)))
          (should-not (p3/python-ensure-language-server))
          (should-not (p3/python-ensure-language-server))
          (should (= calls 1)))
      (delete-directory tools t))))

(ert-deftest p3-integration-gptel-which-key-matches-current-command-surface ()
  (let ((base (p3-integration-cleanup-test--contents "lisp/p3-config-base.el"))
        (gptel (p3-integration-cleanup-test--contents "lisp/p3-config-gptel.el")))
    (dolist (obsolete '("C-c g l" "C-c g c" "C-c g w"))
      (should-not (string-match-p (regexp-quote obsolete) base)))
    (dolist (current '("C-c g g" "C-c g m" "C-c g a" "C-c g f"
                       "C-c g D" "C-c g r" "C-c g d" "C-c g t"
                       "C-c g e" "C-c g v"))
      (should (string-match-p (regexp-quote current) gptel)))))

(ert-deftest p3-integration-office-preview-is-lazy ()
  (let ((org-config
         (p3-integration-cleanup-test--contents "lisp/p3-config-org.el")))
    (should
     (string-match-p
      "(use-package p3-office-preview\\(?:.\\|\n\\)*:commands"
      org-config))
    (should-not
     (string-match-p
      "(use-package p3-office-preview\\(?:.\\|\n\\)*:demand[[:space:]]+t"
      org-config))))

(ert-deftest p3-integration-completed-design-specs-are-retired ()
  (dolist (relative
           '("docs/superpowers/specs/2026-09-08-project-session-continuity-design.md"
             "docs/superpowers/specs/2026-09-14-project-aware-org-roam-design.md"))
    (should-not
     (file-exists-p
      (expand-file-name relative p3-integration-cleanup-test--root)))))

(provide 'p3-integration-cleanup-test)

;;; p3-integration-cleanup-test.el ends here
