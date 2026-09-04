;;; p3-git.el --- Personal Git process helpers -*- lexical-binding: t; -*-

(require 'subr-x)

(defun p3/check-git-installed ()
  "Check if Git is installed."
  (unless (executable-find "git")
    (error "Git is not installed. Please install Git first.")))

(defun p3/get-commit-message ()
  "Prompt the user for a commit message. If empty, use the current date and time."
  (let ((commit-message (read-string "Commit message (leave blank for default): ")))
    (if (string= commit-message "")
        (format "Update: %s" (format-time-string "%Y-%m-%d %H:%M:%S"))
      commit-message)))

(defun p3/git-call (directory &rest arguments)
  "Run Git with ARGUMENTS in DIRECTORY and return (STATUS . OUTPUT)."
  (with-temp-buffer
    (let ((default-directory (file-name-as-directory directory)))
      (cons (apply #'process-file "git" nil (current-buffer) nil arguments)
            (buffer-string)))))

(defun p3/git-run (directory &rest arguments)
  "Run Git with ARGUMENTS in DIRECTORY, signaling an error on failure."
  (pcase-let ((`(,status . ,output)
               (apply #'p3/git-call directory arguments)))
    (unless (zerop status)
      (user-error "Git %s failed in %s: %s"
                  (string-join arguments " ")
                  directory
                  (string-trim output)))
    output))

(defun p3/git-commit-and-push-repository
    (directory add-arguments commit-message)
  "Stage ADD-ARGUMENTS, commit changes, and push DIRECTORY safely."
  (apply #'p3/git-run directory "add" add-arguments)
  (pcase-let ((`(,status . ,output)
               (p3/git-call directory "diff" "--cached" "--quiet" "--exit-code")))
    (cond
     ((zerop status)
      (message "No staged changes in %s" directory))
     ((= status 1)
      (p3/git-run directory "commit" "-m" commit-message))
     (t
      (user-error "Could not inspect staged changes in %s: %s"
                  directory (string-trim output)))))
  (p3/git-run directory "push" "--set-upstream" "origin" "HEAD"))

(defun p3/git-commit-and-push-emacs-config (&optional commit-message)
  "Commit and push the Emacs configuration and Org notes repositories.
If COMMIT-MESSAGE is nil or empty, use a timestamped default message."
  (interactive
   (progn
     (p3/check-git-installed)
     (list (p3/get-commit-message))))
  (let* ((config-dir (file-name-as-directory user-emacs-directory))
         (config-file (expand-file-name "config.org" config-dir))
         (notes-dir (expand-file-name "~/org/notes"))
         (final-message
          (if (and commit-message (not (string= commit-message "")))
              commit-message
            (p3/get-commit-message))))
    (cond
     ((not (file-exists-p config-file))
      (message "The config file %s does not exist." config-file))
     ((not (file-directory-p notes-dir))
      (message "The notes directory %s does not exist." notes-dir))
     (t
      (p3/check-git-installed)
      (p3/git-commit-and-push-repository
       config-dir '("-A") final-message)
      (p3/git-commit-and-push-repository
       notes-dir '("-u") final-message)
      (message "Committed and pushed changes to config and notes repositories.")))))

(defun close-magit-buffers ()
  "Close all Magit related buffers."
  (interactive)
  (dolist (buffer (buffer-list))
    (when (or (string-prefix-p "magit-" (buffer-name buffer))
              (string-prefix-p "*magit" (buffer-name buffer)))
      (kill-buffer buffer))))

(provide 'p3-git)

;;; p3-git.el ends here
