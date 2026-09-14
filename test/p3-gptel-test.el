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

(defun p3-gptel-test--git (directory &rest args)
  "Run Git ARGS in DIRECTORY and return its exit status."
  (let ((default-directory (file-name-as-directory directory)))
    (apply #'process-file "git" nil nil nil args)))

(defun p3-gptel-test--write (directory file contents)
  "Write CONTENTS to FILE under DIRECTORY."
  (with-temp-file (expand-file-name file directory)
    (insert contents)))

(ert-deftest p3-gptel-sensitive-path-detects-secret-like-files ()
  (should (fboundp 'p3/gptel-sensitive-path-p))
  (dolist (file '("/tmp/.env"
                  "/tmp/.env.local"
                  "/tmp/secrets.el"
                  "/tmp/credentials.json"))
    (should (p3/gptel-sensitive-path-p file))))

(ert-deftest p3-gptel-sensitive-path-allows-ordinary-code ()
  (should (fboundp 'p3/gptel-sensitive-path-p))
  (should-not (p3/gptel-sensitive-path-p "/tmp/analysis.py")))

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
          (let ((default-directory (file-name-as-directory directory)))
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
  (should (eq (keymap-lookup p3/gptel-command-map "g") 'gptel))
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
