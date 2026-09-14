;;; p3-terminal.el --- Project-aware Bash shell helpers -*- lexical-binding: t; -*-

(require 'seq)
(require 'subr-x)
(require 'shell)
(require 'p3-platform)
(require 'p3-project)

(defgroup p3/terminal nil
  "Project-aware Bash shell sessions."
  :group 'applications)

(defvar p3/project-shell-buffers (make-hash-table :test #'equal)
  "Map local project roots to their primary P3 shell buffers.")

(defvar-local p3/project-shell-root-value nil
  "Local root associated with the current P3 shell buffer.")

(defun p3/project-shell-root ()
  "Return the local project root or local current directory."
  (let ((root (or (p3/project-root) default-directory)))
    (when (file-remote-p root)
      (user-error "Project shell requires a local project or directory"))
    (file-name-as-directory (expand-file-name root))))

(defun p3/project-shell-buffer-name (root)
  "Return a stable primary shell buffer name for ROOT."
  (format "*shell:%s:%s*"
          (file-name-nondirectory (directory-file-name root))
          (substring (secure-hash 'sha1 root) 0 6)))

(defun p3/project-shell--start (name root)
  "Start the platform Bash in buffer NAME at ROOT and return the buffer."
  (let ((buffer (get-buffer-create name)))
    (with-current-buffer buffer
      (setq default-directory root))
    (let ((default-directory root)
          (explicit-shell-file-name (p3/platform-bash-program)))
      (save-window-excursion
        (shell name)))
    (or (get-buffer name)
        (user-error "Bash shell did not create buffer %s" name))))

(defun p3/project-shell-buffer (&optional new-session)
  "Return the project shell, creating a NEW-SESSION when requested."
  (let* ((root (p3/project-shell-root))
         (base-name (p3/project-shell-buffer-name root))
         (primary (and (not new-session)
                       (gethash root p3/project-shell-buffers))))
    (when (and primary (not (buffer-live-p primary)))
      (remhash root p3/project-shell-buffers)
      (setq primary nil))
    (if (buffer-live-p primary)
        primary
      (let* ((name (if new-session
                       (generate-new-buffer-name base-name)
                     base-name))
             (buffer
              (let ((default-directory root))
                (p3/project-shell--start name root))))
        (with-current-buffer buffer
          (setq-local p3/project-shell-root-value root))
        (unless new-session
          (puthash root buffer p3/project-shell-buffers))
        buffer))))

(defun p3/project-shell-buffer-p (buffer)
  "Return non-nil when BUFFER is a live P3 project shell."
  (and (buffer-live-p buffer)
       (buffer-local-value 'p3/project-shell-root-value buffer)))

(defun p3/project-shell-buffers ()
  "Return all live P3 project shell buffers."
  (seq-filter #'p3/project-shell-buffer-p (buffer-list)))

(defun p3/project-shell-read-buffer ()
  "Prompt for and return a live P3 project shell buffer."
  (let ((buffers (p3/project-shell-buffers)))
    (unless buffers
      (user-error "There are no live project shell sessions"))
    (get-buffer
     (completing-read "Project shell: " (mapcar #'buffer-name buffers) nil t))))

(defun p3/project-shell (&optional new-session)
  "Switch the current window to its project Bash shell.
With a prefix argument, create a NEW-SESSION.  When already in a P3 project
shell, switch back to the previous buffer instead of hiding or deleting the
window."
  (interactive "P")
  (if (and (p3/project-shell-buffer-p (current-buffer))
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
  "Kill the current P3 project shell, or prompt for one to kill."
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
