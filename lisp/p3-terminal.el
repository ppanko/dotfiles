;;; p3-terminal.el --- Project-aware terminal helpers -*- lexical-binding: t; -*-

(require 'seq)
(require 'subr-x)
(require 'p3-core)

(declare-function vterm-mode "vterm")
(declare-function vterm-copy-mode "vterm")

(defgroup p3/terminal nil
  "Project-aware terminal sessions."
  :group 'applications)

(defconst p3/blesh-revision
  "63c23e99f1f7133ae57b79f87b16d1f68cd39884"
  "Pinned ble.sh revision used by the terminal bootstrapper.")

(defcustom p3/blesh-source-url "https://github.com/akinomyoga/ble.sh.git"
  "Git repository used to bootstrap ble.sh."
  :type 'string
  :group 'p3/terminal)

(defcustom p3/blesh-install-directory
  (expand-file-name
   "blesh"
   (file-name-as-directory
    (or (getenv "XDG_DATA_HOME")
        (expand-file-name ".local/share" (or (getenv "HOME") "~")))))
  "Directory where the pinned ble.sh build is installed."
  :type 'directory
  :group 'p3/terminal)

(defvar p3/vterm-project-buffers (make-hash-table :test #'equal)
  "Map project roots to their primary terminal buffers.")

(defun p3/blesh-file ()
  "Return the expected path of the bootstrapped ble.sh entry point."
  (expand-file-name "ble.sh" p3/blesh-install-directory))

(defun p3/terminal--run (program &rest arguments)
  "Run PROGRAM with ARGUMENTS or show its output and signal an error."
  (let ((buffer (get-buffer-create "*Terminal bootstrap*")))
    (with-current-buffer buffer
      (goto-char (point-max))
      (insert (format "$ %s %s\n" program
                      (mapconcat #'shell-quote-argument arguments " "))))
    (let ((status (apply #'call-process program nil buffer t arguments)))
      (unless (and (integerp status) (zerop status))
        (display-buffer buffer)
        (user-error "Terminal bootstrap command failed (%s): %s"
                    status program)))))

(defun p3/install-blesh ()
  "Install the pinned ble.sh revision into user-local data storage."
  (interactive)
  (let ((missing (seq-remove #'executable-find '("git" "make" "gawk"))))
    (when missing
      (user-error "Cannot install ble.sh; missing programs: %s"
                  (string-join missing ", "))))
  (let* ((build-root (make-temp-file "p3-blesh-build-" t))
         (source-directory (expand-file-name "source" build-root))
         (documentation-directory
          (expand-file-name
           "doc/blesh"
           (file-name-directory
            (directory-file-name p3/blesh-install-directory)))))
    (unwind-protect
        (progn
          (make-directory source-directory t)
          (p3/terminal--run "git" "-C" source-directory "init")
          (p3/terminal--run
           "git" "-C" source-directory "remote" "add" "origin"
           p3/blesh-source-url)
          (p3/terminal--run
           "git" "-C" source-directory "fetch" "--depth" "1" "origin"
           p3/blesh-revision)
          (p3/terminal--run
           "git" "-C" source-directory "checkout" "--detach" "FETCH_HEAD")
          (p3/terminal--run
           "git" "-C" source-directory "submodule" "update" "--init"
           "--recursive" "--depth" "1")
          (p3/terminal--run
           "make" "-C" source-directory "install"
           (format "INSDIR=%s" p3/blesh-install-directory)
           (format "INSDIR_DOC=%s" documentation-directory))
          (unless (file-readable-p (p3/blesh-file))
            (user-error "ble.sh installation did not produce %s"
                        (p3/blesh-file)))
          (message "Installed pinned ble.sh revision %s"
                   (substring p3/blesh-revision 0 8)))
      (delete-directory build-root t))))

(defun p3/ensure-blesh ()
  "Offer to install ble.sh when terminal highlighting is unavailable."
  (unless (file-readable-p (p3/blesh-file))
    (if (and (not noninteractive)
             (y-or-n-p "ble.sh is missing; install syntax highlighting now? "))
        (p3/install-blesh)
      (message "Terminal started without syntax highlighting; run M-x p3/install-blesh"))))

(defun p3/vterm-check-prerequisites ()
  "Check prerequisites needed to load or compile the vterm module."
  (unless module-file-suffix
    (user-error "This Emacs lacks dynamic-module support required by vterm"))
  (unless (locate-library "vterm-module")
    (let ((missing
           (seq-remove #'executable-find '("cc" "cmake" "libtool" "make"))))
      (when missing
        (user-error
         "Cannot compile vterm; install these system build tools: %s"
         (string-join missing ", "))))))

(defun p3/vterm-root ()
  "Return the project root or current directory for a terminal."
  (file-name-as-directory
   (expand-file-name (or (p3/project-root) default-directory))))

(defun p3/vterm-buffer-name (root)
  "Return a stable terminal buffer name for ROOT."
  (format "*vterm:%s:%s*"
          (file-name-nondirectory (directory-file-name root))
          (substring (secure-hash 'sha1 root) 0 6)))

(defun p3/vterm-buffer (&optional new-session)
  "Return the project terminal, creating a NEW-SESSION when requested."
  (p3/vterm-check-prerequisites)
  (p3/ensure-blesh)
  (require 'vterm)
  (let* ((root (p3/vterm-root))
         (name (p3/vterm-buffer-name root))
         (primary (and (not new-session)
                       (gethash root p3/vterm-project-buffers)))
         (buffer (if (buffer-live-p primary)
                     primary
                   (if new-session
                       (generate-new-buffer name)
                     (get-buffer-create name)))))
    (with-current-buffer buffer
      (unless (derived-mode-p 'vterm-mode)
        (setq default-directory root)
        (vterm-mode)))
    (unless new-session
      (puthash root buffer p3/vterm-project-buffers))
    buffer))

(defun p3/vterm (&optional new-session)
  "Switch the current window to its project terminal.
With a prefix argument, create a NEW-SESSION.  When already in a terminal,
switch back to the previous buffer instead of hiding or deleting the window."
  (interactive "P")
  (if (and (derived-mode-p 'vterm-mode) (not new-session))
      (switch-to-prev-buffer)
    (switch-to-buffer (p3/vterm-buffer new-session))))

(defun p3/vterm-new ()
  "Create another terminal for the current project in this window."
  (interactive)
  (switch-to-buffer (p3/vterm-buffer t)))

(defun p3/vterm-buffers ()
  "Return all live vterm buffers."
  (seq-filter
   (lambda (buffer)
     (with-current-buffer buffer
       (derived-mode-p 'vterm-mode)))
   (buffer-list)))

(defun p3/vterm-read-buffer ()
  "Prompt for and return a live vterm buffer."
  (let ((buffers (p3/vterm-buffers)))
    (unless buffers
      (user-error "There are no live terminal sessions"))
    (get-buffer
     (completing-read "Terminal: " (mapcar #'buffer-name buffers) nil t))))

(defun p3/vterm-switch ()
  "Switch the current window to an existing terminal session."
  (interactive)
  (switch-to-buffer (p3/vterm-read-buffer)))

(defun p3/vterm-other-window (&optional new-session)
  "Open the project terminal in another ordinary window.
With a prefix argument, create a NEW-SESSION there."
  (interactive "P")
  (switch-to-buffer-other-window (p3/vterm-buffer new-session)))

(defun p3/vterm-maximize (&optional new-session)
  "Open the project terminal and give it the entire frame.
With a prefix argument, create a NEW-SESSION first.  The previous window
layout remains recoverable through `winner-undo'."
  (interactive "P")
  (switch-to-buffer (p3/vterm-buffer new-session))
  (delete-other-windows))

(defun p3/vterm-rename (name)
  "Rename the current terminal to NAME."
  (interactive "sTerminal name: ")
  (unless (derived-mode-p 'vterm-mode)
    (user-error "The current buffer is not a terminal"))
  (rename-buffer (format "*vterm:%s*" name) t))

(defun p3/vterm-enter-copy-mode ()
  "Enter vterm copy mode for normal Emacs navigation and selection."
  (interactive)
  (unless (derived-mode-p 'vterm-mode)
    (user-error "The current buffer is not a terminal"))
  (vterm-copy-mode 1)
  (message "Vterm copy mode enabled; press RET to copy and exit"))

(defun p3/vterm-mode-setup ()
  "Make Emacs editing keys cooperate with the terminal emulator.
CUA's paste command inserts directly into buffers and therefore cannot work in
vterm's process-owned display.  Disable CUA only in this buffer; vterm's yank
commands still use the normal Emacs kill ring and system clipboard."
  (setq-local cua-mode nil))

(defun p3/vterm-kill ()
  "Kill the current terminal, or prompt for one to kill."
  (interactive)
  (kill-buffer
   (if (derived-mode-p 'vterm-mode)
       (current-buffer)
     (p3/vterm-read-buffer))))

(defalias 'p3/vterm-toggle #'p3/vterm)
(defalias 'p3/vterm-open-here #'p3/vterm)

(defvar-keymap p3/vterm-command-map
  :doc "Commands for project-aware terminal sessions."
  "t" #'p3/vterm
  "n" #'p3/vterm-new
  "s" #'p3/vterm-switch
  "o" #'p3/vterm-other-window
  "f" #'p3/vterm-maximize
  "r" #'p3/vterm-rename
  "c" #'p3/vterm-enter-copy-mode
  "k" #'p3/vterm-kill)

(provide 'p3-terminal)

;;; p3-terminal.el ends here
