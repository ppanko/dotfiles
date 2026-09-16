;;; p3-eat-feasibility-test.el --- Eat/Eshell platform gate -*- lexical-binding: t; -*-

(require 'ert)
(require 'eat)
(require 'p3-terminal-test-support)

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
          (let ((result (p3-terminal-test-support-run-fixture buffer 0)))
            (should (plist-get result :terminal))
            (should-not (plist-get result :raw-escape))
            (should (plist-get result :input-sent))
            (should (equal (plist-get result :tty) "1:1"))
            (should (equal (plist-get result :input) "78"))
            (should (> (car (plist-get result :size)) 0))
            (should (> (cdr (plist-get result :size)) 0))))
      (when (buffer-live-p buffer)
        (let ((kill-buffer-query-functions nil))
          (kill-buffer buffer))))))
