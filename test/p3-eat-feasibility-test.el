;;; p3-eat-feasibility-test.el --- Eat/Eshell platform gate -*- lexical-binding: t; -*-

(require 'cl-lib)
(require 'ert)
(require 'seq)
(require 'eat)
(require 'p3-terminal)
(require 'p3-terminal-test-support)

(defun p3-eat-feasibility-test--assert-linux-terminal-result (result)
  "Assert the full GNU/Linux terminal contract represented by RESULT."
  (should (plist-get result :terminal))
  (should-not (plist-get result :raw-escape))
  (should (plist-get result :input-sent))
  (should (equal (plist-get result :input) "78"))
  (should (equal (plist-get result :tty) "1:1"))
  (should (> (car (plist-get result :size)) 0))
  (should (> (cdr (plist-get result :size)) 0)))

(defun p3-eat-feasibility-test--wait-for-child-exit (buffer)
  "Wait for BUFFER's current Eshell child process to be fully reaped."
  (with-current-buffer buffer
    (let ((deadline (+ (float-time) 5.0))
          process)
      (while (and (setq process (eshell-head-process))
                  (< (float-time) deadline))
        (accept-process-output process 0.05))
      (should-not (eshell-head-process)))))

(defun p3-eat-feasibility-test--run-command (buffer command regexp)
  "Run COMMAND in BUFFER and require REGEXP in its resulting output."
  (with-current-buffer buffer
    (let ((start (point-max))
          (deadline (+ (float-time) 10.0))
          found)
      (goto-char (point-max))
      (insert command)
      (eshell-send-input)
      (while (and (not found) (< (float-time) deadline))
        (if-let ((process (eshell-head-process)))
            (accept-process-output process 0.05)
          (accept-process-output nil 0.05))
        (save-excursion
          (goto-char start)
          (setq found (re-search-forward regexp nil t))))
      (should found))))

(ert-deftest p3-eat-feasibility-supported-eshell-terminal-path ()
  (when (eq system-type 'windows-nt)
    (ert-skip "Native Windows full-screen TUI/PTY behavior is out of scope"))
  (p3-terminal-test-support-prepare-platform)
  (should (executable-find "stty"))
  (should (executable-find "env"))
  (should (executable-find "sh"))
  (let* ((eshell-buffer-name "*p3-eat-feasibility*")
         (eat-eshell-fallback-if-stty-not-available t)
         (buffer (save-window-excursion (eshell))))
    (unwind-protect
        (progn
          (eat-eshell-mode 1)
          (p3-eat-feasibility-test--assert-linux-terminal-result
           (p3-terminal-test-support-run-fixture buffer 0)))
      (when (buffer-live-p buffer)
        (let ((kill-buffer-query-functions nil))
          (kill-buffer buffer))))))

(ert-deftest p3-eat-feasibility-p3-project-shell-returns-cleanly ()
  (when (eq system-type 'windows-nt)
    (ert-skip "Native Windows full-screen TUI/PTY behavior is out of scope"))
  (p3-terminal-test-support-prepare-platform)
  (let ((root (file-name-as-directory temporary-file-directory))
        (p3/project-shell-buffers (make-hash-table :test #'equal))
        (eat-eshell-fallback-if-stty-not-available t))
    (cl-letf (((symbol-function 'p3/project-shell-root) (lambda () root)))
      (let ((buffer (p3/project-shell-buffer)))
        (unwind-protect
            (progn
              (eat-eshell-mode 1)
              (dolist (exit-code '(0 7))
                (p3-eat-feasibility-test--assert-linux-terminal-result
                 (p3-terminal-test-support-run-fixture buffer exit-code))
                (p3-eat-feasibility-test--wait-for-child-exit buffer))
              (should (p3/project-shell-live-p buffer))
              (should (eq buffer (p3/project-shell-buffer))))
          (when (buffer-live-p buffer)
            (let ((kill-buffer-query-functions nil))
              (kill-buffer buffer))))))))

(ert-deftest p3-eat-feasibility-windows-falls-back-without-stty ()
  (unless (eq system-type 'windows-nt)
    (ert-skip "Native Windows-only no-stty fallback contract"))
  (p3-terminal-test-support-prepare-platform)
  (let* ((git-program (or (executable-find "git")
                          (ert-fail "git is required for Windows fallback test")))
         (msys-root (or (getenv "P3_TEST_MSYS2_ROOT")
                        (ert-fail "P3_TEST_MSYS2_ROOT is required")))
         (usr-bin (file-name-as-directory
                   (expand-file-name "usr/bin" msys-root)))
         ;; Eat decides whether its in-Eshell terminal path is available by
         ;; looking up stty.  Hide the MSYS2 usr/bin directory from Emacs while
         ;; invoking git by absolute path; the process environment itself is
         ;; otherwise unchanged.
         (exec-path
          (seq-remove
           (lambda (directory)
             (and directory
                  (equal (file-truename (file-name-as-directory directory))
                         (file-truename usr-bin))))
           exec-path))
         (root (file-name-as-directory temporary-file-directory))
         (p3/project-shell-buffers (make-hash-table :test #'equal))
         (eat-eshell-fallback-if-stty-not-available t)
         buffer)
    (should-not (executable-find "stty"))
    (unwind-protect
        (cl-letf (((symbol-function 'p3/project-shell-root) (lambda () root)))
          (setq buffer (p3/project-shell-buffer))
          (with-current-buffer buffer
            (eat-eshell-mode 1)
            (should (derived-mode-p 'eshell-mode)))
          (p3-eat-feasibility-test--run-command
           buffer
           (concat (shell-quote-argument git-program) " --version")
           "git version")
          (p3-eat-feasibility-test--wait-for-child-exit buffer)
          (should (p3/project-shell-live-p buffer)))
      (when (and buffer (buffer-live-p buffer))
        (let ((kill-buffer-query-functions nil))
          (kill-buffer buffer))))))

(ert-deftest p3-eat-feasibility-windows-project-shell-runs-normal-cli-tools ()
  (unless (eq system-type 'windows-nt)
    (ert-skip "Native Windows-only ordinary CLI contract"))
  (p3-terminal-test-support-prepare-platform)
  (should (executable-find "git"))
  (should (executable-find "bash"))
  (let* ((raw-root (make-temp-file "p3-windows-eshell-" t))
         (root (p3/project-normalize-root raw-root))
         (p3/project-shell-buffers (make-hash-table :test #'equal))
         (eat-eshell-fallback-if-stty-not-available t)
         buffer)
    (unwind-protect
        (cl-letf (((symbol-function 'p3/project-shell-root) (lambda () root)))
          (setq buffer (p3/project-shell-buffer))
          (with-current-buffer buffer
            (eat-eshell-mode 1)
            (should (derived-mode-p 'eshell-mode))
            (should (equal p3/project-shell-root-value root))
            (should (equal (p3/project-normalize-root default-directory) root)))
          (p3-eat-feasibility-test--run-command
           buffer "git --version" "git version")
          (p3-eat-feasibility-test--wait-for-child-exit buffer)
          (p3-eat-feasibility-test--run-command
           buffer "bash --version" "GNU bash")
          (p3-eat-feasibility-test--wait-for-child-exit buffer)
          (should (p3/project-shell-live-p buffer))
          (should (eq buffer (p3/project-shell-buffer))))
      (when (and buffer (buffer-live-p buffer))
        (let ((kill-buffer-query-functions nil))
          (kill-buffer buffer)))
      (delete-directory raw-root t))))
