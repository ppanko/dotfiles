;;; p3-terminal-rich-ux-test.el --- Adversarial project Eshell UX tests -*- lexical-binding: t; -*-

(require 'ert)
(require 'ring)
(require 'eshell)

(defconst p3-terminal-rich-ux-test--root
  (file-name-directory
   (directory-file-name
    (file-name-directory (or load-file-name buffer-file-name))))
  "Root of the Emacs configuration under test.")

(add-to-list 'load-path
             (expand-file-name "lisp" p3-terminal-rich-ux-test--root))

(require 'p3-terminal)

(ert-deftest p3-terminal-eshell-setup-uses-history-search ()
  (with-temp-buffer
    (eshell-mode)
    (setq-local p3/project-shell-root-value temporary-file-directory)
    (p3/project-shell-mode-setup)
    (should eshell-hist-ignoredups)
    (should (eq (key-binding (kbd "C-r")) #'consult-history))))

(ert-deftest p3-terminal-prompt-has-path-and-status-marker ()
  (let ((default-directory temporary-file-directory)
        (p3/project-shell-root-value temporary-file-directory)
        (eshell-last-command-status 0))
    (let ((prompt (p3/project-shell-prompt)))
      (should (string-match-p "❯ " prompt))
      (should (string-match-p
               (regexp-quote
                (file-name-nondirectory
                 (directory-file-name temporary-file-directory)))
               prompt)))))

(ert-deftest p3-terminal-prompt-regexp-rejects-prompt-like-output ()
  (dolist (line '("cost $ 20"
                  "hash # tag"
                  "progress % done"
                  "redirect > file"))
    (should-not (string-match-p p3/project-shell-prompt-regexp line)))
  (should
   (string-match-p p3/project-shell-prompt-regexp
                   "project/subdir ❯ ")))

(ert-deftest p3-terminal-history-configuration-is-concurrent-safe ()
  (with-temp-buffer
    (eshell-mode)
    (setq-local p3/project-shell-root-value temporary-file-directory)
    (p3/project-shell-mode-setup)
    (if (boundp 'eshell-history-append)
        (progn
          (should (local-variable-p 'eshell-history-append))
          (should eshell-history-append))
      (should-not eshell-save-history-on-exit)
      (should (memq #'p3/project-shell--append-history-compat
                    eshell-input-filter-functions)))))

(ert-deftest p3-terminal-append-history-compat-appends-only-latest-entry ()
  (unless (fboundp 'eshell-write-history)
    (require 'em-hist))
  (let ((history-file (make-temp-file "p3-eshell-history-")))
    (unwind-protect
        (let ((eshell-history-file-name history-file)
              (eshell-history-ring (make-ring 4)))
          (ring-insert eshell-history-ring "__P3_HISTORY_OLD__")
          (ring-insert eshell-history-ring "__P3_HISTORY_NEW__")
          (p3/project-shell--append-history-compat)
          (with-temp-buffer
            (insert-file-contents history-file)
            (should (= 1 (how-many "__P3_HISTORY_NEW__"
                                   (point-min) (point-max))))
            (should-not (re-search-forward "__P3_HISTORY_OLD__" nil t))
            (should-not (re-search-forward "starship\|PS1=\|__p3_" nil t))))
      (delete-file history-file))))

(provide 'p3-terminal-rich-ux-test)

;;; p3-terminal-rich-ux-test.el ends here
