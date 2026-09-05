;;; p3-config-test.el --- Smoke tests for the Emacs config -*- lexical-binding: t; -*-

(require 'ert)
(require 'subr-x)

(defconst p3-config-test--root
  (file-name-directory
   (directory-file-name
    (file-name-directory (or load-file-name buffer-file-name))))
  "Root of the Emacs configuration under test.")

(add-to-list 'load-path (expand-file-name "lisp" p3-config-test--root))
(require 'p3-config-loader)

(defun p3-config-test--path (relative)
  "Return RELATIVE under the repository root."
  (expand-file-name relative p3-config-test--root))

(defun p3-config-test--contents (relative)
  "Return contents of repository file RELATIVE."
  (with-temp-buffer
    (insert-file-contents (p3-config-test--path relative))
    (buffer-string)))

(defun p3-config-test--assert-readable-elisp (path)
  "Fail when PATH does not contain syntactically readable Emacs Lisp."
  (with-temp-buffer
    (insert-file-contents path)
    (emacs-lisp-mode)
    (condition-case err
        (progn
          (check-parens)
          (goto-char (point-min))
          (condition-case nil
              (while t
                (read (current-buffer)))
            (end-of-file t)))
      (error
       (ert-fail
        (format "Could not read %s: %s" path (error-message-string err)))))))

(defun p3-config-test--position (needle contents)
  "Return one-based end position of NEEDLE in CONTENTS, failing if absent."
  (let ((position (string-match (regexp-quote needle) contents)))
    (should position)
    (+ position (length needle))))

(defun p3-config-test--count-occurrences (needle contents)
  "Return the number of non-overlapping NEEDLE occurrences in CONTENTS."
  (let ((start 0)
        (count 0)
        (regexp (regexp-quote needle)))
    (while (string-match regexp contents start)
      (setq count (1+ count)
            start (match-end 0)))
    count))

(ert-deftest p3-init-el-is-readable ()
  (p3-config-test--assert-readable-elisp
   (p3-config-test--path "init.el")))

(ert-deftest p3-config-org-builds-through-production-cache-contract ()
  (let* ((directory (make-temp-file "p3-config-real-build-" t))
         (p3/config-source (p3-config-test--path "config.org"))
         (p3/config-generated (expand-file-name "config.el" directory)))
    (unwind-protect
        (progn
          (should (equal (p3/config-build) p3/config-generated))
          (should-not (p3/config-cache-stale-p))
          (with-temp-buffer
            (insert-file-contents p3/config-generated)
            (goto-char (point-min))
            (should
             (looking-at
              ";; p3-config-source-sha256: [0-9a-f]\\{64\\}$")))
          (p3-config-test--assert-readable-elisp p3/config-generated))
      (delete-directory directory t))))

(ert-deftest p3-config-org-owns-org-export-integration ()
  (let ((contents (p3-config-test--contents "config.org"))
        (org-config (p3-config-test--contents "lisp/p3-config-org.el")))
    (should
     (string-match-p
      (regexp-quote "(p3/config-load-module 'p3-config-org)") contents))
    (should (string-match-p "(use-package p3-org-export" org-config))
    (should-not (string-match-p "(defun p3/org-export-to-office" contents))
    (should-not (string-match-p "(defun p3/org-export-to-office" org-config))))

(ert-deftest p3-config-org-delegates-custom-subsystems-to-modules ()
  (let ((contents (p3-config-test--contents "config.org")))
    (dolist (module '("p3-platform" "p3-core"))
      (should (string-match-p (regexp-quote (format "(use-package %s" module))
                              contents)))
    (dolist (module '(p3-config-ess p3-config-gptel p3-config-org
                      p3-config-org-roam p3-config-org-present
                      p3-config-project p3-config-python p3-config-reference
                      p3-config-terminal))
      (should
       (string-match-p
        (regexp-quote (format "(p3/config-load-module '%s)" module))
        contents)))
    (dolist (implementation '("(defun p3/windows-rtools-version"
                               "(defun p3/windows-latest-r-program"
                               "(defun p3/project-root"
                               "(defun p3/python-project-interpreter"
                               "(defun p3/vterm-buffer"
                               "(defun p3/ess-project-root"
                               "(defun p3/ess-ensure-project-process"
                               "(defun p3/gptel-send-task"))
      (should-not (string-match-p (regexp-quote implementation) contents)))))

(ert-deftest p3-config-early-orchestration-order-is-explicit ()
  (let* ((contents (p3-config-test--contents "config.org"))
         (newer (p3-config-test--position "(setq load-prefer-newer t)" contents))
         (auto (p3-config-test--position "(auto-compile-on-load-mode)" contents))
         (secrets (p3-config-test--position "(load-file p3/secrets-file)" contents))
         (rtools (p3-config-test--position "(p3/windows-configure-rtools)" contents))
         (base (p3-config-test--position
                "(p3/config-load-module 'p3-config-base)" contents))
         (editing (p3-config-test--position
                   "(p3/config-load-module 'p3-config-editing)" contents))
         (reference (p3-config-test--position
                     "(p3/config-load-module 'p3-config-reference)" contents))
         (completion (p3-config-test--position
                      "(p3/config-load-module 'p3-config-completion)" contents))
         (ess (p3-config-test--position
               "(p3/config-load-module 'p3-config-ess)" contents))
         (r-program (p3-config-test--position
                     "(p3/windows-configure-r-program)" contents))
         (terminal (p3-config-test--position
                    "(p3/config-load-module 'p3-config-terminal)" contents)))
    (should (< newer auto))
    (should (< auto secrets))
    (should (< secrets rtools))
    (should (< rtools base))
    (should (< base editing))
    (should (< editing reference))
    (should (< reference completion))
    (should (< completion ess))
    (should (< ess r-program))
    (should (< r-program terminal))))

(ert-deftest p3-config-platform-setup-preserves-subsystem-timing ()
  (let* ((contents (p3-config-test--contents "config.org"))
         (terminal-config
          (p3-config-test--contents "lisp/p3-config-terminal.el"))
         (rtools (p3-config-test--position "(p3/windows-configure-rtools)" contents))
         (ess (p3-config-test--position
               "(p3/config-load-module 'p3-config-ess)" contents))
         (r-program (p3-config-test--position
                     "(p3/windows-configure-r-program)" contents))
         (terminal (p3-config-test--position
                    "(p3/config-load-module 'p3-config-terminal)" contents))
         (behavior (p3-config-test--position
                    "(p3/config-load-module 'p3-terminal)" terminal-config))
         (shell (p3-config-test--position
                 "(p3/windows-configure-shell)" terminal-config))
         (shell-binding (p3-config-test--position
                         "(global-set-key (kbd \"C-x C-u\") #'shell)"
                         terminal-config)))
    (should-not (string-match-p "(p3/platform-setup)" contents))
    (should (< rtools ess))
    (should (< ess r-program))
    (should (< r-program terminal))
    (should (< behavior shell))
    (should (< shell shell-binding))))

(ert-deftest p3-config-org-subsystem-order-is-explicit ()
  (let* ((contents (p3-config-test--contents "config.org"))
         (org (p3-config-test--position
               "(p3/config-load-module 'p3-config-org)" contents))
         (roam (p3-config-test--position
                "(p3/config-load-module 'p3-config-org-roam)" contents))
         (poly-r (p3-config-test--position "(use-package poly-R" contents))
         (present (p3-config-test--position
                   "(p3/config-load-module 'p3-config-org-present)" contents))
         (project-config
          (p3-config-test--position
           "(p3/config-load-module 'p3-config-project)" contents))
         (python (p3-config-test--position
                  "(p3/config-load-module 'p3-config-python)" contents)))
    (should (< org roam))
    (should (< roam poly-r))
    (should (< poly-r present))
    (should (< present project-config))
    (should (< project-config python))))

(ert-deftest p3-config-python-preserves-subsystem-timing ()
  (let* ((contents (p3-config-test--contents "config.org"))
         (flycheck (p3-config-test--position "(use-package flycheck" contents))
         (project-config
          (p3-config-test--position
           "(p3/config-load-module 'p3-config-project)" contents))
         (python (p3-config-test--position
                  "(p3/config-load-module 'p3-config-python)" contents))
         (rainbow (p3-config-test--position "(use-package rainbow-mode" contents))
         (terminal (p3-config-test--position
                    "(p3/config-load-module 'p3-config-terminal)" contents)))
    (should (< flycheck project-config))
    (should (< project-config python))
    (should (< python rainbow))
    (should (< rainbow terminal))))

(ert-deftest p3-config-org-source-loads-fourteen-config-modules ()
  (let ((contents (p3-config-test--contents "config.org")))
    (should (= 14
               (p3-config-test--count-occurrences
                "(p3/config-load-module 'p3-config-" contents)))
    (dolist (module '(p3-config-base p3-config-editing p3-config-completion
                      p3-config-ess p3-config-gptel p3-config-org
                      p3-config-org-roam p3-config-org-present p3-config-project
                      p3-config-python p3-config-reference p3-config-terminal
                      p3-config-workspace p3-config-git))
      (should
       (string-match-p
        (regexp-quote (format "(p3/config-load-module '%s)" module))
        contents)))))

(ert-deftest p3-config-moved-implementation-is-not-inline ()
  (let ((contents (p3-config-test--contents "config.org")))
    (dolist (implementation
             '("(defconst p3/keybinding-sections"
               "(defun p3/keybinding-atlas"
               "(defun p3/save-kill-other-buffers"
               "(defun p3/sudo-edit"
               "(defun p3/region-suffix"
               "(defun p3/newline-after-comma-or-space"
               "(defun p3/force-quotes"
               "(defun p3/byte-compile-init-dir"
               "(defun p3/windows-shell"
               "(defun move-line"
               "(defun move-line-up"
               "(defun move-line-down"
               "(defun p3/open-in-external-app"
               "(defun check-curl-version"
               "(defun p3/get-local-buffer-mode"
               "(defun p3/is-current-buffer-mode-inferior-ess-r-mode"
               "(defun p3/check-git-installed"
               "(defun p3/get-commit-message"
               "(defun p3/git-call"
               "(defun p3/git-run"
               "(defun p3/git-commit-and-push-repository"
               "(defun p3/git-commit-and-push-emacs-config"
               "(defun close-magit-buffers"
               "(defun p3/consult-r-doc-chapter-search"
               "(defun p3/consult-line-all"
               "(defun p3/ess-company-config"
               "(defvar p3/r-company-backends"
               "(use-package p3-r-tools"
               "(use-package p3-ess"
               "(use-package ess-r-mode"
               "(defun compile-rmd"
               "(use-package p3-python"
               "(use-package python"
               "(use-package eglot"
               "(add-hook 'python-ts-mode-hook"
               "flycheck-python-flake8-executable"
               "(defun p3/org-sort-todos"
               "(defun org-set-line-checkbox"
               "(use-package p3-org-export"
               "(use-package org-agenda"
               "(defun org-roam-generate-tagged-header"
               "(defun org-roam-node-insert-immediate-with-tag"
               "(defun org-roam-rg-search"
               "(defun p3/org-roam-filter-by-tag"
               "(defun p3/org-roam-list-notes"
               "(defun p3/org-roam-list-notes-by-tag"
               "(defun p3/org-roam-get-agenda"
               "(use-package org-roam"
               "(defvar-local p3/org-present--state"
               "(defun p3/org-present-start"
               "(defun p3/org-present-toggle-fullscreen"
               "(defun p3/org-present-hook"
               "(defun p3/org-present-quit-hook"
               "(defun p3/org-present-prev"
               "(defun p3/org-present-next"
               "(use-package org-present"
               "(use-package p3-terminal"
               "(p3/windows-configure-shell)"
               "(use-package vterm"
               "(use-package gptel"
               "(use-package p3-gptel"
               "(use-package projectile"
               "(defun p3/projectile-r-project-file-p"
               "projectile-command-map"
               "projectile-register-project-type"
               "(projectile-mode +1)"))
      (should-not (string-match-p (regexp-quote implementation) contents)))
    (dolist (package '(dashboard which-key vertico company undo-tree super-save
                       multiple-cursors magit git-gutter-fringe+ transpose-frame
                       ace-window restart-emacs avy))
      (should-not
       (string-match-p (regexp-quote (format "(use-package %s" package))
                       contents)))))

