;;; p3-recovery-state-test.el --- Recovery-state path tests -*- lexical-binding: t; -*-

(require 'ert)
(require 'cl-lib)

(defconst p3-recovery-state-test--root
  (file-name-directory
   (directory-file-name
    (file-name-directory (or load-file-name buffer-file-name))))
  "Root of the Emacs configuration under test.")

(add-to-list 'load-path (expand-file-name "lisp" p3-recovery-state-test--root))

(require 'p3-core)

(defun p3-recovery-state-test--contents (path)
  "Return repository file PATH as a string."
  (with-temp-buffer
    (insert-file-contents (expand-file-name path p3-recovery-state-test--root))
    (buffer-string)))

(ert-deftest p3-state-directory-linux-respects-xdg-state-home ()
  (let ((system-type 'gnu/linux)
        (process-environment (copy-sequence process-environment)))
    (setenv "XDG_STATE_HOME" "/tmp/p3-state-root")
    (should
     (equal (p3/state-directory)
            (file-name-as-directory
             (expand-file-name "emacs" "/tmp/p3-state-root"))))))

(ert-deftest p3-state-directory-linux-falls-back-under-home ()
  (let ((system-type 'gnu/linux)
        (process-environment (copy-sequence process-environment)))
    (setenv "XDG_STATE_HOME" nil)
    (should
     (equal (p3/state-directory)
            (file-name-as-directory
             (expand-file-name "~/.local/state/emacs/"))))))

(ert-deftest p3-state-directory-windows-respects-localappdata ()
  (let ((system-type 'windows-nt)
        (process-environment (copy-sequence process-environment)))
    (setenv "LOCALAPPDATA" "C:/p3-test/AppData/Local")
    (should
     (equal (p3/state-directory)
            (file-name-as-directory
             (expand-file-name "Emacs" "C:/p3-test/AppData/Local"))))))

(ert-deftest p3-state-directory-windows-falls-back-under-home ()
  (let ((system-type 'windows-nt)
        (process-environment (copy-sequence process-environment)))
    (setenv "LOCALAPPDATA" nil)
    (should
     (equal (p3/state-directory)
            (file-name-as-directory
             (expand-file-name "~/.local/state/emacs/"))))))

(ert-deftest p3-recovery-state-keeps-crash-files-separate-from-durable-state ()
  (let ((base (p3-recovery-state-test--contents "lisp/p3-config-base.el")))
    (should (string-match-p (regexp-quote "~/.cache/tmp/emacs/auto-saves/") base))
    (should-not (string-match-p (regexp-quote "~/.cache/tmp/emacs/backups") base))
    (should (string-match-p (regexp-quote "p3/state-directory") base))
    (should (string-match-p (regexp-quote "backup-directory-alist") base))
    (should (string-match-p (regexp-quote "tramp-backup-directory-alist") base))
    (should (string-match-p (regexp-quote "tramp-auto-save-directory auto-saves-dir") base))))

(ert-deftest p3-recovery-state-preserves-backup-retention-policy ()
  (let ((base (p3-recovery-state-test--contents "lisp/p3-config-base.el")))
    (should (string-match-p (regexp-quote "backup-by-copying t") base))
    (should (string-match-p (regexp-quote "delete-old-versions t") base))
    (should (string-match-p (regexp-quote "version-control t") base))
    (should (string-match-p (regexp-quote "kept-new-versions 5") base))
    (should (string-match-p (regexp-quote "kept-old-versions 2") base))))

(ert-deftest p3-recovery-state-enables-persistent-undo-before-global-mode ()
  (let* ((editing
          (p3-recovery-state-test--contents "lisp/p3-config-editing.el"))
         (history-position
          (string-match (regexp-quote "undo-tree-auto-save-history t") editing))
         (mode-position
          (string-match (regexp-quote "(global-undo-tree-mode)") editing)))
    (should-not (string-match-p (regexp-quote "~/.emacs.d/undo") editing))
    (should (string-match-p (regexp-quote "p3/state-directory") editing))
    (should history-position)
    (should mode-position)
    (should (< history-position mode-position))))

(provide 'p3-recovery-state-test)

;;; p3-recovery-state-test.el ends here
