;;; p3-gptel.el --- Thin GPTel project and task workflow -*- lexical-binding: t; -*-

(require 'seq)
(require 'subr-x)
(require 'p3-git)

(defvar gptel-context nil)
(defvar gptel-use-context nil)

(declare-function gptel "gptel" (&optional name initial major-mode directory))
(declare-function gptel-menu "gptel-transient" ())
(declare-function gptel-add "gptel-context" (&optional arg confirm))
(declare-function gptel-add-file "gptel-context" (path))
(declare-function gptel-make-ollama "gptel-ollama" (name &rest args))
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

(defun p3/gptel-sensitive-path-p (path)
  "Return non-nil when PATH has an obvious credential-like file name.

This is deliberately a narrow path-based guard for P3 convenience commands,
not a general secret-content scanner."
  (when path
    (let ((case-fold-search t)
          (name (file-name-nondirectory path)))
      (string-match-p
       "\\`\\(?:\\.env\\(?:\\..+\\)?\\|secrets?\\(?:\\..+\\)?\\|credentials?\\(?:\\..+\\)?\\)\\'"
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

(defun p3/gptel-add-git-diff ()
  "Add or explicitly refresh the current repository Git diff in GPTel context.

The context is a snapshot of staged and unstaged tracked changes against HEAD.
Untracked files are not included.  Re-running this command is the only way the
snapshot contents change."
  (interactive)
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
             (buffer
              (get-buffer-create (format "*GPTel Git Diff: %s*" project-name))))
        (with-current-buffer buffer
          (let ((inhibit-read-only t))
            (erase-buffer)
            (insert diff)
            (goto-char (point-min))
            (setq-local default-directory root)
            (when (fboundp 'diff-mode)
              (diff-mode))))
        ;; Use GPTel's own context variable rather than maintaining parallel P3
        ;; attachment state.  A stable buffer identity makes re-running this
        ;; command an explicit refresh of the already-attached snapshot.
        (unless (assoc buffer gptel-context)
          (push (list buffer) gptel-context))
        (message "GPTel context refreshed from tracked Git diff: %s" project-name)
        buffer))))

(defvar p3/gptel-command-map nil
  "Prefix map for GPTel project context and cut-out tasks.")

(setq p3/gptel-command-map
      (let ((map (make-sparse-keymap)))
        (define-key map (kbd "g") #'gptel)
        (define-key map (kbd "m") #'gptel-menu)
        (define-key map (kbd "a") #'gptel-add)
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
