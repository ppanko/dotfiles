;;; p3-terminal-rich-ux-test.el --- Adversarial project Eshell UX tests -*- lexical-binding: t; -*-

(require 'cl-lib)
(require 'ert)
(require 'ring)
(require 'eshell)
(require 'em-hist)
(require 'em-term)
(require 'esh-ext)

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
              ;; Replace the current Emacs version's exit hook with the exact
              ;; overwrite-on-exit shape used by Emacs 29.
              (setq-local eshell-exit-hook '(eshell-write-history))
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

(ert-deftest p3-terminal-managed-eshell-installs-project-local-eat-interpreter ()
  (let ((managed (generate-new-buffer " *p3-managed-interpreter*"))
        (ordinary (generate-new-buffer " *p3-ordinary-interpreter*")))
    (unwind-protect
        (progn
          (with-current-buffer ordinary
            (eshell-mode)
            (should-not (assq #'p3/project-shell-eat-visual-command-p
                              eshell-interpreter-alist)))
          (with-current-buffer managed
            (eshell-mode)
            (setq-local p3/project-shell-root-value temporary-file-directory)
            (p3/project-shell-mode-setup)
            (should (local-variable-p 'eshell-interpreter-alist))
            (let ((entry
                   (assq #'p3/project-shell-eat-visual-command-p
                         eshell-interpreter-alist)))
              (should entry)
              (should (eq (cdr entry) #'p3/project-shell-exec-visual)))
            ;; Keep the stock Eshell visual interpreter after P3's narrower
            ;; route so unsupported platforms still use their normal backend.
            (should (assq #'eshell-visual-command-p eshell-interpreter-alist)))
          (with-current-buffer ordinary
            (should-not (assq #'p3/project-shell-eat-visual-command-p
                              eshell-interpreter-alist))))
      (dolist (buffer (list managed ordinary))
        (when (buffer-live-p buffer)
          (kill-buffer buffer))))))

(ert-deftest p3-terminal-visual-dispatch-preserves-line-oriented-output ()
  (with-temp-buffer
    (eshell-mode)
    (setq-local p3/project-shell-root-value temporary-file-directory)
    (p3/project-shell-mode-setup)
    ;; P3-specific commands must not be added wholesale to Eshell's visual
    ;; list, otherwise every informational invocation loses its scrollback.
    (should-not (member "codex" eshell-visual-commands))
    (should-not (member "pacman" eshell-visual-commands))
    (cl-letf (((symbol-function 'p3/project-shell-eat-supported-p)
               (lambda () t))
              ((symbol-function 'eshell-interactive-output-p)
               (lambda (&rest _) t)))
      ;; Existing full-screen commands still use the dedicated Eat path.
      (should (p3/project-shell-eat-visual-command-p "top" nil))
      ;; Interactive Codex sessions are visual; batch/help/version commands
      ;; remain ordinary Eshell commands so their output persists.
      (should (p3/project-shell-eat-visual-command-p "codex" nil))
      (should (p3/project-shell-eat-visual-command-p
               "codex" '("fix this bug")))
      (should (p3/project-shell-eat-visual-command-p
               "codex" '("resume" "--last")))
      (should-not (p3/project-shell-eat-visual-command-p
                   "codex" '("--version")))
      (should-not (p3/project-shell-eat-visual-command-p
                   "codex" '("--help")))
      (should-not (p3/project-shell-eat-visual-command-p
                   "codex" '("exec" "do work")))
      (should-not (p3/project-shell-eat-visual-command-p
                   "codex" '("completion" "bash")))
      ;; Pacman mutation/download operations need a terminal for readable
      ;; progress; query/search/info operations should stay in Eshell.
      (should (p3/project-shell-eat-visual-command-p
               "pacman" '("-Syu")))
      (should (p3/project-shell-eat-visual-command-p
               "pacman" '("-S" "ripgrep")))
      (should (p3/project-shell-eat-visual-command-p
               "pacman" '("-U" "pkg.tar.zst")))
      (should (p3/project-shell-eat-visual-command-p
               "pacman" '("-R" "ripgrep")))
      (should (p3/project-shell-eat-visual-command-p
               "sudo" '("pacman" "-Syu")))
      (should-not (p3/project-shell-eat-visual-command-p
                   "pacman" '("-Q")))
      (should-not (p3/project-shell-eat-visual-command-p
                   "pacman" '("-Ss" "emacs")))
      (should-not (p3/project-shell-eat-visual-command-p
                   "pacman" '("-Si" "emacs")))
      (should-not (p3/project-shell-eat-visual-command-p
                   "sudo" '("pacman" "-Q")))
      (should-not (p3/project-shell-eat-visual-command-p
                   "git" '("status"))))
    ;; When Eat's PTY path is unsupported (native Windows), P3 declines the
    ;; route entirely and lets Eshell's stock visual interpreter decide.
    (cl-letf (((symbol-function 'p3/project-shell-eat-supported-p)
               (lambda () nil))
              ((symbol-function 'eshell-interactive-output-p)
               (lambda (&rest _) t)))
      (should-not (p3/project-shell-eat-visual-command-p "top" nil))
      (should-not (p3/project-shell-eat-visual-command-p "codex" nil))
      (should-not (p3/project-shell-eat-visual-command-p
                   "pacman" '("-Syu"))))))

(ert-deftest p3-terminal-eat-exit-cleanup-is-scoped-to-managed-parent ()
  (let ((managed (generate-new-buffer " *p3-managed-parent*"))
        (ordinary (generate-new-buffer " *p3-ordinary-parent*"))
        (managed-child (generate-new-buffer " *p3-managed-eat-child*"))
        (ordinary-child (generate-new-buffer " *p3-ordinary-eat-child*"))
        scheduled)
    (unwind-protect
        (progn
          (with-current-buffer managed
            (eshell-mode)
            (setq-local p3/project-shell-root-value temporary-file-directory)
            (p3/project-shell-mode-setup))
          (with-current-buffer ordinary
            (eshell-mode))
          (with-current-buffer managed-child
            (setq-local eshell-parent-buffer managed))
          (with-current-buffer ordinary-child
            (setq-local eshell-parent-buffer ordinary))
          (cl-letf (((symbol-function 'process-live-p) (lambda (_process) nil))
                    ((symbol-function 'process-exit-status) (lambda (_process) 0))
                    ((symbol-function 'get-buffer-window-list)
                     (lambda (&rest _args) nil))
                    ((symbol-function 'run-at-time)
                     (lambda (_time _repeat function argument)
                       (setq scheduled (list function argument)))))
            (cl-letf (((symbol-function 'process-buffer)
                       (lambda (_process) managed-child)))
              (p3/project-shell-eat-visual-buffer-exit 'fake-process)
              (should (equal scheduled
                             (list #'p3/project-shell--kill-eat-visual-buffer
                                   managed-child))))
            (setq scheduled nil)
            (cl-letf (((symbol-function 'process-buffer)
                       (lambda (_process) ordinary-child)))
              (p3/project-shell-eat-visual-buffer-exit 'fake-process)
              (should-not scheduled))))
      (dolist (buffer (list managed ordinary managed-child ordinary-child))
        (when (buffer-live-p buffer)
          (kill-buffer buffer))))))


(ert-deftest p3-terminal-codex-eat-sync-uses-preupdate-window-set ()
  "Only windows Eat marked live before redraw are synchronized afterward."
  (should (fboundp 'p3/project-shell--codex-synchronize-scroll))
  (let ((buffer (generate-new-buffer " *p3-codex-sync*"))
        (window (selected-window))
        old-window-buffer)
    (unwind-protect
        (progn
          (setq old-window-buffer (window-buffer window))
          (set-window-buffer window buffer)
          (with-current-buffer buffer
            (let ((inhibit-read-only t))
              (insert "0123456789abcdef"))
            (setq-local eat-terminal 'dummy
                        buffer-read-only nil)
            (cl-letf (((symbol-function 'eat-term-display-cursor)
                       (lambda (_terminal) 15))
                      ((symbol-function 'pos-visible-in-window-p)
                       (lambda (&rest _) nil))
                      ((symbol-function 'recenter)
                       (lambda (&rest _) nil)))
              ;; A window Eat did not identify as live before the redraw must
              ;; remain untouched, even if its post-redraw point looks active.
              (set-window-point window 7)
              (p3/project-shell--codex-synchronize-scroll nil)
              (should (= (window-point window) 7))
              ;; A window captured as live before output follows the new cursor.
              (p3/project-shell--codex-synchronize-scroll (list window))
              (should (= (window-point window) 15))
              ;; Eat can separately request current-buffer point synchronization.
              (goto-char 4)
              (p3/project-shell--codex-synchronize-scroll '(buffer))
              (should (= (point) 15))
              ;; Read-only/Emacs mode leaves windows free for browsing.
              (setq buffer-read-only t)
              (set-window-point window 7)
              (p3/project-shell--codex-synchronize-scroll (list window))
              (should (= (window-point window) 7)))))
      (when (window-live-p window)
        (set-window-buffer window old-window-buffer))
      (when (buffer-live-p buffer)
        (kill-buffer buffer)))))

(ert-deftest p3-terminal-codex-eat-installs-sync-callback-not-update-hook ()
  "Visual Codex uses Eat's pre-redraw synchronization callback."
  (should (fboundp 'p3/project-shell--setup-codex-scroll-sync))
  (with-temp-buffer
    (setq-local eat--synchronize-scroll-function #'ignore
                eat-update-hook nil)
    (p3/project-shell--setup-codex-scroll-sync)
    (should (local-variable-p 'eat--synchronize-scroll-function))
    (should (eq eat--synchronize-scroll-function
                #'p3/project-shell--codex-synchronize-scroll))
    (should-not
     (memq #'p3/project-shell--codex-follow-output eat-update-hook))))


(provide 'p3-terminal-rich-ux-test)

;;; p3-terminal-rich-ux-test.el ends here
