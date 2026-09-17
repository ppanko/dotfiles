;;; p3-terminal-rich-ux-test.el --- Adversarial project Eshell UX tests -*- lexical-binding: t; -*-

(require 'cl-lib)
(require 'ert)
(require 'ring)
(require 'eshell)
(require 'em-hist)
(require 'em-term)

(defconst p3-terminal-rich-ux-test--root
  (file-name-directory
   (directory-file-name
    (file-name-directory (or load-file-name buffer-file-name))))
  "Root of the Emacs configuration under test.")

(add-to-list 'load-path
             (expand-file-name "lisp" p3-terminal-rich-ux-test--root))

(require 'p3-terminal)

(defun p3-terminal-rich-ux-test--fake-history-writer (filename append)
  "Write the newest history entry to FILENAME, honoring APPEND."
  (let ((entry (ring-ref eshell-history-ring 0)))
    (with-temp-buffer
      (insert entry "\n")
      (write-region (point-min) (point-max) filename append 'silent))))

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

(ert-deftest p3-terminal-new-shell-starts-with-one-p3-prompt ()
  (let* ((root (file-name-as-directory temporary-file-directory))
         (name (generate-new-buffer-name "*p3-prompt-test*"))
         (buffer (p3/project-shell--start name root)))
    (unwind-protect
        (with-current-buffer buffer
          (goto-char (point-min))
          (should (= 1 (how-many "❯ " (point-min) (point-max))))
          (should (derived-mode-p 'eshell-mode)))
      (when (buffer-live-p buffer)
        (kill-buffer buffer)))))

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
      (should-not (memq #'eshell-write-history eshell-exit-hook))
      (should-not (memq #'eshell-add-to-history
                        eshell-input-filter-functions))
      (should (memq #'p3/project-shell--append-history-compat
                    eshell-input-filter-functions)))))

(ert-deftest p3-terminal-history-compat-appends-only-accepted-new-input ()
  (let ((history-file (make-temp-file "p3-eshell-history-"))
        (eshell-history-ring (make-ring 4))
        (next-input "__P3_HISTORY_NEW__"))
    (unwind-protect
        (progn
          (ring-insert eshell-history-ring "__P3_HISTORY_OLD__")
          (cl-letf (((symbol-function 'eshell-add-to-history)
                     (lambda ()
                       (when next-input
                         (unless (and (not (ring-empty-p eshell-history-ring))
                                      (equal (ring-ref eshell-history-ring 0)
                                             next-input))
                           (ring-insert eshell-history-ring next-input)))))
                    ((symbol-function 'eshell-write-history)
                     #'p3-terminal-rich-ux-test--fake-history-writer))
            (let ((eshell-history-file-name history-file))
              (p3/project-shell--append-history-compat)
              ;; Consecutive duplicate: Eshell rejects it, so nothing new is
              ;; appended to the shared history file.
              (p3/project-shell--append-history-compat)
              ;; Blank/filtered input: represented here by no ring mutation.
              (setq next-input nil)
              (p3/project-shell--append-history-compat)))
          (with-temp-buffer
            (insert-file-contents history-file)
            (should (= 1 (how-many "__P3_HISTORY_NEW__"
                                   (point-min) (point-max))))
            (goto-char (point-min))
            (should-not (re-search-forward "__P3_HISTORY_OLD__" nil t))))
      (delete-file history-file))))

(ert-deftest p3-terminal-history-compat-kill-order-does-not-overwrite-peer-history ()
  (let ((history-file (make-temp-file "p3-eshell-history-shared-"))
        (first (generate-new-buffer " *p3-history-first*"))
        (second (generate-new-buffer " *p3-history-second*")))
    (unwind-protect
        (cl-letf (((symbol-function 'eshell-write-history)
                   #'p3-terminal-rich-ux-test--fake-history-writer))
          (dolist (spec `((,first . "__P3_FIRST__")
                          (,second . "__P3_SECOND__")))
            (with-current-buffer (car spec)
              (eshell-mode)
              ;; Simulate the Emacs 29 history module's overwrite-on-exit hook.
              (add-hook 'eshell-exit-hook #'eshell-write-history nil t)
              (setq-local eshell-history-file-name history-file
                          eshell-history-ring (make-ring 4))
              (p3/project-shell--setup-history-append-compat)
              (ring-insert eshell-history-ring (cdr spec))
              (p3/project-shell--write-latest-history-compat)
              (should-not (memq #'eshell-write-history eshell-exit-hook))))
          ;; Killing either shell must not rewrite the complete stale ring.
          (kill-buffer first)
          (kill-buffer second)
          (with-temp-buffer
            (insert-file-contents history-file)
            (should (= 1 (how-many "__P3_FIRST__" (point-min) (point-max))))
            (should (= 1 (how-many "__P3_SECOND__" (point-min) (point-max))))))
      (when (buffer-live-p first) (kill-buffer first))
      (when (buffer-live-p second) (kill-buffer second))
      (delete-file history-file))))

(ert-deftest p3-terminal-managed-eshell-routes-visual-commands-through-eat-path ()
  (with-temp-buffer
    (eshell-mode)
    (should (member "top" eshell-visual-commands))
    (setq-local p3/project-shell-root-value temporary-file-directory)
    (p3/project-shell-mode-setup)
    (should (local-variable-p 'eshell-visual-commands))
    (should (local-variable-p 'eshell-visual-subcommands))
    (should (local-variable-p 'eshell-visual-options))
    (should-not eshell-visual-commands)
    (should-not eshell-visual-subcommands)
    (should-not eshell-visual-options)))

(provide 'p3-terminal-rich-ux-test)

;;; p3-terminal-rich-ux-test.el ends here
