;;; p3-terminal.el --- Project-aware Eshell helpers -*- lexical-binding: t; -*-

(require 'ring)
(require 'seq)
(require 'subr-x)
(require 'p3-project)

(defvar eshell-buffer-name)
(defvar eshell-exit-hook)
(defvar eshell-hist-ignoredups)
(defvar eshell-history-append)
(defvar eshell-history-file-name)
(defvar eshell-history-ring)
(defvar eshell-input-filter-functions)
(defvar eshell-last-command-status)
(defvar eshell-prompt-function)
(defvar eshell-prompt-regexp)
(defvar eshell-save-history-on-exit)
(defvar eshell-visual-commands)
(defvar eshell-visual-options)
(defvar eshell-visual-subcommands)

(declare-function consult-history "consult" ())
(declare-function eshell "eshell" (&optional arg))
(declare-function eshell-add-to-history "em-hist" ())
(declare-function eshell-write-history "em-hist" (&optional filename append))

(defgroup p3/terminal nil
  "Project-aware Eshell sessions."
  :group 'applications)

(defconst p3/project-shell-prompt-regexp "^[^❯\n]*❯ "
  "Prompt regexp for P3 project Eshell buffers.")

(defvar p3/project-shell-buffers (make-hash-table :test #'equal)
  "Map local project roots to their primary P3 shell buffers.")

(defvar-local p3/project-shell-root-value nil
  "Local root associated with the current P3 shell buffer.")

(defun p3/project-shell-root ()
  "Return the canonical local root for the current project shell context."
  (let ((root (or p3/project-shell-root-value
                  (p3/project-root t)
                  default-directory)))
    (when (file-remote-p root)
      (user-error "Project shell requires a local project or directory"))
    (or (p3/project-normalize-root root)
        (user-error "Project shell root does not exist: %s" root))))

(defun p3/project-shell-buffer-name (root)
  "Return a stable primary shell buffer name for ROOT."
  (format "*shell:%s:%s*"
          (file-name-nondirectory (directory-file-name root))
          (substring (secure-hash 'sha1 root) 0 6)))

(defun p3/project-shell-extra-buffer-name (root)
  "Return an unused buffer name for an explicit extra shell at ROOT."
  (let ((primary-name (p3/project-shell-buffer-name root)))
    (generate-new-buffer-name
     (concat (substring primary-name 0 -1) ":extra*"))))

(defun p3/project-shell-prompt ()
  "Return the prompt for the current P3 project Eshell."
  (let* ((root p3/project-shell-root-value)
         (directory (file-name-as-directory
                     (expand-file-name default-directory)))
         (relative (and root
                        (file-in-directory-p directory root)
                        (file-relative-name directory root)))
         (root-label (and root
                          (file-name-nondirectory
                           (directory-file-name root))))
         (label (if relative
                    (concat root-label
                            (unless (equal relative "./")
                              (concat "/"
                                      (directory-file-name relative))))
                  (abbreviate-file-name directory)))
         (ok (or (not (boundp 'eshell-last-command-status))
                 (null eshell-last-command-status)
                 (zerop eshell-last-command-status))))
    (concat (propertize label 'face 'eshell-prompt)
            " "
            (propertize "❯" 'face (if ok 'success 'error))
            " ")))

(defun p3/project-shell--history-head ()
  "Return the newest Eshell history entry, or nil when history is empty."
  (when (and (boundp 'eshell-history-ring)
             (ring-p eshell-history-ring)
             (not (ring-empty-p eshell-history-ring)))
    (ring-ref eshell-history-ring 0)))

(defun p3/project-shell--write-latest-history-compat ()
  "Append only the newest Eshell history entry to the shared history file."
  (when-let ((latest-entry (p3/project-shell--history-head)))
    (let ((latest (make-ring 1)))
      (ring-insert latest latest-entry)
      (let ((eshell-history-ring latest))
        (eshell-write-history eshell-history-file-name t)))))

(defun p3/project-shell--append-history-compat ()
  "Add current input to history and append it only when Eshell accepted it."
  (let ((before (p3/project-shell--history-head)))
    (eshell-add-to-history)
    (let ((after (p3/project-shell--history-head)))
      (unless (equal before after)
        (p3/project-shell--write-latest-history-compat)))))

(defun p3/project-shell--setup-history-append-compat ()
  "Provide concurrent-safe append-only Eshell history on Emacs 29."
  ;; Emacs 29 always installs `eshell-write-history' on `eshell-exit-hook';
  ;; that writer replaces the complete file and can erase commands appended by
  ;; another live project shell.  P3 persists accepted commands incrementally,
  ;; so suppress both that overwrite and the separate Emacs-exit save path.
  (setq-local eshell-save-history-on-exit nil)
  (remove-hook 'eshell-exit-hook #'eshell-write-history t)
  ;; Replace the stock history-adder rather than adding a second hook after it.
  ;; This lets us know whether the current input was actually accepted (blank
  ;; input and consecutive duplicates must not append the previous command).
  (remove-hook 'eshell-input-filter-functions #'eshell-add-to-history t)
  (add-hook 'eshell-input-filter-functions
            #'p3/project-shell--append-history-compat t t))

(defun p3/project-shell--forget-primary ()
  "Forget the current buffer if it owns its project's primary mapping."
  (when-let ((root p3/project-shell-root-value))
    (when (eq (gethash root p3/project-shell-buffers) (current-buffer))
      (remhash root p3/project-shell-buffers))))

(defun p3/project-shell-mode-setup ()
  "Apply P3 interactive UX to the current project Eshell."
  (setq-local eshell-prompt-function #'p3/project-shell-prompt
              eshell-prompt-regexp p3/project-shell-prompt-regexp
              eshell-hist-ignoredups t
              ;; Eat owns terminal-native programs in managed P3 shells.  The
              ;; stock Eshell visual-command route would divert these programs
              ;; into a separate term buffer before Eat can handle them.
              eshell-visual-commands nil
              eshell-visual-subcommands nil
              eshell-visual-options nil)
  (local-set-key (kbd "C-r") #'consult-history)
  (add-hook 'kill-buffer-hook #'p3/project-shell--forget-primary nil t)
  (if (boundp 'eshell-history-append)
      (setq-local eshell-history-append t)
    (p3/project-shell--setup-history-append-compat)))

(defun p3/project-shell--start (name root)
  "Start a managed Eshell named NAME at ROOT and return its buffer."
  (require 'eshell)
  ;; Bind project identity and prompt variables before `eshell-mode' initializes
  ;; so the very first prompt already uses the project-relative P3 label.  The
  ;; buffer-local setup below keeps those settings for subsequent prompts.
  (let ((default-directory root)
        (p3/project-shell-root-value root)
        (eshell-buffer-name name)
        (eshell-prompt-function #'p3/project-shell-prompt)
        (eshell-prompt-regexp p3/project-shell-prompt-regexp)
        (eshell-hist-ignoredups t))
    (let ((buffer (save-window-excursion (eshell))))
      (with-current-buffer buffer
        (setq-local p3/project-shell-root-value root)
        (p3/project-shell-mode-setup))
      buffer)))

(defun p3/project-shell-buffer-p (buffer)
  "Return non-nil when BUFFER is a managed P3 project Eshell."
  (and (buffer-live-p buffer)
       (buffer-local-value 'p3/project-shell-root-value buffer)
       (with-current-buffer buffer
         (derived-mode-p 'eshell-mode))))

(defun p3/project-shell-live-p (buffer)
  "Return non-nil when BUFFER is a live managed P3 project Eshell."
  (p3/project-shell-buffer-p buffer))

(defun p3/project-shell-buffer (&optional new-session)
  "Return the project shell, creating a NEW-SESSION when requested."
  (let* ((root (p3/project-shell-root))
         (base-name (p3/project-shell-buffer-name root))
         (primary (and (not new-session)
                       (gethash root p3/project-shell-buffers))))
    (when (and primary (not (p3/project-shell-live-p primary)))
      (remhash root p3/project-shell-buffers)
      (setq primary nil))
    (if (p3/project-shell-live-p primary)
        primary
      (let* ((name (if new-session
                       (p3/project-shell-extra-buffer-name root)
                     base-name))
             (buffer
              (let ((default-directory root))
                (p3/project-shell--start name root))))
        (with-current-buffer buffer
          (setq-local p3/project-shell-root-value root))
        (unless new-session
          (puthash root buffer p3/project-shell-buffers))
        buffer))))

(defun p3/project-shell-buffers ()
  "Return all live P3 project Eshell buffers."
  (seq-filter #'p3/project-shell-live-p (buffer-list)))

(defun p3/project-shell-read-buffer ()
  "Prompt for and return a live P3 project shell buffer."
  (let ((buffers (p3/project-shell-buffers)))
    (unless buffers
      (user-error "There are no live project shell sessions"))
    (get-buffer
     (completing-read "Project shell: " (mapcar #'buffer-name buffers) nil t))))

(defun p3/project-shell (&optional new-session)
  "Switch the current window to its project Eshell.
With a prefix argument, create a NEW-SESSION.  When already in a live P3
project shell, switch back to the previous buffer instead of hiding or deleting
the window."
  (interactive "P")
  (if (and (p3/project-shell-live-p (current-buffer))
           (not new-session))
      (switch-to-prev-buffer)
    (switch-to-buffer (p3/project-shell-buffer new-session))))

(defun p3/project-shell-new ()
  "Create another Eshell for the current project in this window."
  (interactive)
  (switch-to-buffer (p3/project-shell-buffer t)))

(defun p3/project-shell-switch ()
  "Switch the current window to an existing P3 project shell."
  (interactive)
  (switch-to-buffer (p3/project-shell-read-buffer)))

(defun p3/project-shell-other-window (&optional new-session)
  "Open the project Eshell in another ordinary window.
With a prefix argument, create a NEW-SESSION there."
  (interactive "P")
  (switch-to-buffer-other-window (p3/project-shell-buffer new-session)))

(defun p3/project-shell-rename (name)
  "Rename the current P3 project shell to NAME."
  (interactive "sProject shell name: ")
  (unless (p3/project-shell-buffer-p (current-buffer))
    (user-error "The current buffer is not a P3 project shell"))
  (rename-buffer (format "*shell:%s*" name) t))

(defun p3/project-shell-kill ()
  "Kill the current P3 project shell, or prompt for one to kill."
  (interactive)
  (kill-buffer
   (if (p3/project-shell-buffer-p (current-buffer))
       (current-buffer)
     (p3/project-shell-read-buffer))))

(defvar-keymap p3/project-shell-command-map
  :doc "Commands for project-aware Eshell sessions."
  "t" #'p3/project-shell
  "n" #'p3/project-shell-new
  "s" #'p3/project-shell-switch
  "o" #'p3/project-shell-other-window
  "r" #'p3/project-shell-rename
  "k" #'p3/project-shell-kill)

(provide 'p3-terminal)

;;; p3-terminal.el ends here