(ert-deftest p3-config-reference-replaces-inline-citation-stack ()
  (let ((contents (p3-config-test--contents "config.org")))
    (should (= 1
               (p3-config-test--count-occurrences
                "(p3/config-load-module 'p3-config-reference)" contents)))
    (dolist (forbidden '("(use-package citar"
                          "(use-package citar-org-roam"
                          "reftex-default-bibliography"
                          "reftex-cite-format"
                          "bib-files-directory"
                          "p3/bib-library"
                          "p3/pdf-library"))
      (should-not (string-match-p (regexp-quote forbidden) contents)))
    (dolist (retained '("(setq org-latex-pdf-process"
                          "(use-package poly-R"))
      (should (string-match-p (regexp-quote retained) contents)))))

(ert-deftest p3-config-ess-orchestration-has-one-owner ()
  (let* ((contents (p3-config-test--contents "config.org"))
         (ess (p3-config-test--position
               "(p3/config-load-module 'p3-config-ess)" contents))
         (r-program (p3-config-test--position
                     "(p3/windows-configure-r-program)" contents)))
    (should-not (string-match-p "(use-package p3-r-tools" contents))
    (should-not
     (string-match-p
      (regexp-quote "(keymap-global-set \"C-c R\"") contents))
    (should (< ess r-program))))

