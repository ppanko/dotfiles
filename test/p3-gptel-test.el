;;; p3-gptel-test.el --- Tests for p3-gptel -*- lexical-binding: t; -*-

(require 'ert)
(require 'cl-lib)

(defconst p3-gptel-test--root
  (file-name-directory
   (directory-file-name
    (file-name-directory (or load-file-name buffer-file-name))))
  "Root of the Emacs configuration under test.")

(add-to-list 'load-path (expand-file-name "lisp" p3-gptel-test--root))

(require 'p3-gptel)

(defvar gptel-context)
(defvar gptel-use-context)
(defvar gptel-mode)

(defun p3-gptel-test--git (directory &rest args)
  "Run Git ARGS in DIRECTORY and return its exit status."
  (let ((default-directory (file-name-as-directory directory)))
    (apply #'process-file "git" nil nil nil args)))

(defun p3-gptel-test--write (directory file contents)
  "Write CONTENTS to FILE under DIRECTORY."
  (with-temp-file (expand-file-name file directory)
    (insert contents)))

(defun p3-gptel-test--init-repo (directory &optional file)
  "Initialize DIRECTORY with committed FILE and return DIRECTORY."
  (let ((file (or file "tracked.txt")))
    (should (zerop (p3-gptel-test--git directory "init" "-q")))
    (should (zerop (p3-gptel-test--git directory "config" "user.email" "p3@example.invalid")))
    (should (zerop (p3-gptel-test--git directory "config" "user.name" "P3 Test")))
    (p3-gptel-test--write directory file "base\n")
    (should (zerop (p3-gptel-test--git directory "add" file)))
    (should (zerop (p3-gptel-test--git directory "commit" "-q" "-m" "baseline")))
    directory))

(defun p3-gptel-test--context-buffer (entry)
  "Return the buffer represented by GPTel context ENTRY, if any."
  (cond
   ((bufferp entry) entry)
   ((bufferp (car-safe entry)) (car entry))))

(defun p3-gptel-test--kill-context-buffers (context)
  "Kill live buffers referenced by CONTEXT."
  (dolist (entry context)
    (when-let ((buffer (p3-gptel-test--context-buffer entry)))
      (when (buffer-live-p buffer)
        (kill-buffer buffer)))))

(ert-deftest p3-gptel-sensitive-path-detects-secret-like-files ()
  (should (fboundp 'p3/gptel-sensitive-path-p))
  (dolist (file '("/tmp/.env"
                  "/tmp/.env.local"
                  "/tmp/.env-prod"
                  "/tmp/secrets.el"
                  "/tmp/secrets-prod.env"
                  "/tmp/secret-key.txt"
                  "/tmp/credentials.json"
                  "/tmp/credentials-prod.json"
                  "/tmp/credentials_backup.yml"))
    (should (p3/gptel-sensitive-path-p file))))

(ert-deftest p3-gptel-sensitive-path-allows-ordinary-code ()
  (should (fboundp 'p3/gptel-sensitive-path-p))
  (dolist (file '("/tmp/analysis.py"
                  "/tmp/secretary.txt"
                  "/tmp/credentialsManager.el"))
    (should-not (p3/gptel-sensitive-path-p file))))

(ert-deftest p3-gptel-project-chat-localizes-context-and-project-directory ()
  "Project chat must not inherit or mutate the global GPTel context."
  (should (fboundp 'p3/gptel-project-chat))
  (let ((root (file-name-as-directory (make-temp-file "p3-gptel-project-" t)))
        (chat (generate-new-buffer " *p3-gptel-project-chat*"))
        (old-default (default-value 'gptel-context)))
    (unwind-protect
        (progn
          (set-default 'gptel-context '((global-context)))
          (cl-letf (((symbol-function 'project-current)
                     (lambda (&optional _maybe-prompt) 'project))
                    ((symbol-function 'project-root)
                     (lambda (_project) root))
                    ((symbol-function 'gptel)
                     (lambda () (interactive) chat)))
            (should (eq (p3/gptel-project-chat) chat)))
          (with-current-buffer chat
            (should (local-variable-p 'gptel-context))
            (should-not gptel-context)
            (should (equal default-directory root))
            (should (equal p3/gptel-project-root root)))
          (should (equal (default-value 'gptel-context) '((global-context)))))
      (set-default 'gptel-context old-default)
      (when (buffer-live-p chat) (kill-buffer chat))
      (delete-directory root t))))

(ert-deftest p3-gptel-project-chat-clears-context-when-reused-across-projects ()
  "Selecting a P3 chat from another project must not carry its context across."
  (let ((root-a (file-name-as-directory (make-temp-file "p3-gptel-project-a-" t)))
        (root-b (file-name-as-directory (make-temp-file "p3-gptel-project-b-" t)))
        (chat (generate-new-buffer " *p3-gptel-project-reuse*"))
        current-root)
    (unwind-protect
        (progn
          (with-current-buffer chat
            (setq-local gptel-context '((project-a-context))
                        p3/gptel-project-root root-a
                        default-directory root-a))
          (setq current-root root-b)
          (cl-letf (((symbol-function 'project-current)
                     (lambda (&optional _maybe-prompt) 'project))
                    ((symbol-function 'project-root)
                     (lambda (_project) current-root))
                    ((symbol-function 'gptel)
                     (lambda () (interactive) chat)))
            (p3/gptel-project-chat))
          (with-current-buffer chat
            (should-not gptel-context)
            (should (equal p3/gptel-project-root root-b))
            (should (equal default-directory root-b))))
      (when (buffer-live-p chat) (kill-buffer chat))
      (delete-directory root-a t)
      (delete-directory root-b t))))

(ert-deftest p3-gptel-git-diff-snapshot-includes-staged-and-unstaged-only ()
  (should (fboundp 'p3/gptel-git-diff-snapshot))
  (let ((directory (make-temp-file "p3-gptel-git-" t)))
    (unwind-protect
        (progn
          (should (zerop (p3-gptel-test--git directory "init" "-q")))
          (should (zerop (p3-gptel-test--git directory "config" "user.email" "p3@example.invalid")))
          (should (zerop (p3-gptel-test--git directory "config" "user.name" "P3 Test")))
          (p3-gptel-test--write directory "unstaged.txt" "base\n")
          (p3-gptel-test--write directory "staged.txt" "base\n")
          (should (zerop (p3-gptel-test--git directory "add" "unstaged.txt" "staged.txt")))
          (should (zerop (p3-gptel-test--git directory "commit" "-q" "-m" "baseline")))
          (p3-gptel-test--write directory "unstaged.txt" "unstaged change\n")
          (p3-gptel-test--write directory "staged.txt" "staged change\n")
          (should (zerop (p3-gptel-test--git directory "add" "staged.txt")))
          (p3-gptel-test--write directory "untracked.txt" "do not include\n")
          (let ((snapshot (p3/gptel-git-diff-snapshot directory)))
            (should (string-match-p "unstaged.txt" snapshot))
            (should (string-match-p "unstaged change" snapshot))
            (should (string-match-p "staged.txt" snapshot))
            (should (string-match-p "staged change" snapshot))
            (should-not (string-match-p "untracked.txt" snapshot))))
      (delete-directory directory t))))

(ert-deftest p3-gptel-git-diff-requires-target-chat-buffer ()
  "Diff context should attach only to an explicit GPTel chat session."
  (let ((directory (make-temp-file "p3-gptel-git-chat-" t)))
    (unwind-protect
        (progn
          (p3-gptel-test--init-repo directory)
          (p3-gptel-test--write directory "tracked.txt" "changed\n")
          (with-temp-buffer
            (setq default-directory (file-name-as-directory directory))
            (setq-local gptel-mode nil)
            (should-error (p3/gptel-add-git-diff) :type 'user-error)))
      (delete-directory directory t))))

(ert-deftest p3-gptel-git-diff-context-is-buffer-local ()
  "Adding a diff must not mutate GPTel's global default context."
  (let ((directory (make-temp-file "p3-gptel-git-local-" t))
        (old-default (default-value 'gptel-context))
        context)
    (unwind-protect
        (progn
          (p3-gptel-test--init-repo directory)
          (p3-gptel-test--write directory "tracked.txt" "changed\n")
          (set-default 'gptel-context nil)
          (with-temp-buffer
            (setq default-directory (file-name-as-directory directory))
            (setq-local gptel-mode t)
            (setq context (progn (p3/gptel-add-git-diff) gptel-context))
            (should (local-variable-p 'gptel-context))
            (should (= (length gptel-context) 1)))
          (should-not (default-value 'gptel-context)))
      (p3-gptel-test--kill-context-buffers context)
      (set-default 'gptel-context old-default)
      (delete-directory directory t))))

(ert-deftest p3-gptel-git-diff-refresh-keeps-prior-snapshot-immutable ()
  "Refreshing one chat replaces its attachment without mutating old evidence."
  (let ((directory (make-temp-file "p3-gptel-git-refresh-" t))
        context)
    (unwind-protect
        (progn
          (p3-gptel-test--init-repo directory)
          (p3-gptel-test--write directory "tracked.txt" "first change\n")
          (with-temp-buffer
            (setq default-directory (file-name-as-directory directory))
            (setq-local gptel-mode t)
            (setq-local gptel-context nil)
            (let* ((first (p3/gptel-add-git-diff))
                   (first-text (with-current-buffer first (buffer-string))))
              (p3-gptel-test--write directory "tracked.txt" "second change\n")
              (let ((second (p3/gptel-add-git-diff)))
                (setq context (copy-sequence gptel-context))
                (should-not (eq first second))
                (should (equal (with-current-buffer first (buffer-string)) first-text))
                (should (memq second (mapcar #'p3-gptel-test--context-buffer gptel-context)))
                (should-not (memq first (mapcar #'p3-gptel-test--context-buffer gptel-context)))
                (when (buffer-live-p first) (kill-buffer first))))))
      (p3-gptel-test--kill-context-buffers context)
      (delete-directory directory t))))

(ert-deftest p3-gptel-git-diff-same-basename-repositories-do-not-collide ()
  "Repositories with the same basename must get distinct snapshot buffers."
  (let* ((parent-a (make-temp-file "p3-gptel-parent-a-" t))
         (parent-b (make-temp-file "p3-gptel-parent-b-" t))
         (repo-a (expand-file-name "same-name" parent-a))
         (repo-b (expand-file-name "same-name" parent-b))
         snapshot-a snapshot-b context-a context-b)
    (make-directory repo-a)
    (make-directory repo-b)
    (unwind-protect
        (progn
          (p3-gptel-test--init-repo repo-a)
          (p3-gptel-test--init-repo repo-b)
          (p3-gptel-test--write repo-a "tracked.txt" "change a\n")
          (p3-gptel-test--write repo-b "tracked.txt" "change b\n")
          (with-temp-buffer
            (setq default-directory (file-name-as-directory repo-a))
            (setq-local gptel-mode t)
            (setq-local gptel-context nil)
            (setq snapshot-a (p3/gptel-add-git-diff)
                  context-a (copy-sequence gptel-context)))
          (with-temp-buffer
            (setq default-directory (file-name-as-directory repo-b))
            (setq-local gptel-mode t)
            (setq-local gptel-context nil)
            (setq snapshot-b (p3/gptel-add-git-diff)
                  context-b (copy-sequence gptel-context)))
          (should-not (eq snapshot-a snapshot-b))
          (should (string-match-p "change a" (with-current-buffer snapshot-a (buffer-string))))
          (should (string-match-p "change b" (with-current-buffer snapshot-b (buffer-string)))))
      (p3-gptel-test--kill-context-buffers context-a)
      (p3-gptel-test--kill-context-buffers context-b)
      (delete-directory parent-a t)
      (delete-directory parent-b t))))

(ert-deftest p3-gptel-git-diff-rejects-renamed-sensitive-path ()
  "A renamed secret must not evade the path-based diff guard."
  (let ((directory (make-temp-file "p3-gptel-secret-" t)))
    (unwind-protect
        (progn
          (should (zerop (p3-gptel-test--git directory "init" "-q")))
          (should (zerop (p3-gptel-test--git directory "config" "user.email" "p3@example.invalid")))
          (should (zerop (p3-gptel-test--git directory "config" "user.name" "P3 Test")))
          (p3-gptel-test--write directory ".env" "TOKEN=secret\n")
          (should (zerop (p3-gptel-test--git directory "add" ".env")))
          (should (zerop (p3-gptel-test--git directory "commit" "-q" "-m" "baseline")))
          (should (zerop (p3-gptel-test--git directory "mv" ".env" "settings.txt")))
          (with-temp-buffer
            (setq default-directory (file-name-as-directory directory))
            (setq-local gptel-mode t)
            (setq-local gptel-context nil)
            (should-error (p3/gptel-add-git-diff) :type 'user-error)))
      (delete-directory directory t))))

(ert-deftest p3-gptel-rewrite-native-entrypoint-is-autoloaded ()
  "Cut-out rewrite commands must work before gptel-rewrite has been loaded."
  (should (autoloadp (symbol-function 'gptel--suffix-rewrite))))

(ert-deftest p3-gptel-cutout-request-does-not-inherit-chat-context ()
  (should (fboundp 'p3/gptel-review-region))
  (with-temp-buffer
    (emacs-lisp-mode)
    (insert "(message \"hello\")")
    (set-mark (point-min))
    (goto-char (point-max))
    (setq mark-active t
          transient-mark-mode t)
    (let ((gptel-context '((interactive-context)))
          (gptel-use-context t)
          seen-context
          seen-use-context)
      (cl-letf (((symbol-function 'gptel-request)
                 (lambda (&optional _prompt &rest _args)
                   (setq seen-context gptel-context
                         seen-use-context gptel-use-context))))
        (p3/gptel-review-region))
      (should-not seen-context)
      (should-not seen-use-context))))

(ert-deftest p3-gptel-rewrite-task-does-not-inherit-chat-context ()
  (should (fboundp 'p3/gptel-refactor-region))
  (with-temp-buffer
    (emacs-lisp-mode)
    (insert "(message \"hello\")")
    (set-mark (point-min))
    (goto-char (point-max))
    (setq mark-active t
          transient-mark-mode t)
    (let ((gptel-context '((interactive-context)))
          (gptel-use-context t)
          seen-context
          seen-use-context
          seen-instruction)
      (cl-letf (((symbol-function 'gptel--suffix-rewrite)
                 (lambda (&optional instruction _dry-run)
                   (setq seen-context gptel-context
                         seen-use-context gptel-use-context
                         seen-instruction instruction))))
        (p3/gptel-refactor-region))
      (should-not seen-context)
      (should-not seen-use-context)
      (should (string-match-p "Refactor" seen-instruction)))))

(ert-deftest p3-gptel-ollama-registration-is-explicit-and-offline ()
  (should (fboundp 'p3/gptel-register-ollama))
  (let (call)
    (cl-letf (((symbol-function 'gptel-make-ollama)
               (lambda (name &rest args)
                 (setq call (cons name args))
                 'ollama-backend)))
      (should-not (p3/gptel-register-ollama nil "localhost:11434"))
      (should-not call)
      (should (eq (p3/gptel-register-ollama '(qwen3:8b) "localhost:11434")
                  'ollama-backend))
      (should (equal call
                     '("Ollama" :host "localhost:11434"
                       :models (qwen3:8b) :stream t))))))

(ert-deftest p3-gptel-command-map-exposes-two-mode-workflow ()
  (should (eq (keymap-lookup p3/gptel-command-map "g") #'p3/gptel-project-chat))
  (should (eq (keymap-lookup p3/gptel-command-map "m") 'gptel-menu))
  (should (eq (keymap-lookup p3/gptel-command-map "a") 'gptel-add))
  (should (eq (keymap-lookup p3/gptel-command-map "f") 'gptel-add-file))
  (should (eq (keymap-lookup p3/gptel-command-map "D") #'p3/gptel-add-git-diff))
  (should (eq (keymap-lookup p3/gptel-command-map "r") #'p3/gptel-refactor-region))
  (should (eq (keymap-lookup p3/gptel-command-map "d") #'p3/gptel-document-region))
  (should (eq (keymap-lookup p3/gptel-command-map "t") #'p3/gptel-write-tests))
  (should (eq (keymap-lookup p3/gptel-command-map "e") #'p3/gptel-explain-region))
  (should (eq (keymap-lookup p3/gptel-command-map "v") #'p3/gptel-review-region)))

(provide 'p3-gptel-test)

;;; p3-gptel-test.el ends here
