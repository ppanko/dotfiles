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

(ert-deftest p3-config-terminal-preserves-platform-specific-wiring ()
  (let ((forms (p3-config-terminal-test--forms)))
    (should
     (member
      '(when (eq system-type 'windows-nt)
         (global-set-key (kbd "C-x C-u") #'shell))
      forms))
    (should
     (member
      '(when (eq system-type 'gnu/linux)
         (keymap-global-set "C-c T" p3/vterm-command-map)
         (use-package vterm
           :commands (vterm vterm-other-window)
           :hook (vterm-mode . p3/vterm-mode-setup)
           :bind (("C-x C-u" . p3/vterm)
                  :map vterm-mode-map
                  ("C-y" . vterm-yank)
                  ("M-y" . vterm-yank-pop)
                  ("C-S-v" . vterm-yank)
                  ("C-S-c" . p3/vterm-enter-copy-mode)
                  :map vterm-copy-mode-map
                  ("C-S-c" . vterm-copy-mode-done))
           :custom
           (vterm-max-scrollback 100000)
           (vterm-kill-buffer-on-exit t)
           (vterm-always-compile-module t)
           :init
           (setq vterm-environment
                 (cons (format "P3_BLESH_FILE=%s" (p3/blesh-file))
                       (seq-remove
                        (lambda (entry)
                          (string-prefix-p "P3_BLESH_FILE=" entry))
                        (and (boundp 'vterm-environment) vterm-environment)))
                 vterm-shell
                 (format "%s --noprofile --rcfile %s -i"
                         (shell-quote-argument "/usr/bin/bash")
                         (shell-quote-argument
                          (expand-file-name "vterm-bashrc"
                                            user-emacs-directory))))))
      forms))))

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