(ert-deftest p3-config-project-orchestration-has-one-owner ()
  (let* ((contents (p3-config-test--contents "config.org"))
         (owner "(p3/config-load-module 'p3-config-project)"))
    (should (= 1 (p3-config-test--count-occurrences owner contents)))
    (dolist (forbidden '("(use-package projectile"
                          "p3/projectile-r-project-file-p"
                          "projectile-command-map"
                          "projectile-register-project-type"
                          "(projectile-mode +1)"))
      (should-not (string-match-p (regexp-quote forbidden) contents)))))

(ert-deftest p3-config-python-orchestration-has-one-owner ()
  (let* ((contents (p3-config-test--contents "config.org"))
         (org-config (p3-config-test--contents "lisp/p3-config-org.el"))
         (owner "(p3/config-load-module 'p3-config-python)"))
    (should (= 1 (p3-config-test--count-occurrences owner contents)))
    (dolist (forbidden '("(use-package p3-python"
                          "(use-package python"
                          "(use-package eglot"
                          "(add-hook 'python-ts-mode-hook"
                          "flycheck-python-flake8-executable"))
      (should-not (string-match-p (regexp-quote forbidden) contents)))
    (should (string-match-p (regexp-quote "(python . t)") org-config))))

(ert-deftest p3-config-gptel-orchestration-has-one-owner ()
  (let* ((contents (p3-config-test--contents "config.org"))
         (owner "(p3/config-load-module 'p3-config-gptel)"))
    (should (= 1 (p3-config-test--count-occurrences owner contents)))
    (dolist (forbidden '("(use-package gptel"
                          "(use-package p3-gptel"))
      (should-not (string-match-p (regexp-quote forbidden) contents)))))

