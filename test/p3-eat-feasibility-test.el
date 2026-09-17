;;; p3-eat-feasibility-test.el --- Eat/Eshell platform gate -*- lexical-binding: t; -*-

(require 'ert)
(require 'eat)
(require 'p3-terminal)
(require 'p3-terminal-test-support)

(defun p3-eat-feasibility-test--assert-result (result)
  "Assert the supported terminal contract represented by RESULT."
  (should (plist-get result :terminal))
  (should-not (plist-get result :raw-escape))
  (should (plist-get result :input-sent))
  (should (equal (plist-get result :input) "78"))
  ;; GNU/Linux is the platform on which terminal-native applications such as
  ;; Codex are part of the project-shell contract.  Native Windows only needs
  ;; ordinary Eshell/external-command behavior; a real PTY is not required.
  (unless (eq system-type 'windows-nt)
    (should (equal (plist-get result :tty) "1:1"))
    (should (> (car (plist-get result :size)) 0))
    (should (> (cdr (plist-get result :size)) 0))))

(ert-deftest p3-eat-feasibility-supported-eshell-terminal-path ()
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
          (p3-eat-feasibility-test--assert-result
           (p3-terminal-test-support-run-fixture buffer 0)))
      (when (buffer-live-p buffer)
        (let ((kill-buffer-query-functions nil))
          (kill-buffer buffer))))))

(ert-deftest p3-eat-feasibility-p3-project-shell-returns-cleanly ()
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
                (p3-eat-feasibility-test--assert-result
                 (p3-terminal-test-support-run-fixture buffer exit-code)))
              (should (p3/project-shell-live-p buffer))
              (should (eq buffer (p3/project-shell-buffer)))
              (with-current-buffer buffer
                (should-not (eshell-head-process))))
          (when (buffer-live-p buffer)
            (let ((kill-buffer-query-functions nil))
              (kill-buffer buffer))))))))
