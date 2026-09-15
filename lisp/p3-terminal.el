;;; p3-terminal.el --- Project-aware Bash shell helpers -*- lexical-binding: t; -*-

(require 'seq)
(require 'subr-x)
(require 'shell)
(require 'p3-platform)
(require 'p3-project)

(defvar explicit-bash.exe-args)

(defgroup p3/terminal nil
  "Project-aware Bash shell sessions."
  :group 'applications)

(defconst p3/project-shell-prompt-pattern
  "^[^❯\n]*❯ *"
  "Prompt regexp shared by P3 project shells on all platforms.")

(defconst p3/project-shell-prompt-init-command
  (concat
   ;; `shell-eval-command' sends this directly to Bash.  Disable history before
   ;; the bootstrap body, remove that first control line, and restore the user's
   ;; prior history state at the end so P3 internals never pollute C-r history.
   "if shopt -qo history; then __p3_history_was_on=1; set +o history; history -d $(($HISTCMD - 1)); else __p3_history_was_on=0; fi\n"
   ;; P3 explicitly supports concurrent project shells sharing one HISTFILE.
   ;; Append session history on exit instead of letting later exits overwrite it.
   "shopt -s histappend\n"
   "if [ \"${TERM-}\" != dumb ] && command -v starship >/dev/null 2>&1; then\n"
   "  if ! declare -F starship_precmd >/dev/null 2>&1; then\n"
   "    if __p3_starship_init=\"$(starship init bash --print-full-init)\"; then\n"
   "      eval -- \"$__p3_starship_init\" || PS1='\\w ❯ '\n"
   "    else\n"
   "      PS1='\\w ❯ '\n"
   "    fi\n"
   "    unset __p3_starship_init\n"
   "  fi\n"
   "else\n"
   "  PS1='\\w ❯ '\n"
   "fi\n"
   "if [ \"$__p3_history_was_on\" = 1 ]; then unset __p3_history_was_on; set -o history; else unset __p3_history_was_on; fi\n")
  "Bootstrap shared Bash history and the P3 prompt without history noise.")

(defvar p3/project-shell-buffers (make-hash-table :test #'equal)
  "Map local project roots to their primary P3 shell buffers.")

(defvar-local p3/project-shell-root-value nil
  "Local root associated with the current P3 shell buffer.")

(defun p3/project-shell-starship-config ()
  "Return the tracked Starship configuration used by P3 project shells."
  (let* ((library (or (locate-library "p3-terminal")
                      (user-error "Cannot locate p3-terminal library")))
         (configuration-root
          (file-name-directory
           (directory-file-name (file-name-directory library))))
         (config
          (expand-file-name "templates/p3-starship.toml" configuration-root)))
    (unless (file-readable-p config)
      (user-error "Project shell Starship configuration is unreadable: %s" config))
    config))

(defun p3/project-shell-rich-terminfo-p ()
  "Return non-nil when `dumb-emacs-ansi' is available to local processes."
  (when-let ((infocmp (and (eq system-type 'gnu/linux)
                           (executable-find "infocmp"))))
    (eq 0 (ignore-errors
            (call-process infocmp nil nil nil "dumb-emacs-ansi")))))

(defun p3/project-shell-comint-terminal ()
  "Return the safest useful Comint terminal type for a P3 project shell."
  (if (and (eq system-type 'gnu/linux)
           (equal comint-terminfo-terminal "dumb")
           (p3/project-shell-rich-terminfo-p))
      "dumb-emacs-ansi"
    comint-terminfo-terminal))

(defun p3/project-shell-root ()
  "Return the canonical local root for the current project shell context."
  (let ((root (or p3/project-shell-root-value
                  (p3/project-root)
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

(defun p3/project-shell-mode-setup ()
  "Apply the shared interactive UX to the current P3 project shell."
  (setq-local comint-input-ignoredups t)
  (local-set-key (kbd "C-r") #'comint-history-isearch-backward)
  ;; Rtools and Git-for-Windows Bash are MSYS shells.  Keep directory resync
  ;; reliable on Emacs 29 as well as versions that detect this automatically.
  (when (p3/windows-p)
    (setq-local shell-dirstack-query "command pwd -W")))

(defun p3/project-shell--start (name root)
  "Start the platform Bash in buffer NAME at ROOT and return the buffer."
  (let* ((buffer (get-buffer-create name))
         (bash-program (p3/platform-bash-program))
         (bash-directory (file-name-directory bash-program)))
    (with-current-buffer buffer
      (setq default-directory root))
    (let ((default-directory root)
          ;; Preserve the real executable basename so Shell mode can recognize
          ;; native-Windows MSYS Bash rather than spoofing it as GNU/Linux Bash.
          (explicit-shell-file-name bash-program)
          (exec-path (cons bash-directory exec-path))
          (explicit-bash-args '("--noediting" "-i"))
          (explicit-bash.exe-args '("--noediting" "-i"))
          ;; Starship needs something richer than TERM=dumb, but terminfo-aware
          ;; programs can malfunction if TERM names an entry that is not installed.
          (comint-terminfo-terminal (p3/project-shell-comint-terminal))
          (shell-fontify-input-enable t)
          (shell-highlight-undef-enable t)
          (shell-prompt-pattern p3/project-shell-prompt-pattern)
          (process-environment (copy-sequence process-environment)))
      (setenv "STARSHIP_CONFIG" (p3/project-shell-starship-config))
      ;; Emacs 29 derives Shell history from HISTFILE, while Emacs 30 can also
      ;; use `shell-history-file-name'.  Bash does not expand a literal `~'
      ;; inherited through the environment, so supply the native absolute path.
      (when (string-empty-p (or (getenv "HISTFILE") ""))
        (setenv "HISTFILE" (expand-file-name "~/.bash_history")))
      (when (p3/windows-p)
        (setenv "CHERE_INVOKING" "1"))
      (save-window-excursion
        (shell name)))
    (setq buffer
          (or (get-buffer name)
              (user-error "Bash shell did not create buffer %s" name)))
    (with-current-buffer buffer
      (when (derived-mode-p 'shell-mode)
        (p3/project-shell-mode-setup)
        (shell-eval-command p3/project-shell-prompt-init-command)))
    buffer))

(defun p3/project-shell-buffer-p (buffer)
  "Return non-nil when BUFFER is a P3 project shell buffer."
  (and (buffer-live-p buffer)
       (buffer-local-value 'p3/project-shell-root-value buffer)))

(defun p3/project-shell-live-p (buffer)
  "Return non-nil when BUFFER is a P3 project shell with a live process."
  (and (p3/project-shell-buffer-p buffer)
       (when-let ((process (get-buffer-process buffer)))
         (process-live-p process))))

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
  "Return all P3 project shell buffers with live Bash processes."
  (seq-filter #'p3/project-shell-live-p (buffer-list)))

(defun p3/project-shell-read-buffer ()
  "Prompt for and return a live P3 project shell buffer."
  (let ((buffers (p3/project-shell-buffers)))
    (unless buffers
      (user-error "There are no live project shell sessions"))
    (get-buffer
     (completing-read "Project shell: " (mapcar #'buffer-name buffers) nil t))))

(defun p3/project-shell (&optional new-session)
  "Switch the current window to its project Bash shell.
With a prefix argument, create a NEW-SESSION.  When already in a live P3
project shell, switch back to the previous buffer instead of hiding or deleting
the window."
  (interactive "P")
  (if (and (p3/project-shell-live-p (current-buffer))
           (not new-session))
      (switch-to-prev-buffer)
    (switch-to-buffer (p3/project-shell-buffer new-session))))

(defun p3/project-shell-new ()
  "Create another Bash shell for the current project in this window."
  (interactive)
  (switch-to-buffer (p3/project-shell-buffer t)))

(defun p3/project-shell-switch ()
  "Switch the current window to an existing P3 project shell."
  (interactive)
  (switch-to-buffer (p3/project-shell-read-buffer)))

(defun p3/project-shell-other-window (&optional new-session)
  "Open the project Bash shell in another ordinary window.
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
  "Kill the current P3 project shell, or prompt for a live one to kill."
  (interactive)
  (kill-buffer
   (if (p3/project-shell-buffer-p (current-buffer))
       (current-buffer)
     (p3/project-shell-read-buffer))))

(defvar-keymap p3/project-shell-command-map
  :doc "Commands for project-aware Bash shell sessions."
  "t" #'p3/project-shell
  "n" #'p3/project-shell-new
  "s" #'p3/project-shell-switch
  "o" #'p3/project-shell-other-window
  "r" #'p3/project-shell-rename
  "k" #'p3/project-shell-kill)

(provide 'p3-terminal)

;;; p3-terminal.el ends here
