;;; p3-terminal-rich-ux-test.el --- Adversarial project shell UX tests -*- lexical-binding: t; -*-

(require 'ert)
(require 'cl-lib)
(require 'ring)
(require 'seq)

(defconst p3-terminal-rich-ux-test--root
  (file-name-directory
   (directory-file-name
    (file-name-directory (or load-file-name buffer-file-name))))
  "Root of the Emacs configuration under test.")

(add-to-list 'load-path
             (expand-file-name "lisp" p3-terminal-rich-ux-test--root))

(require 'p3-terminal)

(defun p3-terminal-rich-ux-test--wait-for-output (buffer process regexp)
  "Return non-nil when REGEXP appears in BUFFER while PROCESS is live."
  (let ((deadline (+ (float-time) 10.0))
        found)
    (while (and (not found) (< (float-time) deadline))
      (accept-process-output process 0.1)
      (with-current-buffer buffer
        (save-excursion
          (goto-char (point-min))
          (setq found (re-search-forward regexp nil t)))))
    found))

(defun p3-terminal-rich-ux-test--exit-shell (process)
  "Exit PROCESS normally and fail if it remains live."
  (when (process-live-p process)
    (process-send-string process "exit\n")
    (let ((deadline (+ (float-time) 10.0)))
      (while (and (process-live-p process) (< (float-time) deadline))
        (accept-process-output process 0.1)))
    (should-not (process-live-p process))))

(ert-deftest p3-terminal-prompt-pattern-rejects-prompt-like-command-output ()
  (dolist (line '("cost $ 20"
                  "hash # tag"
                  "progress % done"
                  "redirect > file"))
    (should-not (string-match-p p3/project-shell-prompt-pattern line)))
  (should
   (string-match-p p3/project-shell-prompt-pattern
                   "~/src/project git:main ! ❯ ")))

(ert-deftest p3-terminal-linux-missing-rich-terminfo-keeps-safe-default ()
  (unless (eq system-type 'gnu/linux)
    (ert-skip "GNU/Linux-only terminfo fallback regression"))
  (let* ((root (file-name-as-directory
                (expand-file-name "p3-terminfo-fallback"
                                  temporary-file-directory)))
         (name "*p3-terminfo-fallback-test*")
         (comint-terminfo-terminal "dumb")
         captured-term)
    (unwind-protect
        (cl-letf (((symbol-function 'p3/windows-p) (lambda () nil))
                  ((symbol-function 'p3/platform-bash-program)
                   (lambda () "/bin/bash"))
                  ((symbol-function 'executable-find)
                   (lambda (_program) nil))
                  ((symbol-function 'shell)
                   (lambda (buffer-name &optional _file-name)
                     (setq captured-term comint-terminfo-terminal)
                     (get-buffer-create buffer-name))))
          (p3/project-shell--start name root)
          (should (equal captured-term "dumb")))
      (when-let ((buffer (get-buffer name)))
        (kill-buffer buffer)))))

(ert-deftest p3-terminal-concurrent-shells-preserve-clean-shared-history ()
  (let* ((raw-root (make-temp-file "p3-shared-history-" t))
         (root (p3/project-normalize-root raw-root))
         (home (expand-file-name "home" raw-root))
         (history-file (expand-file-name "p3-history" raw-root))
         (msys-root (getenv "P3_TEST_MSYS2_ROOT"))
         (linuxy-environment-path
          (if (eq system-type 'windows-nt)
              (and msys-root
                   (file-name-as-directory
                    (expand-file-name "usr/bin" msys-root)))
            linuxy-environment-path))
         (shell-file-name shell-file-name)
         (explicit-shell-file-name explicit-shell-file-name)
         (explicit-bash.exe-args
          (and (boundp 'explicit-bash.exe-args) explicit-bash.exe-args))
         (shell-mode-hook shell-mode-hook)
         (process-environment (copy-sequence process-environment))
         (names '("*p3-history-one*" "*p3-history-two*" "*p3-history-three*"))
         buffers
         processes)
    (make-directory home)
    ;; Force a hostile startup state so the project-shell contract, rather than
    ;; the runner's personal Bash defaults, must provide append-only history.
    (with-temp-file (expand-file-name ".bashrc" home)
      (insert "shopt -u histappend\n"))
    (setenv "HOME" home)
    (setenv "HISTFILE" history-file)
    (unwind-protect
        (progn
          (when (eq system-type 'windows-nt)
            (unless msys-root
              (ert-skip "P3_TEST_MSYS2_ROOT is required for Windows shell smoke"))
            (p3/windows-configure-shell))
          (unless (or (eq system-type 'windows-nt) (executable-find "bash"))
            (ert-skip "Bash is unavailable for shared-history smoke"))
          (let* ((first (p3/project-shell--start (nth 0 names) root))
                 (second (p3/project-shell--start (nth 1 names) root))
                 (first-process (get-buffer-process first))
                 (second-process (get-buffer-process second)))
            (setq buffers (list first second)
                  processes (list first-process second-process))
            (should (process-live-p first-process))
            (should (process-live-p second-process))
            (process-send-string first-process "echo __P3_HISTORY_ONE__\n")
            (process-send-string second-process "echo __P3_HISTORY_TWO__\n")
            (should (p3-terminal-rich-ux-test--wait-for-output
                     first first-process "__P3_HISTORY_ONE__"))
            (should (p3-terminal-rich-ux-test--wait-for-output
                     second second-process "__P3_HISTORY_TWO__"))
            (p3-terminal-rich-ux-test--exit-shell first-process)
            (p3-terminal-rich-ux-test--exit-shell second-process))
          (let* ((third (p3/project-shell--start (nth 2 names) root))
                 (third-process (get-buffer-process third)))
            (push third buffers)
            (push third-process processes)
            (should (process-live-p third-process))
            (process-send-string
             third-process
             "if shopt -q histappend; then echo __P3_HISTAPPEND_ON__; else echo __P3_HISTAPPEND_OFF__; fi\n")
            (should (p3-terminal-rich-ux-test--wait-for-output
                     third third-process "__P3_HISTAPPEND_ON__"))
            (with-current-buffer third
              (let ((entries (ring-elements comint-input-ring)))
                (should (seq-some
                         (lambda (entry)
                           (string-match-p "__P3_HISTORY_ONE__" entry))
                         entries))
                (should (seq-some
                         (lambda (entry)
                           (string-match-p "__P3_HISTORY_TWO__" entry))
                         entries))
                (should-not
                 (seq-some
                  (lambda (entry)
                    (or (string-match-p "starship init bash" entry)
                        (string-match-p "__p3_starship_init" entry)
                        (string-match-p "PS1=.*❯" entry)))
                  entries))))))
      (dolist (process processes)
        (when (and process (process-live-p process))
          (delete-process process)))
      (dolist (buffer buffers)
        (when (and buffer (buffer-live-p buffer))
          (let ((kill-buffer-query-functions nil))
            (kill-buffer buffer))))
      (delete-directory raw-root t))))

(provide 'p3-terminal-rich-ux-test)

;;; p3-terminal-rich-ux-test.el ends here
