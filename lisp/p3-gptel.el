;;; p3-gptel.el --- Thin GPTel project and task workflow -*- lexical-binding: t; -*-

(require 'project)
(require 'seq)
(require 'subr-x)
(require 'p3-git)
(require 'p3-project)

(defvar gptel-context nil)
(defvar gptel-mode nil)
(defvar gptel-use-context nil)
(defvar gptel--openai-oauth-token-file)

(declare-function gptel "gptel" (name &optional key initial interactivep))
(declare-function gptel-menu "gptel-transient" ())
(declare-function gptel-add "gptel-context" (&optional arg confirm))
(declare-function gptel-add-file "gptel-context" (path))
(declare-function gptel-make-ollama "gptel-ollama" (name &rest args))
(declare-function gptel-openai-oauth-login "gptel-openai-oauth" (&optional backend method))
(declare-function gptel-request "gptel" (prompt &rest args))
(declare-function diff-mode "diff-mode" ())

;; GPTel autoloads the public rewrite command, but P3 deliberately calls the
;; native rewrite suffix directly so fixed cut-out tasks need no extra prompt.
;; Install the same lazy-load boundary for that entry point explicitly.
(autoload 'gptel--suffix-rewrite "gptel-rewrite" nil nil)

(defconst p3/gptel-task-prompts
  '((refactor . "Refactor the selected code while preserving its behavior. Return only the final replacement code.")
    (document . "Add concise documentation appropriate for the selected code and language while preserving behavior. Return only the final replacement text.")
    (tests . "Write focused tests for the selected code. Return the test code and no surrounding commentary.")
    (explain . "Explain the selected code clearly and concisely, including important behavior and non-obvious assumptions.")
    (review . "Review the selected code critically. Identify correctness, maintainability, and robustness issues without modifying the source."))
  "Instructions for P3's small set of GPTel cut-out tasks.")

(defvar-local p3/gptel-project-root nil
  "Project root currently associated with this P3-started GPTel chat.")

(defvar-local p3/gptel-git-diff-root nil
  "Repository root captured by this P3 Git-diff snapshot buffer.")

(defun p3/gptel-sensitive-path-p (path)
  "Return non-nil when PATH has an obvious credential-like file name.

This is deliberately a narrow path-based guard for P3 convenience commands,
not a general secret-content scanner."
  (when path
    (let ((case-fold-search t)
          (name (file-name-nondirectory path)))
      (string-match-p
       "\\`\\(?:\\.env\\|secrets?\\|credentials?\\)\\(?:\\'\\|[._-]\\)"
       name))))

(defun p3/gptel-sensitive-buffer-p ()
  "Return non-nil when the current buffer visits a sensitive-looking path."
  (and buffer-file-name
       (p3/gptel-sensitive-path-p buffer-file-name)))

(defun p3/gptel--region-text ()
  "Return the active region text or signal a user error."
  (unless (use-region-p)
    (user-error "Select a region first"))
  (when (p3/gptel-sensitive-buffer-p)
    (user-error "Refusing to send content from a sensitive-looking file"))
  (buffer-substring-no-properties (region-beginning) (region-end)))

(defun p3/gptel-register-ollama (models &optional host)
  "Register an Ollama backend for MODELS at HOST without probing the server.

When MODELS is nil, do nothing.  This keeps Ollama an explicitly configured
optional backend rather than guessing which local models are installed."
  (when models
    (gptel-make-ollama
      "Ollama"
      :host (or host "localhost:11434")
      :models models
      :stream t)))

(defun p3/gptel-chatgpt-oauth-available-p ()
  "Return non-nil when the installed GPTel provides ChatGPT OAuth support."
  (require 'gptel-openai-oauth nil t))

(defun p3/gptel--chatgpt-token-file-p (file)
  "Return non-nil when FILE is GPTel's ChatGPT OAuth token file."
  (and (stringp file)
       (boundp 'gptel--openai-oauth-token-file)
       (stringp gptel--openai-oauth-token-file)
       (equal (expand-file-name file)
              (expand-file-name gptel--openai-oauth-token-file))))

(defun p3/gptel-secure-openai-oauth-token-write (write-token file token)
  "Call WRITE-TOKEN for FILE and TOKEN with owner-only Unix permissions.

Only GPTel's ChatGPT OAuth token file is affected.  Windows keeps GPTel's
native file handling because POSIX mode bits are not an access-control
boundary there."
  (if (and (not (eq system-type 'windows-nt))
           (p3/gptel--chatgpt-token-file-p file))
      (let ((old-modes (default-file-modes)))
        (unwind-protect
            (progn
              (set-default-file-modes #o600)
              (prog1 (funcall write-token file token)
                (when (file-exists-p file)
                  (set-file-modes file #o600))))
          (set-default-file-modes old-modes)))
    (funcall write-token file token)))

(defun p3/gptel-secure-openai-oauth-token-storage ()
  "Harden GPTel's persisted ChatGPT OAuth token on Unix-like systems."
  (when (and (not (eq system-type 'windows-nt))
             (boundp 'gptel--openai-oauth-token-file)
             (stringp gptel--openai-oauth-token-file)
             (file-exists-p gptel--openai-oauth-token-file))
    (set-file-modes gptel--openai-oauth-token-file #o600))
  (when (and (fboundp 'gptel-oauth--write-token)
             (not (advice-member-p
                   #'p3/gptel-secure-openai-oauth-token-write
                   #'gptel-oauth--write-token)))
    (advice-add #'gptel-oauth--write-token :around
                #'p3/gptel-secure-openai-oauth-token-write)))

(defun p3/gptel-chatgpt-login ()
  "Authenticate GPTel with the registered ChatGPT Plus/Pro backend."
  (interactive)
  (unless (p3/gptel-chatgpt-oauth-available-p)
    (user-error
     "Installed GPTel lacks ChatGPT OAuth support; upgrade GPTel and reload the config"))
  (p3/gptel-secure-openai-oauth-token-storage)
  (call-interactively #'gptel-openai-oauth-login))

(defun p3/gptel--rewrite-task (task)
  "Run rewrite TASK on the active region with clean task-local context."
  (p3/gptel--region-text)
  (let ((gptel-context nil)
        (gptel-use-context nil))
    (gptel--suffix-rewrite (alist-get task p3/gptel-task-prompts))))

(defun p3/gptel-refactor-region ()
  "Propose a native GPTel rewrite that refactors the selected region."
  (interactive)
  (p3/gptel--rewrite-task 'refactor))

(defun p3/gptel-document-region ()
  "Propose a native GPTel rewrite that documents the selected region."
  (interactive)
  (p3/gptel--rewrite-task 'document))

(defun p3/gptel-task-response-callback (response info)
  "Display a non-destructive cut-out task RESPONSE using INFO on failure."
  (cond
   ((stringp response)
    (let ((buffer (get-buffer-create "*GPTel Task Response*")))
      (with-current-buffer buffer
        (let ((inhibit-read-only t))
          (erase-buffer)
          (insert response)
          (goto-char (point-min))
          (special-mode)))
      (display-buffer buffer)))
   ((null response)
    (message "GPTel task failed: %s"
             (or (plist-get info :status) "unknown error")))
   ((eq response 'abort)
    (message "GPTel task aborted"))))

(defun p3/gptel--request-region-task (task)
  "Send non-destructive TASK for the active region with clean context."
  (let ((text (p3/gptel--region-text))
        (instruction (alist-get task p3/gptel-task-prompts)))
    (let ((gptel-context nil)
          (gptel-use-context nil))
      (gptel-request
       (format "%s\n\nLanguage/mode: %s\n\nCode:\n%s"
               instruction major-mode text)
       :stream nil
       :callback #'p3/gptel-task-response-callback))))

(defun p3/gptel-write-tests ()
  "Ask GPTel for tests for the selected region without modifying source."
  (interactive)
  (p3/gptel--request-region-task 'tests))

(defun p3/gptel-explain-region ()
  "Ask GPTel to explain the selected region without modifying source."
  (interactive)
  (p3/gptel--request-region-task 'explain))

(defun p3/gptel-review-region ()
  "Ask GPTel to review the selected region without modifying source."
  (interactive)
  (p3/gptel--request-region-task 'review))

(defun p3/gptel--canonical-directory (directory)
  "Return stable local identity for DIRECTORY, preserving remote paths."
  (if (file-remote-p directory)
      (file-name-as-directory directory)
    (or (p3/project-normalize-root directory)
        (file-name-as-directory (expand-file-name directory)))))

(defun p3/gptel-project-chat ()
  "Start or select a GPTel chat scoped to the current project directory.

GPTel continues to own chat naming, persistence, backend/model state, and
conversation resumption.  P3 only records the caller's `project.el' directory
and ensures the selected chat has its own explicit context list.  Reusing a
P3-started chat from another project clears its attached context rather than
silently carrying project material across roots."
  (interactive)
  (let* ((directory
          (p3/gptel--canonical-directory
           (or (p3/project-root) default-directory)))
         (chat (call-interactively #'gptel)))
    (unless (buffer-live-p chat)
      (user-error "GPTel did not return a live chat buffer"))
    (with-current-buffer chat
      ;; A project chat should never inherit process-wide context merely because
      ;; another buffer used GPTel.  Preserve context only when returning to a
      ;; chat already associated with the same project root.
      (unless (and (local-variable-p 'gptel-context)
                   (equal p3/gptel-project-root directory))
        (setq-local gptel-context nil))
      (setq-local default-directory directory
                  p3/gptel-project-root directory))
    chat))

(defun p3/gptel--current-project-root ()
  "Return the canonical current `project.el' root, or nil."
  (when-let ((root (p3/project-root)))
    (p3/gptel--canonical-directory root)))

(defun p3/gptel--project-chats (root)
  "Return live P3-started GPTel chats associated with ROOT."
  (seq-filter
   (lambda (buffer)
     (and (buffer-live-p buffer)
          (buffer-local-value 'gptel-mode buffer)
          (equal (buffer-local-value 'p3/gptel-project-root buffer) root)))
   (buffer-list)))

(defun p3/gptel--choose-project-chat (root)
  "Return a P3 GPTel chat for ROOT, prompting only when ambiguous."
  (let ((chats (p3/gptel--project-chats root)))
    (cond
     ((null chats)
      (user-error "No project GPTel chat; start one with C-c g g"))
     ((null (cdr chats))
      (car chats))
     (t
      (get-buffer
       (completing-read
        "GPTel project chat: "
        (mapcar #'buffer-name chats) nil t))))))

(defun p3/gptel-add-context (&optional arg)
  "Add or remove GPTel context for the relevant project chat.

Inside a GPTel chat, delegate directly to native `gptel-add'.  From an ordinary
project buffer, run native `gptel-add' in the source buffer while binding its
context to a matching P3 project chat, then save the resulting context back to
that chat.  This preserves GPTel's native region/buffer semantics without
mutating the process-wide default context or introducing a separate context
store.  Outside a project, retain native GPTel behavior.

P3's path-based safety guard applies when adding context from the current
source buffer.  Native GPTel commands remain available as an explicit escape
hatch."
  (interactive "P")
  (let ((root (p3/gptel--current-project-root)))
    (cond
     ((bound-and-true-p gptel-mode)
      (gptel-add arg t))
     ((null root)
      (gptel-add arg t))
     (t
      (when (and (not (and arg (< (prefix-numeric-value arg) 0)))
                 (p3/gptel-sensitive-buffer-p))
        (user-error "Refusing to add content from a sensitive-looking file"))
      (let ((chat (p3/gptel--choose-project-chat root))
            new-context)
        (let ((gptel-context
               (copy-tree (buffer-local-value 'gptel-context chat))))
          (gptel-add arg t)
          (setq new-context gptel-context))
        (with-current-buffer chat
          (setq-local gptel-context new-context))
        (message "GPTel context updated for %s" (buffer-name chat)))))))

(defun p3/gptel-git-root (&optional directory)
  "Return the Git root containing DIRECTORY or `default-directory'."
  (file-name-as-directory
   (string-trim
    (p3/git-run (or directory default-directory)
                "rev-parse" "--show-toplevel"))))

(defun p3/gptel-git-diff-snapshot (&optional directory)
  "Return tracked staged and unstaged changes against HEAD in DIRECTORY.

Untracked files are excluded.  Rename detection is disabled so both old and
new paths remain explicit for the sensitive-path guard."
  (let ((root (p3/gptel-git-root directory)))
    (p3/git-run root "diff" "--no-renames" "HEAD" "--")))

(defun p3/gptel--git-diff-sensitive-paths (directory)
  "Return sensitive-looking tracked paths changed in DIRECTORY."
  (seq-filter
   #'p3/gptel-sensitive-path-p
   (split-string
    (p3/git-run directory "diff" "--no-renames" "--name-only" "HEAD" "--")
    "\n" t)))

(defun p3/gptel--context-buffer (entry)
  "Return the buffer represented by GPTel context ENTRY, if any."
  (cond
   ((bufferp entry) entry)
   ((bufferp (car-safe entry)) (car entry))))

(defun p3/gptel--git-diff-context-p (entry root)
  "Return non-nil when context ENTRY is P3's Git snapshot for ROOT."
  (when-let ((buffer (p3/gptel--context-buffer entry)))
    (and (buffer-live-p buffer)
         (equal (buffer-local-value 'p3/gptel-git-diff-root buffer) root))))

(defun p3/gptel--ensure-local-context ()
  "Ensure GPTel context mutations in the current buffer remain local."
  (unless (local-variable-p 'gptel-context)
    (setq-local gptel-context (copy-tree gptel-context))))

(defun p3/gptel-add-git-diff ()
  "Add or explicitly refresh this chat's current repository Git diff.

The attachment is an immutable snapshot of staged and unstaged tracked changes
against HEAD; untracked files are excluded.  Re-running this command creates a
new snapshot and replaces only this chat's previous P3 snapshot for the same
repository.  Existing snapshots are never rewritten in place."
  (interactive)
  (unless (bound-and-true-p gptel-mode)
    (user-error "Add Git diff from the target GPTel chat buffer"))
  (let* ((root (p3/gptel-git-root))
         (sensitive (p3/gptel--git-diff-sensitive-paths root)))
    (when sensitive
      (user-error "Refusing to add diff containing sensitive-looking path(s): %s"
                  (string-join sensitive ", ")))
    (let ((diff (p3/gptel-git-diff-snapshot root)))
      (when (string-empty-p diff)
        (user-error "No tracked changes against HEAD"))
      (let* ((project-name
              (file-name-nondirectory (directory-file-name root)))
             ;; Every refresh gets a distinct buffer object.  GPTel context is
             ;; live, so reusing and rewriting a buffer would silently mutate
             ;; evidence already attached to another conversation.
             (buffer
              (generate-new-buffer
               (format " *GPTel Git Diff: %s*" project-name))))
        (with-current-buffer buffer
          (insert diff)
          (goto-char (point-min))
          (when (fboundp 'diff-mode)
            (diff-mode))
          (setq-local default-directory root
                      p3/gptel-git-diff-root root)
          (setq buffer-read-only t)
          (set-buffer-modified-p nil))
        (p3/gptel--ensure-local-context)
        (setq gptel-context
              (seq-remove
               (lambda (entry)
                 (p3/gptel--git-diff-context-p entry root))
               gptel-context))
        (push buffer gptel-context)
        (message "GPTel context refreshed from tracked Git diff: %s" project-name)
        buffer))))

(defvar p3/gptel-command-map nil
  "Prefix map for GPTel project context and cut-out tasks.")

(setq p3/gptel-command-map
      (let ((map (make-sparse-keymap)))
        (define-key map (kbd "g") #'p3/gptel-project-chat)
        (define-key map (kbd "l") #'p3/gptel-chatgpt-login)
        (define-key map (kbd "m") #'gptel-menu)
        (define-key map (kbd "a") #'p3/gptel-add-context)
        (define-key map (kbd "f") #'gptel-add-file)
        (define-key map (kbd "D") #'p3/gptel-add-git-diff)
        (define-key map (kbd "r") #'p3/gptel-refactor-region)
        (define-key map (kbd "d") #'p3/gptel-document-region)
        (define-key map (kbd "t") #'p3/gptel-write-tests)
        (define-key map (kbd "e") #'p3/gptel-explain-region)
        (define-key map (kbd "v") #'p3/gptel-review-region)
        map))

(defun p3/gptel-setup ()
  "Install the global GPTel workflow prefix."
  (define-key global-map (kbd "C-c g") p3/gptel-command-map))

(provide 'p3-gptel)

;;; p3-gptel.el ends here