(ert-deftest p3-config-behavior-library-owner-pattern-is-explicit ()
  (let ((base (p3-config-test--contents "lisp/p3-config-base.el"))
        (git (p3-config-test--contents "lisp/p3-config-git.el"))
        (gptel (p3-config-test--contents "lisp/p3-config-gptel.el"))
        (org (p3-config-test--contents "lisp/p3-config-org.el"))
        (reference (p3-config-test--contents "lisp/p3-config-reference.el"))
        (roam (p3-config-test--contents "lisp/p3-config-org-roam.el"))
        (present (p3-config-test--contents "lisp/p3-config-org-present.el"))
        (terminal (p3-config-test--contents "lisp/p3-config-terminal.el"))
        (commands (p3-config-test--contents "lisp/p3-commands.el"))
        (git-behavior (p3-config-test--contents "lisp/p3-git.el"))
        (gptel-behavior (p3-config-test--contents "lisp/p3-gptel.el"))
        (org-behavior (p3-config-test--contents "lisp/p3-org.el"))
        (reference-behavior (p3-config-test--contents "lisp/p3-reference.el"))
        (roam-behavior (p3-config-test--contents "lisp/p3-org-roam.el"))
        (present-behavior (p3-config-test--contents "lisp/p3-org-present.el"))
        (terminal-behavior (p3-config-test--contents "lisp/p3-terminal.el")))
    (should (string-match-p
             (regexp-quote "(p3/config-load-module 'p3-commands)") base))
    (should (string-match-p
             (regexp-quote "(p3/config-load-module 'p3-git)") git))
    (should (string-match-p
             (regexp-quote "(p3/config-load-module 'p3-gptel)") gptel))
    (should (string-match-p
             (regexp-quote "(p3/config-load-module 'p3-org)") org))
    (should (string-match-p
             (regexp-quote "(p3/config-load-module 'p3-reference)") reference))
    (should (string-match-p
             (regexp-quote "(p3/config-load-module 'p3-org-roam)") roam))
    (should (string-match-p
             (regexp-quote "(p3/config-load-module 'p3-org-present)") present))
    (should (string-match-p
             (regexp-quote "(p3/config-load-module 'p3-terminal)") terminal))
    (dolist (behavior (list commands git-behavior gptel-behavior org-behavior
                            reference-behavior roam-behavior present-behavior
                            terminal-behavior))
      (should-not (string-match-p "p3-config-" behavior)))))

