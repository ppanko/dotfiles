;;; p3-terminal-test-support.el --- Shared terminal test helpers -*- lexical-binding: t; -*-

(require 'ert)
(require 'eshell)
(require 'esh-proc)
(require 'p3-platform)

(defconst p3-terminal-test-support-root
  (file-name-directory
   (directory-file-name
    (file-name-directory (or load-file-name buffer-file-name)))))

(defun p3-terminal-test-support-python ()
  (or (executable-find "python3")
      (executable-find "python")
      (ert-skip "Python is unavailable for terminal fixture")))

(defun p3-terminal-test-support-prepare-platform ()
  (when (eq system-type 'windows-nt)
    (let* ((msys-root
            (or (getenv "P3_TEST_MSYS2_ROOT")
                (ert-skip "P3_TEST_MSYS2_ROOT is required on Windows")))
           (usr-bin (file-name-as-directory
                     (expand-file-name "usr/bin" msys-root))))
      (setq linuxy-environment-path usr-bin)
      (p3/windows-path-prepend usr-bin))))

(defun p3-terminal-test-support-run-fixture (buffer exit-code)
  "Run the terminal fixture in BUFFER and return an observation plist."
  (let* ((fixture (expand-file-name "test/fixtures/p3-terminal-fixture.py"
                                    p3-terminal-test-support-root))
         (python (p3-terminal-test-support-python))
         (command (mapconcat #'shell-quote-argument
                             (list python fixture (number-to-string exit-code))
                             " "))
         (deadline (+ (float-time) 5.0))
         observed-terminal
         observed-raw-escape
         input-sent
         finished)
    (with-current-buffer buffer
      (goto-char (point-max))
      (insert command)
      (eshell-send-input))
    (while (and (not finished) (< (float-time) deadline))
      (accept-process-output nil 0.05)
      (when (buffer-live-p buffer)
        (with-current-buffer buffer
          (unless input-sent
            (save-excursion
              (goto-char (point-min))
              (when (search-forward "__P3_CURSOR__" nil t)
                (setq observed-terminal t)
                (goto-char (point-min))
                (setq observed-raw-escape
                      (search-forward "\033[" nil t))
                (when-let ((proc (eshell-head-process)))
                  (process-send-string proc "x")
                  (setq input-sent t)))))
          (save-excursion
            (goto-char (point-min))
            (setq finished
                  (and input-sent
                       (re-search-forward "__P3_INPUT__[0-9a-f]+" nil t)))))))
    (unless finished
      (when (buffer-live-p buffer)
        (with-current-buffer buffer
          (when-let ((proc (eshell-head-process)))
            (delete-process proc)))))
    (with-current-buffer buffer
      (let (tty size input)
        (save-excursion
          (goto-char (point-min))
          (when (re-search-forward "__P3_TTY__\\([01]:[01]\\)" nil t)
            (setq tty (match-string-no-properties 1)))
          (goto-char (point-min))
          (when (re-search-forward
                 "__P3_SIZE__\\([0-9]+\\):\\([0-9]+\\)" nil t)
            (setq size (cons (string-to-number
                              (match-string-no-properties 1))
                             (string-to-number
                              (match-string-no-properties 2)))))
          (goto-char (point-min))
          (when (re-search-forward "__P3_INPUT__\\([0-9a-f]+\\)" nil t)
            (setq input (match-string-no-properties 1))))
        (list :terminal observed-terminal
              :raw-escape observed-raw-escape
              :input-sent input-sent
              :tty tty
              :size size
              :input input
              :finished finished)))))

(defun p3-terminal-test-support--eat-child (parent)
  "Return PARENT's dedicated Eat child, if one exists."
  (seq-find
   (lambda (buffer)
     (and (buffer-live-p buffer)
          (with-current-buffer buffer
            (and (derived-mode-p 'eat-mode)
                 (boundp 'eshell-parent-buffer)
                 (eq eshell-parent-buffer parent)))))
   (buffer-list)))

(defun p3-terminal-test-support--wait-for-eat-child (parent)
  "Wait briefly for PARENT's dedicated Eat child."
  (let ((deadline (+ (float-time) 3.0))
        child)
    (while (and (not (setq child (p3-terminal-test-support--eat-child parent)))
                (< (float-time) deadline))
      (accept-process-output nil 0.05))
    (should (buffer-live-p child))
    child))

(defun p3-terminal-test-support--wait-for-text (buffer regexp)
  "Wait briefly for REGEXP to appear in BUFFER."
  (let ((deadline (+ (float-time) 3.0))
        found)
    (while (and (buffer-live-p buffer)
                (not found)
                (< (float-time) deadline))
      (accept-process-output (get-buffer-process buffer) 0.05)
      (with-current-buffer buffer
        (save-excursion
          (goto-char (point-min))
          (setq found (re-search-forward regexp nil t)))))
    (should found)))

(ert-deftest p3-terminal-sudo-password-is-read-invisibly-in-eat ()
  "Visual sudo prompts must use masked input and never expose the secret."
  (when (eq system-type 'windows-nt)
    (ert-skip "Native Windows full-screen TUI/PTY behavior is out of scope"))
  (p3-terminal-test-support-prepare-platform)
  (should (p3/project-shell-eat-supported-p))
  (let* ((compiler (or (executable-find "cc")
                       (ert-skip "C compiler is unavailable for sudo fixture")))
         (raw-root (make-temp-file "p3-sudo-password-" t))
         (root (p3/project-normalize-root raw-root))
         (bin-dir (expand-file-name "bin" raw-root))
         (sudo (expand-file-name "sudo" bin-dir))
         (fixture (expand-file-name "test/fixtures/p3-sudo-password-fixture.c"
                                    p3-terminal-test-support-root))
         (p3/project-shell-buffers (make-hash-table :test #'equal))
         (process-environment (copy-sequence process-environment))
         (exec-path (copy-sequence exec-path))
         (password-reads 0)
         parent child)
    (make-directory bin-dir t)
    (should (zerop (call-process compiler nil nil nil fixture "-O0" "-o" sudo)))
    (push bin-dir exec-path)
    (setenv "PATH" (concat bin-dir path-separator (getenv "PATH")))
    (setenv "P3_TEST_SUDO_PASSWORD" "p3-secret")
    (setenv "P3_TEST_SUDO_PROMPTS" "2")
    (setenv "P3_TEST_SUDO_EXIT" "7")
    (unwind-protect
        (cl-letf (((symbol-function 'p3/project-shell-root) (lambda () root))
                  ((symbol-function 'read-passwd)
                   (lambda (&rest _)
                     (setq password-reads (1+ password-reads))
                     "p3-secret")))
          (add-hook 'eat-exit-hook #'p3/project-shell-eat-visual-buffer-exit)
          (setq parent (p3/project-shell-buffer))
          (with-current-buffer parent
            (goto-char (point-max))
            (insert "sudo pacman -S demo")
            (eshell-send-input))
          (setq child (p3-terminal-test-support--wait-for-eat-child parent))
          (p3-terminal-test-support--wait-for-text child "__P3_SUDO_OK__2")
          (should (= password-reads 2))
          (with-current-buffer child
            (goto-char (point-min))
            (should-not (search-forward "p3-secret" nil t)))
          (with-current-buffer parent
            (goto-char (point-min))
            (should-not (search-forward "p3-secret" nil t))))
      (remove-hook 'eat-exit-hook #'p3/project-shell-eat-visual-buffer-exit)
      (dolist (buffer (list child parent))
        (when (buffer-live-p buffer)
          (let ((kill-buffer-query-functions nil))
            (kill-buffer buffer))))
      (delete-directory raw-root t))))

(provide 'p3-terminal-test-support)
