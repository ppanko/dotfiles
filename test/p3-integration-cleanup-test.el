;;; p3-integration-cleanup-test.el --- Cross-module integration cleanup tests -*- lexical-binding: t; -*-

(require 'ert)
(require 'cl-lib)
(require 'seq)
(require 'subr-x)

(defconst p3-integration-cleanup-test--root
  (file-name-directory
   (directory-file-name
    (file-name-directory (or load-file-name buffer-file-name))))
  "Root of the Emacs configuration under test.")

(add-to-list 'load-path (expand-file-name "lisp" p3-integration-cleanup-test--root))

(require 'p3-project)
(require 'p3-platform)
(require 'p3-ess)
(require 'p3-gptel)
(require 'p3-python)
(require 'p3-r-language-server)

(defun p3-integration-cleanup-test--contents (relative)
  "Return repository file RELATIVE as a string."
  (with-temp-buffer
    (insert-file-contents
     (expand-file-name relative p3-integration-cleanup-test--root))
    (buffer-string)))

(defun p3-integration-cleanup-test--forms (relative)
  "Read all top-level Lisp forms from repository file RELATIVE."
  (with-temp-buffer
    (insert-file-contents
     (expand-file-name relative p3-integration-cleanup-test--root))
    (goto-char (point-min))
    (let (forms)
      (condition-case nil
          (while t
            (push (read (current-buffer)) forms))
        (end-of-file nil))
      (nreverse forms))))

(defun p3-integration-cleanup-test--find-call (form head)
  "Return the first nested call in FORM whose car is HEAD."
  (cond
   ((and (consp form) (eq (car form) head)) form)
   ((consp form)
    (seq-some
     (lambda (child)
       (p3-integration-cleanup-test--find-call child head))
     form))))

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

(ert-deftest p3-integration-rmarkdown-compile-is-mode-independent ()
  (let ((forms
         (p3-integration-cleanup-test--forms "lisp/p3-config-ess.el")))
    (should
     (member
      '(add-hook 'find-file-hook #'p3/ess-configure-rmarkdown-compile)
      forms))))

(ert-deftest p3-integration-rmarkdown-compile-uses-shared-r-and-posix-quoting ()
  (with-temp-buffer
    (let ((system-type 'windows-nt))
      (setq buffer-file-name "/tmp/report $draft.Rmd")
      (cl-letf (((symbol-function 'p3/r-program)
                 (lambda () "/opt/R tools/$stable/bin/R")))
        (p3/ess-configure-rmarkdown-compile))
      (should (local-variable-p 'compile-command))
      (should
       (string-match-p
        (regexp-quote
         (shell-quote-argument "/opt/R tools/$stable/bin/R" t))
        compile-command))
      (should (string-match-p "--args" compile-command))
      (should
       (string-match-p
        (regexp-quote
         (shell-quote-argument "/tmp/report $draft.Rmd" t))
        compile-command))))
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

(ert-deftest p3-integration-python-signaled-bootstrap-failure-is-latched ()
  (let* ((tools (make-temp-file "p3-python-bootstrap-error-" t))
         (p3/python-language-server-bootstrap-failed nil)
         (calls 0)
         warnings)
    (unwind-protect
        (cl-letf (((symbol-function 'executable-find)
                   (lambda (_program) "/usr/bin/python3"))
                  ((symbol-function 'p3/python-tools-path)
                   (lambda (file) (expand-file-name file tools)))
                  ((symbol-function 'call-process)
                   (lambda (&rest _args)
                     (setq calls (1+ calls))
                     (error "permission denied")))
                  ((symbol-function 'display-warning)
                   (lambda (_type message &optional _level _buffer-name)
                     (push message warnings))))
          (should-not (p3/python-ensure-language-server))
          (should-not (p3/python-ensure-language-server))
          (should (= calls 1))
          (should (= (length warnings) 1))
          (should (string-match-p "permission denied" (car warnings))))
      (delete-directory tools t))))

(ert-deftest p3-integration-python-file-visit-never-bootstraps-language-server ()
  (let* ((tools (make-temp-file "p3-python-file-visit-" t))
         (user-emacs-directory (file-name-as-directory tools))
         (system-type 'gnu/linux)
         (process-called nil))
    (unwind-protect
        (cl-letf (((symbol-function 'executable-find)
                   (lambda (_program) "/usr/bin/python3"))
                  ((symbol-function 'call-process)
                   (lambda (&rest _args)
                     (setq process-called t)
                     1))
                  ((symbol-function 'display-warning)
                   (lambda (&rest _args) nil)))
          (p3/python-eglot-ensure)
          (should-not process-called))
      (delete-directory tools t))))

(ert-deftest p3-integration-r-file-visit-never-runs-heavy-language-server-validation ()
  (let ((p3/r-language-server-ready nil)
        (p3/r-language-server-bootstrap-failed nil)
        (p3/r-language-server-warning-key nil)
        (heavy-probes 0))
    (cl-letf (((symbol-function 'p3/r-program)
               (lambda () "/opt/R/bin/R"))
              ((symbol-function 'p3/r-version)
               (lambda (&optional _program)
                 (setq heavy-probes (1+ heavy-probes))
                 "4.5.1"))
              ((symbol-function 'p3/r-language-server-library)
               (lambda (_version) "/tmp/p3-r-tools/library/"))
              ((symbol-function 'p3/r-language-server-installed-p)
               (lambda (&rest _args)
                 (setq heavy-probes (1+ heavy-probes))
                 t))
              ((symbol-function 'display-warning)
               (lambda (&rest _args) nil)))
      (p3/r-language-server-command)
      (should (= heavy-probes 0)))))

(ert-deftest p3-integration-windows-tool-discovery-is-session-cached ()
  (let ((system-type 'windows-nt)
        (p3/windows-rtools-override nil)
        (p3/windows-r-program-override nil)
        (p3/windows-rtools-selection-cache :uninitialized)
        (p3/windows-r-program-selection-cache :uninitialized)
        (rtools-scans 0)
        (r-scans 0))
    (cl-letf (((symbol-function 'p3/windows-latest-rtools)
               (lambda ()
                 (setq rtools-scans (1+ rtools-scans))
                 "C:/rtools46"))
              ((symbol-function 'p3/windows-latest-r-program)
               (lambda ()
                 (setq r-scans (1+ r-scans))
                 "C:/Program Files/R/R-4.6.1/bin/Rterm.exe")))
      (should (equal (p3/windows-select-rtools) "C:/rtools46"))
      (should (equal (p3/windows-select-rtools) "C:/rtools46"))
      (should
       (equal (p3/windows-select-r-program)
              "C:/Program Files/R/R-4.6.1/bin/Rterm.exe"))
      (should
       (equal (p3/windows-select-r-program)
              "C:/Program Files/R/R-4.6.1/bin/Rterm.exe"))
      (should (= rtools-scans 1))
      (should (= r-scans 1)))))

(ert-deftest p3-integration-windows-r-override-invalidates-selection-cache ()
  (let ((system-type 'windows-nt)
        (p3/windows-r-program-override nil)
        (p3/windows-r-program-selection-cache :uninitialized)
        (discoveries 0))
    (cl-letf (((symbol-function 'p3/windows-latest-r-program)
               (lambda ()
                 (setq discoveries (1+ discoveries))
                 "C:/Program Files/R/R-4.6.1/bin/Rterm.exe"))
              ((symbol-function 'file-regular-p)
               (lambda (_path) t)))
      (should
       (equal (p3/windows-select-r-program)
              "C:/Program Files/R/R-4.6.1/bin/Rterm.exe"))
      (setq p3/windows-r-program-override "D:/R/bin/Rterm.exe")
      (should
       (equal (p3/windows-select-r-program) "D:/R/bin/Rterm.exe"))
      (should (= discoveries 1)))))

(ert-deftest p3-integration-routed-file-visit-reuses-resolved-project-root ()
  (should (fboundp 'p3/project-with-file-routing))
  (let ((root "/tmp/p3-project/")
        (project-current-calls 0))
    (cl-letf (((symbol-function 'project-current)
               (lambda (&optional _maybe-prompt _directory)
                 (setq project-current-calls (1+ project-current-calls))
                 'fake-project))
              ((symbol-function 'project-root)
               (lambda (_project) root))
              ((symbol-function 'p3/project-switch-to-tab)
               (lambda (selected-root) selected-root)))
      (p3/project-with-file-routing
       (lambda (&rest _args)
         (should (equal (p3/project-root) root))
         (should (equal (p3/project-root) root)))
       "/tmp/p3-project/file.R")
      (should (= project-current-calls 1)))))

(ert-deftest p3-integration-appearance-uses-shared-project-root ()
  (let ((appearance
         (p3-integration-cleanup-test--contents "lisp/p3-config-appearance.el")))
    (should (string-match-p (regexp-quote "(p3/project-root)") appearance))
    (should-not (string-match-p "(project-current" appearance))))

(ert-deftest p3-integration-gptel-which-key-matches-current-command-surface ()
  (let* ((forms
          (p3-integration-cleanup-test--forms "lisp/p3-config-gptel.el"))
         (call
          (seq-some
           (lambda (form)
             (p3-integration-cleanup-test--find-call
              form 'which-key-add-key-based-replacements))
           forms))
         (args (cdr call))
         advertised
         live)
    (should call)
    (while args
      (push (car args) advertised)
      (setq args (cddr args)))
    (map-keymap
     (lambda (event binding)
       (when binding
         (push (concat "C-c g " (single-key-description event)) live)))
     p3/gptel-command-map)
    (should
     (equal (sort advertised #'string<)
            (sort live #'string<)))))

(ert-deftest p3-integration-office-preview-is-lazy ()
  (let* ((forms
          (p3-integration-cleanup-test--forms "lisp/p3-config-org.el"))
         (form
          (seq-find
           (lambda (candidate)
             (and (consp candidate)
                  (eq (car candidate) 'use-package)
                  (eq (cadr candidate) 'p3-office-preview)))
           forms))
         (args (cddr form)))
    (should form)
    (should
     (equal
      (plist-get args :commands)
      '(p3/office-preview-pptx p3/org-export-pptx-preview)))
    (should-not (plist-member args :demand))))

(provide 'p3-integration-cleanup-test)

;;; p3-integration-cleanup-test.el ends here
