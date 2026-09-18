;;; p3-terminal.el --- Project-aware Eshell helpers -*- lexical-binding: t; -*-

(require 'ring)
(require 'seq)
(require 'subr-x)
(require 'p3-project)

(defvar eat-kill-buffer-on-exit)
(defvar eat-terminal)
(defvar eat--synchronize-scroll-function)
(defvar eshell-buffer-name)
(defvar eshell-exit-hook)
(defvar eshell-hist-ignoredups)
(defvar eshell-history-append)
(defvar eshell-history-file-name)
(defvar eshell-history-ring)
(defvar eshell-input-filter-functions)
(defvar eshell-interpreter-alist)
(defvar eshell-last-command-status)
(defvar eshell-parent-buffer)
(defvar eshell-password-prompt-regexp)
(defvar eshell-prompt-function)
(defvar eshell-prompt-regexp)
(defvar eshell-save-history-on-exit)
(defvar eshell-visual-commands)

(declare-function consult-history "consult" ())
(declare-function eat-exec "eat" (buffer name command startfile switches))
(declare-function eat-mode "eat" ())
(declare-function eat-semi-char-mode "eat" (&optional arg))
(declare-function eat-send-password "eat" ())
(declare-function eat-term-display-cursor "eat" (terminal))
(declare-function eshell "eshell" (&optional arg))
(declare-function eshell-add-to-history "em-hist" ())
(declare-function eshell-find-interpreter "esh-ext"
                  (file args &optional no-examine-p))
(declare-function eshell-interactive-output-p "esh-io"
                  (&optional index handles))
(declare-function eshell-stringify-list "esh-util" (args))
(declare-function eshell-visual-command-p "em-term" (command args))
(declare-function eshell-write-history "em-hist" (&optional filename append))

(defgroup p3/terminal nil
  "Project-aware Eshell sessions."
  :group 'applications)

(defconst p3/project-shell-prompt-regexp "^[^❯\n]*❯ "
  "Prompt regexp for P3 project Eshell buffers.")

(defconst p3/project-shell-sudo-password-prompt "[P3 sudo] password: "
  "Recognizable sudo prompt used for masked password entry in Eat.")

(defconst p3/project-shell-sudo-password-tail-limit 512
  "Maximum sudo output tail retained for split password-prompt detection.")

(defconst p3/project-shell-codex-line-subcommands
  '("exec" "e" "review" "login" "logout" "mcp" "plugin"
    "app-server" "remote-control" "app" "completion" "update"
    "doctor" "sandbox" "debug" "execpolicy" "apply" "a" "queue"
    "archive" "delete" "migrate-rollouts" "unarchive" "cloud"
    "cloud-tasks" "responses-api-proxy" "tcp-tunnel" "stdio-to-uds"
    "exec-server" "features")
  "Codex subcommands whose useful output belongs in Eshell scrollback.")

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

(defun p3/project-shell-project-label (root)
  "Return the readable project label for ROOT."
  (file-name-nondirectory (directory-file-name root)))

(defun p3/project-shell-buffer-name (root)
  "Return the readable primary shell buffer name for ROOT."
  (format "*shell:%s*" (p3/project-shell-project-label root)))

(defun p3/project-shell-eat-buffer-name (root)
  "Return the readable dedicated Eat buffer name for ROOT."
  (format "*eat:%s*" (p3/project-shell-project-label root)))

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

(defun p3/project-shell-eat-supported-p ()
  "Return non-nil when P3's dedicated Eat PTY path is supported here."
  ;; Native Windows deliberately keeps ordinary Eshell/CLI support but does
  ;; not claim a PTY/TUI contract.  The Linux path is regression-tested with a
  ;; real terminal fixture and requires stty for raw terminal setup.
  (and (eq system-type 'gnu/linux)
       (executable-find "stty")))

(defun p3/project-shell--codex-visual-p (args)
  "Return non-nil when Codex ARGS describe an interactive TUI session."
  (and
   ;; Help/version output is useful shell scrollback, never a transient TUI.
   (not (seq-some (lambda (arg)
                    (member arg '("--help" "-h" "--version" "-V")))
                  args))
   ;; The top-level CLI has a small set of explicitly interactive surfaces:
   ;; its default prompt/session plus resume/fork.  Known administrative and
   ;; noninteractive subcommands should retain their ordinary Eshell output.
   (not (seq-some (lambda (arg)
                    (member arg p3/project-shell-codex-line-subcommands))
                  args))))

(defconst p3/project-shell-codex-tail-tolerance 2
  "Characters from buffer end treated as Codex's live terminal tail.")

(defun p3/project-shell--codex-synchronize-scroll (windows)
  "Synchronize Codex Eat scrolling for WINDOWS captured before a redraw.

Eat computes WINDOWS before it processes an output batch, while it still knows
which windows were following the terminal cursor.  Reuse that pre-redraw
decision rather than trying to infer intent from positions after Codex has
redrawn its TUI.  The symbol `buffer' requests current-buffer point
synchronization; window objects request window-point synchronization."
  (let ((cursor (eat-term-display-cursor eat-terminal)))
    (dolist (window windows)
      (if (eq window 'buffer)
          (goto-char cursor)
        (unless buffer-read-only
          (set-window-point window cursor)
          (cond
           ((>= cursor
                (- (point-max) p3/project-shell-codex-tail-tolerance))
            (with-selected-window window
              (goto-char cursor)
              (recenter -1)))
           ((not (pos-visible-in-window-p cursor window t))
            (with-selected-window window
              (goto-char cursor)
              (recenter)))))))))

(defun p3/project-shell--setup-codex-scroll-sync ()
  "Use Codex-specific pre-redraw scroll synchronization in this Eat buffer."
  ;; Eat intentionally computes the window set before terminal output mutates
  ;; the buffer, then dispatches it through this buffer-local callback.
  (setq-local eat--synchronize-scroll-function
              #'p3/project-shell--codex-synchronize-scroll))

(defun p3/project-shell--pacman-sync-query-p (arg)
  "Return non-nil when pacman short sync ARG is output-only."
  (and (string-match-p "\\`-S[silgpq]+\\'" arg)
       (string-match-p "[silgp]" arg)
       (not (string-match-p "[cyu]" arg))))

(defun p3/project-shell--pacman-visual-p (args)
  "Return non-nil when pacman ARGS benefit from an interactive terminal."
  (let ((query-only-long
         (seq-some (lambda (arg)
                     (member arg '("--search" "--info" "--list"
                                   "--groups" "--print")))
                   args)))
    (or
     ;; Explicit package upgrades/removals are mutating and may prompt.
     (seq-some (lambda (arg)
                 (or (string-match-p "\\`-[UR]" arg)
                     (member arg '("--upgrade" "--remove"))))
               args)
     ;; Sync operations download/install/update unless they are one of the
     ;; documented search/info/list/groups/print forms.
     (and (not query-only-long)
          (seq-some
           (lambda (arg)
             (or (equal arg "--sync")
                 (and (string-prefix-p "-S" arg)
                      (not (p3/project-shell--pacman-sync-query-p arg)))))
           args)))))

(defun p3/project-shell-eat-visual-command-p (command args)
  "Return non-nil when COMMAND ARGS should use P3's dedicated Eat buffer."
  (let ((command (file-name-nondirectory command)))
    (and (p3/project-shell-eat-supported-p)
         (eshell-interactive-output-p 'all)
         (or
          ;; Preserve Eshell's normal visual-command knowledge, but route it
          ;; through Eat only inside a managed P3 shell on a verified platform.
          (eshell-visual-command-p command args)
          (cond
           ((equal command "codex")
            (p3/project-shell--codex-visual-p args))
           ((equal command "pacman")
            (p3/project-shell--pacman-visual-p args))
           ((equal command "sudo")
            (when-let ((pacman-tail (member "pacman" args)))
              (p3/project-shell--pacman-visual-p (cdr pacman-tail)))))))))

(defun p3/project-shell--strip-sudo-prompt-options (args)
  "Return sudo option ARGS without an explicit password-prompt option."
  (let (result)
    (while args
      (let ((arg (pop args)))
        (cond
         ((member arg '("-p" "--prompt"))
          (when args (pop args)))
         ((or (string-prefix-p "--prompt=" arg)
              (and (string-prefix-p "-p" arg)
                   (> (length arg) 2))))
         (t (push arg result)))))
    (nreverse result)))

(defun p3/project-shell--sudo-password-args (args)
  "Return visual sudo ARGS with P3's recognizable password prompt."
  (if-let ((pacman-tail (member "pacman" args)))
      (let* ((prefix-count (- (length args) (length pacman-tail)))
             (prefix (seq-take args prefix-count)))
        (append (list "-p" p3/project-shell-sudo-password-prompt)
                (p3/project-shell--strip-sudo-prompt-options prefix)
                pacman-tail))
    args))

(defun p3/project-shell--eat-send-password (process)
  "Read and send one password invisibly to Eat PROCESS."
  (when (and (process-live-p process)
             (buffer-live-p (process-buffer process)))
    (with-current-buffer (process-buffer process)
      (when (derived-mode-p 'eat-mode)
        (call-interactively #'eat-send-password)))))

(defun p3/project-shell--sudo-password-filter (process output)
  "Pass OUTPUT through Eat and detect sudo password prompts for PROCESS."
  (when-let ((filter (process-get process 'p3/project-shell-original-filter)))
    (funcall filter process output))
  (when-let ((prompt (process-get process 'p3/project-shell-sudo-prompt)))
    (let* ((scan (concat (or (process-get process 'p3/project-shell-sudo-tail) "")
                         output))
           (exact-regexp (regexp-quote prompt))
           (fallback-regexp
            (process-get process 'p3/project-shell-sudo-fallback-regexp))
           (count 0))
      ;; Prefer the prompt P3 injects with sudo -p.  If PAM/sudoers ignores
      ;; that override, fall back to Eshell's standard password-prompt regexp.
      ;; The exact matches are consumed first so a normal P3 prompt cannot also
      ;; be counted by the broader fallback regexp.
      (while (string-match exact-regexp scan)
        (setq count (1+ count)
              scan (substring scan (match-end 0))))
      (let ((case-fold-search t))
        (when (and fallback-regexp
                   (string-match fallback-regexp scan))
          (setq count (1+ count)
                scan (substring scan (match-end 0)))))
      ;; Retain a bounded suffix so either recognizer can span adjacent process
      ;; filter calls without allowing long-running command output to grow here.
      (let ((keep (min (length scan)
                       p3/project-shell-sudo-password-tail-limit)))
        (process-put process 'p3/project-shell-sudo-tail
                     (substring scan (- (length scan) keep))))
      (dotimes (_ count)
        ;; Defer minibuffer input until Eat's own filter has finished handling
        ;; the prompt chunk; this avoids re-entering the terminal parser.
        (run-at-time 0 nil #'p3/project-shell--eat-send-password process)))))

(defun p3/project-shell--install-sudo-password-filter (process)
  "Install masked sudo password handling around Eat PROCESS's current filter."
  (process-put process 'p3/project-shell-original-filter (process-filter process))
  (process-put process 'p3/project-shell-sudo-prompt
               p3/project-shell-sudo-password-prompt)
  (process-put process 'p3/project-shell-sudo-fallback-regexp
               eshell-password-prompt-regexp)
  (process-put process 'p3/project-shell-sudo-tail "")
  (set-process-filter process #'p3/project-shell--sudo-password-filter))

(defun p3/project-shell-exec-visual (&rest args)
  "Run visual command ARGS in a dedicated Eat buffer for this P3 Eshell."
  (require 'eat)
  (require 'esh-ext)
  (let* (eshell-interpreter-alist
         (command-name (file-name-nondirectory (car args)))
         (codex-p (equal command-name "codex"))
         (interp (eshell-find-interpreter (car args) (cdr args)))
         (program (car interp))
         (raw-program-args
          (flatten-tree
           (eshell-stringify-list (append (cdr interp) (cdr args)))))
         (sudo-p (and (equal (file-name-nondirectory program) "sudo")
                      (member "pacman" raw-program-args)))
         (program-args (if sudo-p
                           (p3/project-shell--sudo-password-args raw-program-args)
                         raw-program-args))
         (root (p3/project-shell-root))
         (eat-buffer
          (generate-new-buffer (p3/project-shell-eat-buffer-name root)))
         (eshell-buffer (current-buffer))
         (directory default-directory))
    (condition-case err
        (save-current-buffer
          ;; Display first so Eat sizes the terminal against the window the
          ;; user will actually interact with, matching Eat's visual-command
          ;; integration without enabling its global Eshell minor mode.
          (switch-to-buffer eat-buffer)
          (setq default-directory directory)
          (eat-mode)
          (setq-local eshell-parent-buffer eshell-buffer
                      eat-kill-buffer-on-exit nil)
          (when codex-p
            (p3/project-shell--setup-codex-scroll-sync))
          (eat-exec eat-buffer program program nil program-args)
          (let ((process (get-buffer-process eat-buffer)))
            (unless (and process (process-live-p process))
              (error "Failed to invoke visual command: %s" program))
            (when sudo-p
              (p3/project-shell--install-sudo-password-filter process)))
          (eat-semi-char-mode))
      (error
       (when (buffer-live-p eat-buffer)
         (let ((kill-buffer-query-functions nil))
           (kill-buffer eat-buffer)))
       (signal (car err) (cdr err)))))
  nil)

(defun p3/project-shell--setup-visual-commands ()
  "Install P3's Eat visual-command route in this managed Eshell only."
  (require 'esh-ext)
  ;; `eshell-interpreter-alist' is buffer-local in Eshell.  Put P3's narrow
  ;; Eat route before the stock visual-command interpreter, retaining the stock
  ;; entry as a fallback (notably on native Windows, where P3 declines Eat).
  (setq-local
   eshell-interpreter-alist
   (cons (cons #'p3/project-shell-eat-visual-command-p
               #'p3/project-shell-exec-visual)
         (seq-remove
          (lambda (entry)
            (eq (car-safe entry) #'p3/project-shell-eat-visual-command-p))
          eshell-interpreter-alist))))

(defun p3/project-shell--forget-primary ()
  "Forget the current buffer if it owns its project's primary mapping."
  (when-let ((root p3/project-shell-root-value))
    (when (eq (gethash root p3/project-shell-buffers) (current-buffer))
      (remhash root p3/project-shell-buffers))))

(defun p3/project-shell-mode-setup ()
  "Apply P3 interactive UX to the current project Eshell."
  (setq-local eshell-prompt-function #'p3/project-shell-prompt
              eshell-prompt-regexp p3/project-shell-prompt-regexp
              eshell-hist-ignoredups t)
  (p3/project-shell--setup-visual-commands)
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

(defun p3/project-shell--kill-eat-visual-buffer (buffer)
  "Kill finished dedicated Eat BUFFER without querying."
  (when (buffer-live-p buffer)
    (let ((kill-buffer-query-functions nil))
      (kill-buffer buffer))))

(defun p3/project-shell-eat-visual-buffer-exit (process)
  "Return a successful P3 Eat visual PROCESS to its parent project Eshell.

Eat calls this from the public `eat-exit-hook'.  Only dedicated Eat buffers
whose `eshell-parent-buffer' is a managed P3 project shell are affected.
Failed terminal commands stay visible for inspection; unrelated Eat sessions
keep their normal lifecycle."
  (let ((child (process-buffer process)))
    (when (and child
               (buffer-live-p child)
               (not (process-live-p process))
               (zerop (process-exit-status process)))
      (with-current-buffer child
        (when (and (boundp 'eshell-parent-buffer)
                   (p3/project-shell-buffer-p eshell-parent-buffer))
          (let ((parent eshell-parent-buffer))
            (dolist (window (get-buffer-window-list child nil t))
              (set-window-buffer window parent))
            ;; `eat-exit-hook' runs just before Eat deletes the process.  Defer
            ;; buffer deletion one event turn so Eat can finish its sentinel
            ;; cleanup without operating on a killed current buffer.
            (run-at-time 0 nil
                         #'p3/project-shell--kill-eat-visual-buffer child)))))))

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
                     (if (get-buffer base-name)
                         (generate-new-buffer-name base-name)
                       base-name)))
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