(ert-deftest p3-config-workspace-keeps-only-narrow-ess-display-policy ()
  (let ((contents (p3-config-test--contents "lisp/p3-config-workspace.el")))
    (should (string-match-p
             (regexp-quote "(major-mode . inferior-ess-r-mode)") contents))
    (dolist (broad '("python" "vterm" "shell-mode" "repl"))
      (should-not (string-match-p broad contents)))))

(ert-deftest p3-config-generated-artifacts-remain-ignored-and-untracked ()
  (skip-unless (executable-find "git"))
  (let ((default-directory p3-config-test--root))
    (dolist (generated '("config.el" "lisp/example.elc"))
      (should (zerop (process-file "git" nil nil nil
                                   "check-ignore" "-q" generated))))
    (with-temp-buffer
      (should (zerop (process-file "git" nil (current-buffer) nil
                                   "ls-files" "config.el" "*.elc")))
      (should (string-empty-p (string-trim (buffer-string)))))))

(ert-deftest p3-init-loads-project-and-loader-before-literate-config ()
  (let* ((contents (p3-config-test--contents "init.el"))
         (load-path-position
          (p3-config-test--position
           "(add-to-list 'load-path p3/lisp-directory)" contents))
         (project-position
          (p3-config-test--position "(require 'p3-project)" contents))
         (loader-position
          (p3-config-test--position "(require 'p3-config-loader)" contents))
         (config-position
          (p3-config-test--position "(p3/config-load)" contents)))
    (should (< load-path-position project-position))
    (should (< project-position loader-position))
    (should (< loader-position config-position))))

(ert-deftest p3-init-does-not-unconditionally-load-org-for-tangling ()
  (let ((contents (p3-config-test--contents "init.el")))
    (should-not (string-match-p "(require 'ob-tangle)" contents))
    (should-not (string-match-p "(org-babel-tangle-file" contents))
    (should-not (string-match-p "(defun p3/load-config" contents))))

(ert-deftest p3-init-does-not-special-case-org-export ()
  (let ((contents (p3-config-test--contents "init.el")))
    (should-not (string-match-p "(load \"p3-org-export\"" contents))))

(provide 'p3-config-test)

;;; p3-config-test.el ends here
