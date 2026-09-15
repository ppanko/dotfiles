;;; p3-config-ess-test.el --- ESS configuration boundary tests -*- lexical-binding: t; -*-

(require 'ert)
(require 'cl-lib)
(require 'seq)

(defconst p3-config-ess-test--root
  (file-name-directory
   (directory-file-name
    (file-name-directory (or load-file-name buffer-file-name))))
  "Root of the Emacs configuration under test.")

(add-to-list 'load-path (expand-file-name "lisp" p3-config-ess-test--root))
(require 'p3-platform)
(require 'p3-r-language-server)

(defun p3-config-ess-test--path (relative)
  "Return RELATIVE under the repository root."
  (expand-file-name relative p3-config-ess-test--root))

(defun p3-config-ess-test--contents (relative)
  "Return contents of RELATIVE under the repository root."
  (with-temp-buffer
    (insert-file-contents (p3-config-ess-test--path relative))
    (buffer-string)))

(defun p3-config-ess-test--forms (relative)
  "Read all top-level Lisp forms from RELATIVE."
  (with-temp-buffer
    (insert-file-contents (p3-config-ess-test--path relative))
    (goto-char (point-min))
    (let (forms)
      (condition-case nil
          (while t
            (push (read (current-buffer)) forms))
        (end-of-file nil))
      (nreverse forms))))

(defun p3-config-ess-test--find-top-level (relative predicate)
  "Return first top-level form in RELATIVE matching PREDICATE."
  (seq-find predicate (p3-config-ess-test--forms relative)))

(defun p3-config-ess-test--use-package-form ()
  "Return the `use-package ess-r-mode' form under test."
  (p3-config-ess-test--find-top-level
   "lisp/p3-config-ess.el"
   (lambda (form)
     (and (consp form)
          (eq (car form) 'use-package)
          (eq (cadr form) 'ess-r-mode)))))

(defun p3-config-ess-test--defvar-form (symbol)
  "Return top-level defvar for SYMBOL in the ESS config module."
  (p3-config-ess-test--find-top-level
   "lisp/p3-config-ess.el"
   (lambda (form)
     (and (consp form)
          (eq (car form) 'defvar)
          (eq (cadr form) symbol)))))

(defun p3-config-ess-test--defun-form (symbol)
  "Return top-level defun for SYMBOL in the ESS config module."
  (p3-config-ess-test--find-top-level
   "lisp/p3-config-ess.el"
   (lambda (form)
     (and (consp form)
          (eq (car form) 'defun)
          (eq (cadr form) symbol)))))

(defun p3-config-ess-test--setq-pairs ()
  "Return variable/value pairs from the ESS package `setq' form."
  (let* ((form (p3-config-ess-test--use-package-form))
         (setq-form (plist-get (cddr form) :config)))
    (should (eq (car-safe setq-form) 'setq))
    (seq-partition (cdr setq-form) 2)))

(ert-deftest p3-config-ess-load-order-is-explicit ()
  (let* ((forms (p3-config-ess-test--forms "lisp/p3-config-ess.el"))
         (loader-position
          (seq-position forms '(require 'p3-config-loader) #'equal))
         (ess-position
          (seq-position forms '(p3/config-load-module 'p3-ess) #'equal))
         (setup-position
          (seq-position forms '(p3/ess-setup) #'equal))
         (r-tools-position
          (seq-position forms '(p3/config-load-module 'p3-r-tools) #'equal))
         (binding-position
          (seq-position forms
                        '(keymap-global-set "C-c R" p3-r-command-map)
                        #'equal)))
    (dolist (position
             (list loader-position ess-position setup-position
                   r-tools-position binding-position))
      (should (integerp position)))
    (should (< loader-position ess-position setup-position
               r-tools-position binding-position))))

(ert-deftest p3-config-ess-preserves-company-backends-exactly ()
  (should
   (equal
    (nth 2 (p3-config-ess-test--defvar-form 'p3/r-company-backends))
    '(quote
      ((:separate
        company-R-library company-R-args company-R-objects
        company-dabbrev-code
        :with company-yasnippet)
       company-capf)))))

(ert-deftest p3-config-ess-preserves-company-buffer-hook ()
  (should
   (equal
    (cddddr (p3-config-ess-test--defun-form 'p3/ess-company-config))
    '((setq-local company-backends p3/r-company-backends)))))

(ert-deftest p3-config-ess-preserves-inferior-buffer-setup ()
  (should
   (equal
    (cddddr (p3-config-ess-test--defun-form 'p3/ess-inferior-mode-setup))
    '((setq-local ansi-color-for-comint-mode 'filter)
      (smartparens-mode 1)))))

(ert-deftest p3-config-ess-preserves-hooks-and-bindings ()
  (let* ((form (p3-config-ess-test--use-package-form))
         (args (cddr form)))
    (should form)
    (should
     (equal
      (plist-get args :hook)
      '((inferior-ess-mode . p3/ess-inferior-mode-setup)
        (ess-r-post-run . p3-r-load-view-data-frame)
        (ess-r-mode . p3/ess-company-config)
        (ess-r-mode . p3/use-project-root-as-default-dir)
        (ess-mode . (lambda () (modify-syntax-entry ?_ "w"))))))
    (should
     (equal
      (plist-get args :bind)
      '(:map ess-mode-map
        ("C-<return>" . nil)
        ("S-<return>" . ess-eval-region-or-line-visibly-and-step)
        ("C-." . p3-r-insert-pipe)
        ("C-c i" . p3-r-evaluate-library-section)
        ("C-c v" . p3-r-view-data-frame-at-point)
        ("C-c m" . p3-r-targets-make)
        ("C-c d" . p3-r-targets-make-debug)
        ("C-c l" . p3-r-targets-load-at-point)
        :map inferior-ess-r-mode-map
        ("C-c v" . p3-r-view-data-frame-at-point)
        ("C-c m" . p3-r-targets-make)
        ("C-c d" . p3-r-targets-make-debug)
        ("C-c l" . p3-r-targets-load-at-point))))))

(ert-deftest p3-config-ess-preserves-sensitive-settings ()
  (let ((pairs (p3-config-ess-test--setq-pairs)))
    (dolist (pair
             '((ess-ask-for-ess-directory nil)
               (ess-style 'RStudio)
               (ess-eval-visibly t)
               (ess-toggle-underscore nil)
               (ess-use-flymake nil)
               (ess--command-default-timeout 1)
               (inferior-R-args "--no-save")
               (ess-gen-proc-buffer-name-function
                'ess-gen-proc-buffer-name:project-or-directory)))
      (should (member pair pairs)))
    (should
     (member
      '(flycheck-lintr-linters
        "linters_with_defaults(object_name_linter(c('snake_case','camelCase')), commented_code_linter = NULL, line_length_linter(90), single_quotes_linter=NULL)")
      pairs))
    (should
     (member
      '(ess-R-font-lock-keywords
        '((ess-R-fl-keyword:modifiers . t)
          (ess-R-fl-keyword:fun-defs . t)
          (ess-R-fl-keyword:keywords . t)
          (ess-R-fl-keyword:assign-ops)
          (ess-R-fl-keyword:constants . t)
          (ess-fl-keyword:fun-calls . t)
          (ess-fl-keyword:numbers . t)
          (ess-fl-keyword:operators . t)
          (ess-fl-keyword:delimiters . t)
          (ess-fl-keyword:= . t)
          (ess-R-fl-keyword:F&T . t)
          (ess-R-fl-keyword:%op% . t)))
      pairs))))

(ert-deftest p3-config-ess-delegates-rmarkdown-compile-behavior ()
  (let ((forms (p3-config-ess-test--forms "lisp/p3-config-ess.el")))
    (should-not (p3-config-ess-test--defun-form 'compile-rmd))
    (should-not (member '(add-hook 'ess-mode-hook 'compile-rmd) forms))
    (should
     (member
      '(add-hook 'markdown-mode-hook #'p3/ess-configure-rmarkdown-compile)
      forms))))

(ert-deftest p3-r-language-server-api-is-explicit ()
  (dolist (function '(p3/r-program
                      p3/r-language-server-library
                      p3/r-ensure-language-server
                      p3/r-language-server-ready-state
                      p3/r-bootstrap-language-server
                      p3/r-language-server-command
                      p3/r-eglot-ensure))
    (should (fboundp function))))

(ert-deftest p3-r-program-uses-one-platform-authority ()
  (let ((system-type 'windows-nt))
    (cl-letf (((symbol-function 'p3/windows-select-r-program)
               (lambda () "C:/Program Files/R/R-4.5.1/bin/Rterm.exe"))
              ((symbol-function 'executable-find)
               (lambda (&rest _)
                 (ert-fail "Windows R authority must not fall back to PATH"))))
      (should
       (equal (p3/r-program)
              "C:/Program Files/R/R-4.5.1/bin/Rterm.exe"))))
  (let ((system-type 'gnu/linux)
        (was-bound (boundp 'inferior-R-program-name))
        (original (and (boundp 'inferior-R-program-name)
                       (symbol-value 'inferior-R-program-name))))
    (unwind-protect
        (progn
          (set 'inferior-R-program-name "R-custom")
          (cl-letf (((symbol-function 'executable-find)
                     (lambda (program)
                       (and (equal program "R-custom") "/opt/R/bin/R"))))
            (should (equal (p3/r-program) "/opt/R/bin/R"))))
      (if was-bound
          (set 'inferior-R-program-name original)
        (makunbound 'inferior-R-program-name)))))

(ert-deftest p3-r-language-server-library-is-versioned-and-platform-local ()
  (let ((user-emacs-directory "/tmp/p3 emacs/")
        (system-type 'gnu/linux))
    (should
     (equal (p3/r-language-server-library "4.5.2")
            "/tmp/p3 emacs/r-tools/linux/R-4.5/library/")))
  (let ((user-emacs-directory "C:/Users/Pavel/.emacs.d/")
        (system-type 'windows-nt))
    (should
     (equal (p3/r-language-server-library "4.6.0")
            "c:/Users/Pavel/.emacs.d/r-tools/windows/R-4.6/library/"))))

(ert-deftest p3-r-language-server-process-status-is-defensive ()
  (cl-letf (((symbol-function 'call-process)
             (lambda (&rest _) "killed")))
    (should-not (p3/r-version "/opt/R/bin/R"))
    (should-not
     (p3/r-language-server-installed-p
      "/opt/R/bin/R" "/tmp/p3-r-tools/library/"))))

(ert-deftest p3-r-language-server-installed-check-is-managed-only ()
  (let (expression)
    (cl-letf (((symbol-function 'call-process)
               (lambda (_program _input _destination _display &rest args)
                 (setq expression (car (last args)))
                 ;; Model languageserver being available only from a global
                 ;; library: an unconstrained lookup would succeed, while a
                 ;; managed-library lookup must fail.
                 (if (string-match-p "lib.loc=" expression) 1 0))))
      (should-not
       (p3/r-language-server-installed-p
        "/opt/R/bin/R" "/tmp/p3-r-tools/library/"))
      (should (string-match-p "loadNamespace" expression))
      (should (string-match-p "lib.loc=" expression)))))

(ert-deftest p3-r-language-server-reuses-existing-managed-package ()
  (let ((p3/r-language-server-bootstrap-failed nil)
        (p3/r-language-server-ready nil))
    (cl-letf (((symbol-function 'p3/r-program) (lambda () "/opt/R/bin/R"))
              ((symbol-function 'p3/r-version) (lambda (&optional _program) "4.5.1"))
              ((symbol-function 'p3/r-language-server-library)
               (lambda (_version) "/tmp/p3-r-tools/library/"))
              ((symbol-function 'p3/r-language-server-installed-p)
               (lambda (_program _library) t))
              ((symbol-function 'p3/r-language-server-write-state)
               (lambda (&rest _)
                 (ert-fail "Validation helper must not persist readiness")))
              ((symbol-function 'p3/r-install-language-server)
               (lambda (&rest _)
                 (ert-fail "Installed language server should be reused"))))
      (should
       (equal (p3/r-ensure-language-server)
              "/tmp/p3-r-tools/library/")))))

(ert-deftest p3-r-language-server-failed-bootstrap-does-not-loop ()
  (let ((p3/r-language-server-bootstrap-failed nil)
        (p3/r-language-server-ready nil)
        (attempts 0))
    (cl-letf (((symbol-function 'p3/r-program) (lambda () "/opt/R/bin/R"))
              ((symbol-function 'p3/r-version) (lambda (&optional _program) "4.5.1"))
              ((symbol-function 'p3/r-language-server-library)
               (lambda (_version) "/tmp/p3-r-tools/library/"))
              ((symbol-function 'p3/r-language-server-installed-p)
               (lambda (_program _library) nil))
              ((symbol-function 'p3/r-install-language-server)
               (lambda (_program _library)
                 (setq attempts (1+ attempts))
                 nil)))
      (should-not (p3/r-ensure-language-server))
      (should-not (p3/r-ensure-language-server))
      (should (= attempts 1)))))

(ert-deftest p3-r-language-server-signaled-bootstrap-failure-does-not-loop ()
  (let ((p3/r-language-server-bootstrap-failed nil)
        (p3/r-language-server-ready nil)
        (p3/r-language-server-warning-key nil)
        (attempts 0)
        warnings)
    (cl-letf (((symbol-function 'p3/r-program) (lambda () "/opt/R/bin/R"))
              ((symbol-function 'p3/r-version) (lambda (&optional _program) "4.5.1"))
              ((symbol-function 'p3/r-language-server-library)
               (lambda (_version) "/tmp/p3-r-tools/library/"))
              ((symbol-function 'p3/r-language-server-installed-p)
               (lambda (_program _library) nil))
              ((symbol-function 'p3/r-install-language-server)
               (lambda (_program _library)
                 (setq attempts (1+ attempts))
                 (error "permission denied")))
              ((symbol-function 'display-warning)
               (lambda (_type message &optional _level _buffer-name)
                 (push message warnings))))
      (should-not (p3/r-ensure-language-server))
      (should-not (p3/r-ensure-language-server))
      (should (= attempts 1))
      (should
       (equal p3/r-language-server-bootstrap-failed
              '("/opt/R/bin/R" . "/tmp/p3-r-tools/library/")))
      (should (= (length warnings) 1))
      (should (string-match-p "permission denied" (car warnings))))))

(ert-deftest p3-r-language-server-explicit-bootstrap-persists-readiness ()
  (let ((p3/r-language-server-bootstrap-failed nil)
        (p3/r-language-server-warning-key nil)
        written)
    (cl-letf (((symbol-function 'p3/r-language-server-clear-state)
               (lambda () nil))
              ((symbol-function 'p3/r-ensure-language-server)
               (lambda () "/tmp/p3-r-tools/library/"))
              ((symbol-function 'p3/r-program)
               (lambda () "/opt/R/bin/R"))
              ((symbol-function 'p3/r-language-server-write-state)
               (lambda (program library)
                 (setq written (cons program library)))))
      (p3/r-bootstrap-language-server)
      (should
       (equal written
              '("/opt/R/bin/R" . "/tmp/p3-r-tools/library/"))))))

(ert-deftest p3-r-language-server-missing-r-warns-once-from-buffer-hook ()
  (let ((p3/r-language-server-warning-key nil)
        warnings)
    (cl-letf (((symbol-function 'p3/r-program) (lambda () nil))
              ((symbol-function 'eglot-ensure)
               (lambda () (ert-fail "Eglot must not start without R")))
              ((symbol-function 'display-warning)
               (lambda (_type message &optional _level _buffer-name)
                 (push message warnings))))
      (should-not (p3/r-eglot-ensure))
      (should-not (p3/r-eglot-ensure))
      (should (= (length warnings) 1))
      (should (string-match-p "No usable R executable" (car warnings)))
      (should (string-match-p "p3/r-bootstrap-language-server" (car warnings))))))

(ert-deftest p3-r-language-server-command-keeps-project-startup-context ()
  (cl-letf (((symbol-function 'p3/r-program)
             (lambda () "C:/Program Files/R/R-4.5.1/bin/Rterm.exe"))
            ((symbol-function 'p3/r-language-server-ready-state)
             (lambda ()
               '("C:/Program Files/R/R-4.5.1/bin/Rterm.exe"
                 . "C:/Users/Pavel/r tools/R-4.5/library/"))))
    (let ((command (p3/r-language-server-command)))
      (should
       (equal (car command)
              "C:/Program Files/R/R-4.5.1/bin/Rterm.exe"))
      (should (member "--slave" command))
      (should-not (member "--vanilla" command))
      (should (string-match-p (regexp-quote ".libPaths(c(") (car (last command))))
      (should (string-match-p (regexp-quote "languageserver::run()")
                              (car (last command)))))))

(ert-deftest p3-r-eglot-preserves-ownership-and-limits-capabilities ()
  (require 'eglot)
  (with-temp-buffer
    (let ((eglot-stay-out-of '(xref))
          (eglot-ignored-server-capabilities '(:experimentalProvider))
          (eglot-server-programs
           '(((R-mode ess-r-mode) . ("R" "--slave" "-e" "old"))))
          (flycheck-mode t)
          called)
      (cl-letf (((symbol-function 'p3/r-language-server-command)
                 (lambda () '("managed-R" "--slave" "-e" "managed")))
                ((symbol-function 'eglot-ensure)
                 (lambda () (setq called t))))
        (p3/r-eglot-ensure))
      (should called)
      (should (local-variable-p 'eglot-stay-out-of))
      (should (local-variable-p 'eglot-ignored-server-capabilities))
      (should (local-variable-p 'eglot-server-programs))
      (should (member 'flymake eglot-stay-out-of))
      (should (member "company" eglot-stay-out-of))
      (should (member 'xref eglot-stay-out-of))
      (should flycheck-mode)
      (dolist (capability p3/r-eglot-ignored-capabilities)
        (should (memq capability eglot-ignored-server-capabilities)))
      (should (memq :experimentalProvider eglot-ignored-server-capabilities))
      (dolist (wanted '(:hoverProvider
                         :completionProvider
                         :signatureHelpProvider
                         :definitionProvider
                         :referencesProvider
                         :documentHighlightProvider
                         :documentSymbolProvider
                         :workspaceSymbolProvider
                         :codeActionProvider
                         :renameProvider
                         :callHierarchyProvider))
        (should-not (memq wanted eglot-ignored-server-capabilities)))
      (should
       (equal
        (alist-get '(R-mode ess-r-mode) eglot-server-programs nil nil #'equal)
        '("managed-R" "--slave" "-e" "managed"))))))

(ert-deftest p3-r-eglot-startup-error-degrades-cleanly ()
  (let ((p3/r-language-server-warning-key nil)
        warnings)
    (cl-letf (((symbol-function 'p3/r-language-server-command)
               (lambda () (error "broken R setup")))
              ((symbol-function 'display-warning)
               (lambda (_type message &optional _level _buffer-name)
                 (push message warnings))))
      (should-not (p3/r-eglot-ensure))
      (should-not (p3/r-eglot-ensure))
      (should (= (length warnings) 1))
      (should (string-match-p "broken R setup" (car warnings)))
      (should (string-match-p "ESS/editing remains available" (car warnings))))))

(ert-deftest p3-ess-library-has-no-buffer-configuration-glue ()
  (let ((contents (p3-config-ess-test--contents "lisp/p3-ess.el")))
    (dolist (forbidden '("p3/ess-inferior-mode-setup"
                         "ansi-color-for-comint-mode"
                         "smartparens-mode"))
      (should-not (string-match-p (regexp-quote forbidden) contents)))))

(ert-deftest p3-generic-completion-has-no-ess-company-owner ()
  (let ((contents
         (p3-config-ess-test--contents "lisp/p3-config-completion.el")))
    (dolist (forbidden '("p3/r-company-backends"
                         "p3/ess-company-config"
                         "company-R-library"
                         "company-R-args"
                         "company-R-objects"))
      (should-not (string-match-p (regexp-quote forbidden) contents)))))

(provide 'p3-config-ess-test)

;;; p3-config-ess-test.el ends here
