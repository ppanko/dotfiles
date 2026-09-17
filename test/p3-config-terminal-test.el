;;; p3-config-terminal-test.el --- Terminal config boundary tests -*- lexical-binding: t; -*-

(require 'ert)
(require 'seq)

(defconst p3-config-terminal-test--root
  (file-name-directory
   (directory-file-name
    (file-name-directory (or load-file-name buffer-file-name))))
  "Root of the Emacs configuration under test.")

(defun p3-config-terminal-test--path (relative)
  "Return RELATIVE under the repository root."
  (expand-file-name relative p3-config-terminal-test--root))

(defun p3-config-terminal-test--contents (relative)
  "Return contents of repository file RELATIVE."
  (with-temp-buffer
    (insert-file-contents (p3-config-terminal-test--path relative))
    (buffer-string)))

(defun p3-config-terminal-test--forms ()
  "Read all top-level forms from the terminal config module."
  (with-temp-buffer
    (insert-file-contents
     (p3-config-terminal-test--path "lisp/p3-config-terminal.el"))
    (goto-char (point-min))
    (let (forms)
      (condition-case nil
          (while t
            (push (read (current-buffer)) forms))
        (end-of-file nil))
      (nreverse forms))))

(ert-deftest p3-config-terminal-loads-behavior-before-shell-setup ()
  (let* ((forms (p3-config-terminal-test--forms))
         (behavior
          (seq-position forms '(p3/config-load-module 'p3-terminal) #'equal))
         (shell
          (seq-position forms '(p3/windows-configure-shell) #'equal)))
    (should (integerp behavior))
    (should (integerp shell))
    (should (< behavior shell))))

(ert-deftest p3-config-terminal-uses-one-project-shell-surface ()
  (let ((forms (p3-config-terminal-test--forms))
        (terminal (p3-config-terminal-test--contents "lisp/p3-terminal.el"))
        (config (p3-config-terminal-test--contents "lisp/p3-config-terminal.el")))
    (should
     (member
      '(global-set-key (kbd "C-x C-u") #'p3/project-shell)
      forms))
    (should
     (member
      '(keymap-global-set "C-c T" p3/project-shell-command-map)
      forms))
    (should-not (string-match-p "(require 'shell)" terminal))
    (should-not (string-match-p "shell-eval-command" terminal))
    (should (string-match-p "(use-package eat" config))
    (should (string-match-p "(use-package eshell-syntax-highlighting" config))
    (should-not (string-match-p "vterm" config))))

(ert-deftest p3-config-terminal-uses-dedicated-eat-visual-command-integration ()
  (let ((contents
         (p3-config-terminal-test--contents "lisp/p3-config-terminal.el")))
    (should (string-match-p "(use-package eat" contents))
    (should (string-match-p "eat-eshell-visual-command-mode" contents))
    (should-not (string-match-p "(eat-eshell-mode 1)" contents))
    (should-not (string-match-p
                 "eat-eshell-fallback-if-stty-not-available" contents))
    (should-not (string-match-p "eat--eshell-local-mode" contents))))

(ert-deftest p3-config-terminal-config-org-delegates-shell-boundary ()
  (let ((contents (p3-config-terminal-test--contents "config.org")))
    (should
     (= 1
        (let ((start 0)
              (count 0)
              (needle (regexp-quote
                       "(p3/config-load-module 'p3-config-terminal)")))
          (while (string-match needle contents start)
            (setq count (1+ count)
                  start (match-end 0)))
          count)))
    (dolist (forbidden '("(use-package p3-terminal"
                          "(p3/windows-configure-shell)"
                          "(use-package vterm"))
      (should-not (string-match-p (regexp-quote forbidden) contents)))))

(provide 'p3-config-terminal-test)

;;; p3-config-terminal-test.el ends here
